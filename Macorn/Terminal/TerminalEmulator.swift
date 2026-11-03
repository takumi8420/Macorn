import Foundation

/// 文字の色。端末の既定の色・256 色の番号・フルカラーのどれか
nonisolated enum TerminalColor: Equatable, Sendable {
    case standard
    case indexed(UInt8)
    case rgb(UInt8, UInt8, UInt8)
}

/// 文字の見た目（色・太字など）
nonisolated struct TerminalAttributes: Equatable, Sendable {
    var foreground = TerminalColor.standard
    var background = TerminalColor.standard
    var bold = false
    var dim = false
    var italic = false
    var underline = false
    var inverse = false
}

/// 画面の1マス
nonisolated struct TerminalCell: Equatable, Sendable {
    var character: Character = " "
    /// 1 = ふつう、2 = 全角の左半分、0 = 全角の右半分（中身は左のマスにある）
    var width: UInt8 = 1
    var attributes = TerminalAttributes()

    static let blank = TerminalCell()
}

/// 端末の画面（制御文字を読み取り、升目の中身とカーソルを持つ）。xterm 互換の主な命令に対応する。
nonisolated final class TerminalEmulator {
    private(set) var columns: Int
    private(set) var rows: Int
    /// いま見えている画面（全画面のアプリが使う別画面のときはそちら）
    private(set) var lines: [[TerminalCell]]
    /// 上へ流れていった行（ふだんの画面だけ）
    private(set) var scrollback: [[TerminalCell]] = []
    let maxScrollback = 5000

    private(set) var cursorX = 0
    private(set) var cursorY = 0
    private(set) var cursorVisible = true
    private(set) var isAlternateScreen = false
    /// 矢印キーを「ESC O A」の形で送る（vim などが求める）
    private(set) var applicationCursorKeys = false
    /// 貼り付けを ESC [200~ 〜 ESC [201~ で囲む
    private(set) var bracketedPaste = false
    private(set) var title = ""
    /// シェルが知らせてきた今のフォルダ（OSC 7）
    private(set) var reportedDirectory: String?
    /// 端末からシェルへ返す応答（カーソル位置の問い合わせなど）
    var respond: ((String) -> Void)?
    /// 中身が変わった回数（描画の判断用）
    private(set) var revision = 0

    private var attributes = TerminalAttributes()
    private var pendingWrap = false
    private var autoWrap = true
    private var scrollTop = 0
    private var scrollBottom: Int
    private var savedCursor: (x: Int, y: Int, attributes: TerminalAttributes) = (0, 0, TerminalAttributes())
    private var otherLines: [[TerminalCell]]
    private var tabStops: Set<Int> = []

    // 読み取りの状態
    private enum State { case ground, escape, escapeIntermediate, csi, osc, oscEscape, dcs, dcsEscape }
    private var state = State.ground
    private var parameters: [UInt8] = []
    private var intermediates: [UInt8] = []
    private var oscBuffer: [UInt8] = []
    private var utf8Buffer: [UInt8] = []
    private var utf8Expected = 0

    init(columns: Int, rows: Int) {
        self.columns = max(columns, 2)
        self.rows = max(rows, 1)
        lines = Self.blankLines(count: max(rows, 1), columns: max(columns, 2))
        otherLines = Self.blankLines(count: max(rows, 1), columns: max(columns, 2))
        scrollBottom = max(rows, 1) - 1
        resetTabStops()
    }

    private static func blankLines(count: Int, columns: Int) -> [[TerminalCell]] {
        Array(repeating: Array(repeating: .blank, count: columns), count: count)
    }

    private func blankLine() -> [TerminalCell] {
        // 消した部分は、今の背景色で塗る（xterm と同じ）
        var cell = TerminalCell.blank
        cell.attributes.background = attributes.background
        return Array(repeating: cell, count: columns)
    }

    private func resetTabStops() {
        tabStops = Set(stride(from: 8, to: columns, by: 8))
    }

    /// 画面の文字（行ごと、右端の空白を除く）。テストと自動操作用
    var screenText: [String] {
        lines.map { Self.text(of: $0) }
    }

    static func text(of line: [TerminalCell]) -> String {
        var text = ""
        for cell in line where cell.width != 0 { text.append(cell.character) }
        while text.last == " " { text.removeLast() }
        return text
    }

    // MARK: - 受け取り

    func feed(_ data: Data) {
        for byte in data { feed(byte: byte) }
        revision &+= 1
    }

    func feed(_ text: String) { feed(Data(text.utf8)) }

    private func feed(byte: UInt8) {
        // UTF-8 の途中のバイト
        if utf8Expected > 0 {
            if byte & 0xC0 == 0x80 {
                utf8Buffer.append(byte)
                if utf8Buffer.count == utf8Expected {
                    let scalar = String(decoding: utf8Buffer, as: UTF8.self).unicodeScalars.first
                    utf8Buffer = []
                    utf8Expected = 0
                    if let scalar { handle(scalar: scalar) }
                }
                return
            }
            // 壊れた並び
            utf8Buffer = []
            utf8Expected = 0
            handle(scalar: "\u{FFFD}")
        }
        if byte >= 0x80, state == .ground || state == .osc {
            if state == .osc {
                oscBuffer.append(byte)
                return
            }
            switch byte {
            case 0xC0...0xDF: utf8Expected = 2
            case 0xE0...0xEF: utf8Expected = 3
            case 0xF0...0xF7: utf8Expected = 4
            default:
                handle(scalar: "\u{FFFD}")
                return
            }
            utf8Buffer = [byte]
            return
        }
        handle(byte: byte)
    }

    private func handle(scalar: Unicode.Scalar) {
        guard state == .ground else { return }
        printCharacter(scalar)
    }

    private func handle(byte: UInt8) {
        switch state {
        case .ground:
            if byte < 0x20 || byte == 0x7F {
                control(byte)
            } else {
                printCharacter(Unicode.Scalar(byte))
            }
        case .escape:
            escape(byte)
        case .escapeIntermediate:
            // 文字の集合の切り替え（ESC ( B など）は扱わない
            state = .ground
        case .csi:
            if byte == 0x1B {
                state = .escape
            } else if byte < 0x20 {
                control(byte)
            } else if (0x30...0x3F).contains(byte) {
                parameters.append(byte)
            } else if (0x20...0x2F).contains(byte) {
                intermediates.append(byte)
            } else if (0x40...0x7E).contains(byte) {
                state = .ground
                csi(final: byte)
            } else {
                state = .ground
            }
        case .osc:
            if byte == 0x07 {
                state = .ground
                osc()
            } else if byte == 0x1B {
                state = .oscEscape
            } else {
                oscBuffer.append(byte)
            }
        case .oscEscape:
            state = .ground
            osc()
            if byte != 0x5C { handle(byte: byte) }
        case .dcs:
            if byte == 0x1B { state = .dcsEscape }
        case .dcsEscape:
            state = byte == 0x5C ? .ground : .dcs
        }
    }

    // MARK: - 制御文字

    private func control(_ byte: UInt8) {
        switch byte {
        case 0x08: // BS
            if cursorX > 0 { cursorX -= 1 }
            pendingWrap = false
        case 0x09: // TAB
            let next = tabStops.filter { $0 > cursorX }.min() ?? (columns - 1)
            cursorX = min(next, columns - 1)
        case 0x0A, 0x0B, 0x0C: // LF
            lineFeed()
        case 0x0D: // CR
            cursorX = 0
            pendingWrap = false
        case 0x1B:
            state = .escape
            parameters = []
            intermediates = []
        default:
            break
        }
    }

    private func escape(_ byte: UInt8) {
        state = .ground
        switch byte {
        case UInt8(ascii: "["):
            state = .csi
            parameters = []
            intermediates = []
        case UInt8(ascii: "]"):
            state = .osc
            oscBuffer = []
        case UInt8(ascii: "P"):
            state = .dcs
        case UInt8(ascii: "("), UInt8(ascii: ")"), UInt8(ascii: "*"), UInt8(ascii: "+"), UInt8(ascii: "#"), UInt8(ascii: "%"):
            state = .escapeIntermediate
        case UInt8(ascii: "7"): saveCursor()
        case UInt8(ascii: "8"): restoreCursor()
        case UInt8(ascii: "D"): lineFeed()
        case UInt8(ascii: "E"):
            cursorX = 0
            lineFeed()
        case UInt8(ascii: "M"): reverseIndex()
        case UInt8(ascii: "H"): tabStops.insert(cursorX)
        case UInt8(ascii: "c"): reset()
        default:
            break
        }
    }

    // MARK: - 文字を置く

    private func printCharacter(_ scalar: Unicode.Scalar) {
        let width = Self.width(of: scalar)
        if width == 0 {
            appendCombining(scalar)
            return
        }
        if pendingWrap {
            if autoWrap {
                cursorX = 0
                lineFeed()
            }
            pendingWrap = false
        }
        if width == 2, cursorX == columns - 1 {
            // 全角が右端に入らないときは、次の行へ
            if autoWrap {
                put(.blank, at: cursorX, cursorY)
                cursorX = 0
                lineFeed()
            } else {
                return
            }
        }
        put(TerminalCell(character: Character(scalar), width: UInt8(width), attributes: attributes), at: cursorX, cursorY)
        if width == 2, cursorX + 1 < columns {
            put(TerminalCell(character: " ", width: 0, attributes: attributes), at: cursorX + 1, cursorY)
        }
        cursorX += width
        if cursorX >= columns {
            cursorX = columns - 1
            pendingWrap = true
        }
    }

    /// x, y のマスに置く。全角の片側だけを上書きするときは、もう片側を消す
    private func put(_ cell: TerminalCell, at x: Int, _ y: Int) {
        guard (0..<columns).contains(x), (0..<rows).contains(y) else { return }
        let old = lines[y][x]
        // 全角の右半分を上書きするなら、左半分を消す（全角の右半分を置くときは、左半分は今置いたものなので消さない）
        if old.width == 0, cell.width != 0, x > 0, lines[y][x - 1].width == 2 { lines[y][x - 1] = .blank }
        // 全角の左半分を上書きするなら、右半分を消す
        if old.width == 2, x + 1 < columns, lines[y][x + 1].width == 0 { lines[y][x + 1] = .blank }
        lines[y][x] = cell
    }

    /// 結合文字（濁点・異体字セレクタなど）は、直前の文字にくっつける
    private func appendCombining(_ scalar: Unicode.Scalar) {
        var x = pendingWrap ? cursorX : cursorX - 1
        var y = cursorY
        if x < 0 {
            guard y > 0 else { return }
            y -= 1
            x = columns - 1
        }
        if lines[y][x].width == 0, x > 0 { x -= 1 }
        let combined = String(lines[y][x].character) + String(scalar)
        if combined.count == 1 { lines[y][x].character = Character(combined) }
    }

    /// 文字の幅（全角は 2、結合文字は 0）
    static func width(of scalar: Unicode.Scalar) -> Int {
        let value = scalar.value
        if value < 0x300 { return 1 }
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .enclosingMark, .format:
            return 0
        default:
            break
        }
        if (0x1F3FB...0x1F3FF).contains(value) { return 0 } // 肌の色
        for range in wideRanges where range.contains(value) { return 2 }
        return 1
    }

    private static let wideRanges: [ClosedRange<UInt32>] = [
        0x1100...0x115F, 0x231A...0x231B, 0x2329...0x232A, 0x23E9...0x23EC, 0x23F0...0x23F0, 0x23F3...0x23F3,
        0x25FD...0x25FE, 0x2614...0x2615, 0x2648...0x2653, 0x267F...0x267F, 0x2693...0x2693, 0x26A1...0x26A1,
        0x26AA...0x26AB, 0x26BD...0x26BE, 0x26C4...0x26C5, 0x26CE...0x26CE, 0x26D4...0x26D4, 0x26EA...0x26EA,
        0x26F2...0x26F3, 0x26F5...0x26F5, 0x26FA...0x26FA, 0x26FD...0x26FD, 0x2705...0x2705, 0x270A...0x270B,
        0x2728...0x2728, 0x274C...0x274C, 0x274E...0x274E, 0x2753...0x2755, 0x2757...0x2757, 0x2795...0x2797,
        0x27B0...0x27B0, 0x27BF...0x27BF, 0x2B1B...0x2B1C, 0x2B50...0x2B50, 0x2B55...0x2B55,
        0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xA000...0xA4CF, 0xA960...0xA97F,
        0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE10...0xFE19, 0xFE30...0xFE6F, 0xFF00...0xFF60, 0xFFE0...0xFFE6,
        0x1F004...0x1F004, 0x1F0CF...0x1F0CF, 0x1F18E...0x1F18E, 0x1F191...0x1F19A, 0x1F200...0x1F251,
        0x1F300...0x1F64F, 0x1F680...0x1F6FF, 0x1F900...0x1F9FF, 0x1FA70...0x1FAFF,
        0x20000...0x2FFFD, 0x30000...0x3FFFD,
    ]

    // MARK: - 行の送り・スクロール

    private func lineFeed() {
        pendingWrap = false
        if cursorY == scrollBottom {
            scrollUp(1)
        } else if cursorY < rows - 1 {
            cursorY += 1
        }
    }

    private func reverseIndex() {
        pendingWrap = false
        if cursorY == scrollTop {
            scrollDown(1)
        } else if cursorY > 0 {
            cursorY -= 1
        }
    }

    private func scrollUp(_ count: Int) {
        let count = min(count, scrollBottom - scrollTop + 1)
        for _ in 0..<count {
            let removed = lines.remove(at: scrollTop)
            if !isAlternateScreen, scrollTop == 0 {
                scrollback.append(removed)
                if scrollback.count > maxScrollback { scrollback.removeFirst(scrollback.count - maxScrollback) }
            }
            lines.insert(blankLine(), at: scrollBottom)
        }
    }

    private func scrollDown(_ count: Int) {
        let count = min(count, scrollBottom - scrollTop + 1)
        for _ in 0..<count {
            lines.remove(at: scrollBottom)
            lines.insert(blankLine(), at: scrollTop)
        }
    }

    // MARK: - CSI

    private func csi(final: UInt8) {
        let raw = String(decoding: parameters, as: UTF8.self)
        var marker: Character?
        var body = Substring(raw)
        if let first = body.first, "?>=<".contains(first) {
            marker = first
            body = body.dropFirst()
        }
        let params = body.split(separator: ";", omittingEmptySubsequences: false)
            .flatMap { $0.split(separator: ":", omittingEmptySubsequences: false) }
            .map { Int($0) }
        func param(_ index: Int, _ fallback: Int = 1) -> Int {
            guard index < params.count, let value = params[index], value > 0 else { return fallback }
            return value
        }
        let intermediate = intermediates.first

        if intermediate != nil {
            // カーソルの形（CSI n SP q）などは扱わない
            return
        }

        switch Character(Unicode.Scalar(final)) {
        case "@": insertBlanks(param(0))
        case "A": moveCursor(toX: cursorX, y: max(cursorY - param(0), cursorY >= scrollTop ? scrollTop : 0))
        case "B", "e": moveCursor(toX: cursorX, y: min(cursorY + param(0), cursorY <= scrollBottom ? scrollBottom : rows - 1))
        case "C", "a": moveCursor(toX: cursorX + param(0), y: cursorY)
        case "D": moveCursor(toX: cursorX - param(0), y: cursorY)
        case "E": moveCursor(toX: 0, y: cursorY + param(0))
        case "F": moveCursor(toX: 0, y: cursorY - param(0))
        case "G", "`": moveCursor(toX: param(0) - 1, y: cursorY)
        case "H", "f": moveCursor(toX: param(1) - 1, y: param(0) - 1)
        case "d": moveCursor(toX: cursorX, y: param(0) - 1)
        case "J": eraseInDisplay(params.first.flatMap { $0 } ?? 0)
        case "K": eraseInLine(params.first.flatMap { $0 } ?? 0)
        case "L": insertLines(param(0))
        case "M": deleteLines(param(0))
        case "P": deleteCharacters(param(0))
        case "X": eraseCharacters(param(0))
        case "S": scrollUp(param(0))
        case "T": if marker == nil { scrollDown(param(0)) }
        case "m": if marker == nil { selectGraphicRendition(params) }
        case "r":
            if marker == nil { setScrollRegion(top: param(0), bottom: param(1, rows)) }
        case "s": if marker == nil { saveCursor() }
        case "u": if marker == nil { restoreCursor() }
        case "h": setModes(params, marker: marker, enabled: true)
        case "l": setModes(params, marker: marker, enabled: false)
        case "n":
            if marker == nil {
                if params.first == 6 { respond?("\u{1B}[\(cursorY + 1);\(cursorX + 1)R") }
                if params.first == 5 { respond?("\u{1B}[0n") }
            }
        case "c":
            if marker == nil { respond?("\u{1B}[?1;2c") }
            if marker == ">" { respond?("\u{1B}[>0;10;0c") }
        case "g":
            let mode = params.first.flatMap { $0 } ?? 0
            if mode == 0 { tabStops.remove(cursorX) }
            if mode == 3 { tabStops.removeAll() }
        default:
            break
        }
    }

    private func moveCursor(toX x: Int, y: Int) {
        cursorX = min(max(x, 0), columns - 1)
        cursorY = min(max(y, 0), rows - 1)
        pendingWrap = false
    }

    private func eraseInDisplay(_ mode: Int) {
        pendingWrap = false
        switch mode {
        case 0:
            eraseInLine(0)
            for y in (cursorY + 1)..<rows { lines[y] = blankLine() }
        case 1:
            eraseInLine(1)
            for y in 0..<cursorY { lines[y] = blankLine() }
        case 2:
            for y in 0..<rows { lines[y] = blankLine() }
        case 3:
            scrollback.removeAll()
        default:
            break
        }
    }

    private func eraseInLine(_ mode: Int) {
        let range: Range<Int>
        switch mode {
        case 0: range = cursorX..<columns
        case 1: range = 0..<(cursorX + 1)
        default: range = 0..<columns
        }
        let blank = blankLine()[0]
        for x in range { lines[cursorY][x] = blank }
        fixBrokenWideCharacters(row: cursorY)
    }

    private func eraseCharacters(_ count: Int) {
        let blank = blankLine()[0]
        for x in cursorX..<min(cursorX + count, columns) { lines[cursorY][x] = blank }
        fixBrokenWideCharacters(row: cursorY)
    }

    private func insertBlanks(_ count: Int) {
        let count = min(count, columns - cursorX)
        var line = lines[cursorY]
        line.insert(contentsOf: Array(repeating: blankLine()[0], count: count), at: cursorX)
        line.removeLast(count)
        lines[cursorY] = line
        fixBrokenWideCharacters(row: cursorY)
    }

    private func deleteCharacters(_ count: Int) {
        let count = min(count, columns - cursorX)
        var line = lines[cursorY]
        line.removeSubrange(cursorX..<(cursorX + count))
        line.append(contentsOf: Array(repeating: blankLine()[0], count: count))
        lines[cursorY] = line
        fixBrokenWideCharacters(row: cursorY)
    }

    /// 全角の片側だけが残ったマスを空白にする
    private func fixBrokenWideCharacters(row y: Int) {
        for x in 0..<columns {
            let cell = lines[y][x]
            if cell.width == 0, x == 0 || lines[y][x - 1].width != 2 { lines[y][x] = .blank }
            if cell.width == 2, x + 1 >= columns || lines[y][x + 1].width != 0 { lines[y][x] = .blank }
        }
    }

    private func insertLines(_ count: Int) {
        guard (scrollTop...scrollBottom).contains(cursorY) else { return }
        for _ in 0..<min(count, scrollBottom - cursorY + 1) {
            lines.remove(at: scrollBottom)
            lines.insert(blankLine(), at: cursorY)
        }
        cursorX = 0
    }

    private func deleteLines(_ count: Int) {
        guard (scrollTop...scrollBottom).contains(cursorY) else { return }
        for _ in 0..<min(count, scrollBottom - cursorY + 1) {
            lines.remove(at: cursorY)
            lines.insert(blankLine(), at: scrollBottom)
        }
        cursorX = 0
    }

    private func setScrollRegion(top: Int, bottom: Int) {
        let top = max(top, 1) - 1
        let bottom = min(bottom, rows) - 1
        guard top < bottom else { return }
        scrollTop = top
        scrollBottom = bottom
        moveCursor(toX: 0, y: 0)
    }

    private func saveCursor() {
        savedCursor = (cursorX, cursorY, attributes)
    }

    private func restoreCursor() {
        moveCursor(toX: savedCursor.x, y: savedCursor.y)
        attributes = savedCursor.attributes
    }

    private func setModes(_ params: [Int?], marker: Character?, enabled: Bool) {
        guard marker == "?" else { return }
        for mode in params.compactMap({ $0 }) {
            switch mode {
            case 1: applicationCursorKeys = enabled
            case 7: autoWrap = enabled
            case 25: cursorVisible = enabled
            case 47, 1047: switchScreen(alternate: enabled, clear: mode == 1047 && enabled)
            case 1048: enabled ? saveCursor() : restoreCursor()
            case 1049:
                if enabled {
                    saveCursor()
                    switchScreen(alternate: true, clear: true)
                } else {
                    switchScreen(alternate: false, clear: false)
                    restoreCursor()
                }
            case 2004: bracketedPaste = enabled
            default: break
            }
        }
    }

    /// 全画面のアプリ（vim・less など）が使う別画面と、ふだんの画面を切り替える
    private func switchScreen(alternate: Bool, clear: Bool) {
        guard alternate != isAlternateScreen else {
            if clear { lines = Self.blankLines(count: rows, columns: columns) }
            return
        }
        swap(&lines, &otherLines)
        isAlternateScreen = alternate
        if clear, alternate { lines = Self.blankLines(count: rows, columns: columns) }
        scrollTop = 0
        scrollBottom = rows - 1
        pendingWrap = false
    }

    private func reset() {
        if isAlternateScreen { switchScreen(alternate: false, clear: false) }
        attributes = TerminalAttributes()
        lines = Self.blankLines(count: rows, columns: columns)
        scrollTop = 0
        scrollBottom = rows - 1
        cursorX = 0
        cursorY = 0
        pendingWrap = false
        autoWrap = true
        cursorVisible = true
        applicationCursorKeys = false
        bracketedPaste = false
        resetTabStops()
    }

    // MARK: - 色と文字の見た目（SGR）

    private func selectGraphicRendition(_ params: [Int?]) {
        let values = params.isEmpty ? [0] : params.map { $0 ?? 0 }
        var index = 0
        while index < values.count {
            let value = values[index]
            switch value {
            case 0: attributes = TerminalAttributes()
            case 1: attributes.bold = true
            case 2: attributes.dim = true
            case 3: attributes.italic = true
            case 4: attributes.underline = true
            case 7: attributes.inverse = true
            case 21, 22:
                attributes.bold = false
                attributes.dim = false
            case 23: attributes.italic = false
            case 24: attributes.underline = false
            case 27: attributes.inverse = false
            case 30...37: attributes.foreground = .indexed(UInt8(value - 30))
            case 39: attributes.foreground = .standard
            case 40...47: attributes.background = .indexed(UInt8(value - 40))
            case 49: attributes.background = .standard
            case 90...97: attributes.foreground = .indexed(UInt8(value - 90 + 8))
            case 100...107: attributes.background = .indexed(UInt8(value - 100 + 8))
            case 38, 48:
                var color: TerminalColor?
                if index + 2 < values.count, values[index + 1] == 5 {
                    color = .indexed(UInt8(clamping: values[index + 2]))
                    index += 2
                } else if index + 4 < values.count, values[index + 1] == 2 {
                    color = .rgb(UInt8(clamping: values[index + 2]), UInt8(clamping: values[index + 3]), UInt8(clamping: values[index + 4]))
                    index += 4
                }
                if let color {
                    if value == 38 { attributes.foreground = color } else { attributes.background = color }
                }
            default:
                break
            }
            index += 1
        }
    }

    // MARK: - OSC（題名・今のフォルダ）

    private func osc() {
        let text = String(decoding: oscBuffer, as: UTF8.self)
        oscBuffer = []
        guard let separator = text.firstIndex(of: ";") else { return }
        let code = text[..<separator]
        let value = String(text[text.index(after: separator)...])
        switch code {
        case "0", "2": title = value
        case "7":
            // file://ホスト名/パス
            if let url = URL(string: value), url.isFileURL { reportedDirectory = url.path }
        default:
            break
        }
    }

    // MARK: - 大きさの変更

    func resize(columns newColumns: Int, rows newRows: Int) {
        let newColumns = max(newColumns, 2)
        let newRows = max(newRows, 1)
        guard newColumns != columns || newRows != rows else { return }

        func fit(_ line: [TerminalCell]) -> [TerminalCell] {
            if line.count >= newColumns {
                var cut = Array(line.prefix(newColumns))
                if cut.last?.width == 2 { cut[newColumns - 1] = .blank }
                return cut
            }
            return line + Array(repeating: .blank, count: newColumns - line.count)
        }

        func fitRows(_ screen: [[TerminalCell]], keepingCursor: Bool) -> (lines: [[TerminalCell]], removedTop: Int) {
            var screen = screen.map(fit)
            var removedTop = 0
            if newRows < screen.count {
                let excess = screen.count - newRows
                // カーソルが見えなくならないよう、上の行から押し出す
                removedTop = keepingCursor ? min(excess, max(0, cursorY - (newRows - 1))) : 0
                let top = Array(screen.prefix(removedTop))
                screen.removeFirst(removedTop)
                screen.removeLast(excess - removedTop)
                if keepingCursor, !isAlternateScreen { scrollback.append(contentsOf: top.map(fit)) }
            } else if newRows > screen.count {
                screen += Array(repeating: Array(repeating: .blank, count: newColumns), count: newRows - screen.count)
            }
            return (screen, removedTop)
        }

        scrollback = scrollback.map(fit)
        let current = fitRows(lines, keepingCursor: true)
        let other = fitRows(otherLines, keepingCursor: false)
        columns = newColumns
        rows = newRows
        lines = current.lines
        otherLines = other.lines
        cursorY -= current.removedTop
        cursorX = min(cursorX, columns - 1)
        cursorY = min(max(cursorY, 0), rows - 1)
        scrollTop = 0
        scrollBottom = rows - 1
        pendingWrap = false
        resetTabStops()
        if scrollback.count > maxScrollback { scrollback.removeFirst(scrollback.count - maxScrollback) }
        revision &+= 1
    }
}
