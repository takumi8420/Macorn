import AppKit

/// 端末の画面を描き、キー入力（日本語入力を含む）をシェルへ送る。
final class TerminalView: NSView, NSTextInputClient {
    let emulator: TerminalEmulator
    /// シェルへ送る（キー入力・貼り付け）
    var send: ((Data) -> Void)?
    /// 画面の行数・桁数が変わった
    var onResize: ((Int, Int) -> Void)?
    /// フォーカスを得た・失った
    var onFocusChange: ((Bool) -> Void)?
    /// シェルが終わったあとに Return を押した（新しく開き直す）
    var onRestartRequest: (() -> Void)?
    var isProcessExited = false

    private var font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private var boldFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
    private(set) var cellWidth: CGFloat = 7
    private(set) var cellHeight: CGFloat = 15
    private var baseline: CGFloat = 12
    private let inset = NSSize(width: 6, height: 4)

    /// 上へ戻って見ている行数（0 = いちばん下）
    private var scrollOffset = 0
    private var scrollRemainder: CGFloat = 0
    /// 日本語入力の変換中の文字
    private var markedText = NSAttributedString()
    /// 選択の始まりと終わり（行は「流れた行＋画面」を通した番号）
    private var selectionStart: (row: Int, column: Int)?
    private var selectionEnd: (row: Int, column: Int)?

    init(emulator: TerminalEmulator) {
        self.emulator = emulator
        super.init(frame: .zero)
        // macOS 14 からは自分の枠の外にも描けてしまうので、上のヘッダーを塗りつぶさないよう枠で切る
        clipsToBounds = true
        updateFontMetrics()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        onFocusChange?(true)
        return true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        onFocusChange?(false)
        return true
    }

    private var isFocused: Bool { window?.firstResponder === self && window?.isKeyWindow == true }

    private func updateFontMetrics() {
        // 端数を切り上げると、全角（2 マス）の文字の間が空きすぎるので、そのままの幅を使う
        cellWidth = ("M" as NSString).size(withAttributes: [.font: font]).width
        cellHeight = ceil(font.ascender - font.descender + font.leading) + 2
        baseline = ceil(font.ascender) + 1
    }

    // MARK: - 大きさ

    var gridSize: (columns: Int, rows: Int) {
        let columns = Int((bounds.width - inset.width * 2) / cellWidth)
        let rows = Int((bounds.height - inset.height * 2) / cellHeight)
        return (max(columns, 2), max(rows, 1))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let size = gridSize
        if size.columns != emulator.columns || size.rows != emulator.rows {
            emulator.resize(columns: size.columns, rows: size.rows)
            onResize?(size.columns, size.rows)
        }
    }

    /// 新しい出力が届いた
    func contentDidChange() {
        if scrollOffset > emulator.scrollback.count { scrollOffset = emulator.scrollback.count }
        needsDisplay = true
    }

    // MARK: - 描画

    override func draw(_ dirtyRect: NSRect) {
        let background = NSColor.textBackgroundColor
        background.setFill()
        dirtyRect.intersection(bounds).fill()

        let scrollback = emulator.scrollback
        let screen = emulator.lines
        let rows = emulator.rows
        let firstRow = scrollback.count - scrollOffset

        for y in 0..<rows {
            let absolute = firstRow + y
            let line: [TerminalCell]
            if absolute < scrollback.count {
                line = absolute >= 0 ? scrollback[absolute] : []
            } else {
                let index = absolute - scrollback.count
                line = index < screen.count ? screen[index] : []
            }
            let top = inset.height + CGFloat(y) * cellHeight
            let rowRect = NSRect(x: 0, y: top, width: bounds.width, height: cellHeight)
            guard rowRect.intersects(dirtyRect) else { continue }
            drawLine(line, row: absolute, top: top)
        }

        drawCursor(firstRow: firstRow)
    }

    private func drawLine(_ line: [TerminalCell], row: Int, top: CGFloat) {
        var x = 0
        while x < line.count {
            let cell = line[x]
            if cell.width == 0 {
                x += 1
                continue
            }
            // 同じ見た目の半角の文字は、まとめて描く（等幅なので位置がずれない）
            var text = String(cell.character)
            var span = Int(cell.width)
            let isASCII = cell.character.isASCII && cell.width == 1
            if isASCII {
                var next = x + 1
                while next < line.count, line[next].width == 1, line[next].character.isASCII,
                      line[next].attributes == cell.attributes {
                    text.append(line[next].character)
                    span += 1
                    next += 1
                }
            }
            let selected = isSelected(row: row, column: x)
            let colors = self.colors(for: cell.attributes, selected: selected)
            let rect = NSRect(x: inset.width + CGFloat(x) * cellWidth, y: top, width: CGFloat(span) * cellWidth, height: cellHeight)
            if colors.background != NSColor.textBackgroundColor || selected {
                colors.background.setFill()
                rect.fill()
            }
            if text.contains(where: { $0 != " " }) {
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: cell.attributes.bold ? boldFont : font,
                    .foregroundColor: colors.foreground,
                ]
                if cell.attributes.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                if cell.attributes.italic { attributes[.obliqueness] = 0.15 }
                var origin = NSPoint(x: rect.minX, y: top + 1)
                if !isASCII {
                    // 全角などは、字の幅がマスの幅と合わないので、マスの中ほどに置く
                    let width = (text as NSString).size(withAttributes: attributes).width
                    origin.x += max(0, (rect.width - width) / 2)
                }
                (text as NSString).draw(at: origin, withAttributes: attributes)
            }
            x += isASCII ? span : Int(cell.width)
        }
    }

    private func drawCursor(firstRow: Int) {
        let cursorRow = emulator.scrollback.count + emulator.cursorY
        let visibleRow = cursorRow - firstRow
        guard emulator.cursorVisible || markedText.length > 0, (0..<emulator.rows).contains(visibleRow), !isProcessExited else { return }
        let rect = NSRect(
            x: inset.width + CGFloat(emulator.cursorX) * cellWidth,
            y: inset.height + CGFloat(visibleRow) * cellHeight,
            width: cellWidth,
            height: cellHeight
        )
        if markedText.length > 0 {
            // 変換中の文字を、カーソルの位置に下線つきで出す
            let text = NSMutableAttributedString(attributedString: markedText)
            let range = NSRange(location: 0, length: text.length)
            text.addAttributes([.font: font, .foregroundColor: NSColor.textColor, .underlineStyle: NSUnderlineStyle.single.rawValue], range: range)
            let size = text.size()
            NSColor.textBackgroundColor.setFill()
            NSRect(x: rect.minX, y: rect.minY, width: size.width + 2, height: cellHeight).fill()
            text.draw(at: NSPoint(x: rect.minX, y: rect.minY + 1))
            return
        }
        let accent = Theme.shared.accentColor
        if isFocused {
            accent.withAlphaComponent(0.85).setFill()
            rect.fill()
            let cell = emulator.lines[emulator.cursorY][emulator.cursorX]
            if cell.width != 0, cell.character != " " {
                (String(cell.character) as NSString).draw(
                    at: NSPoint(x: rect.minX, y: rect.minY + 1),
                    withAttributes: [.font: font, .foregroundColor: NSColor.white]
                )
            }
        } else {
            accent.setStroke()
            let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1
            path.stroke()
        }
    }

    // MARK: - 色

    private func colors(for attributes: TerminalAttributes, selected: Bool) -> (foreground: NSColor, background: NSColor) {
        var foreground = color(attributes.foreground, isForeground: true, bold: attributes.bold)
        var background = color(attributes.background, isForeground: false, bold: false)
        if attributes.inverse { swap(&foreground, &background) }
        if attributes.dim { foreground = foreground.withAlphaComponent(0.6) }
        if selected { background = NSColor.selectedTextBackgroundColor }
        return (foreground, background)
    }

    private var isDark: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func color(_ color: TerminalColor, isForeground: Bool, bold: Bool) -> NSColor {
        switch color {
        case .standard:
            return isForeground ? .textColor : .textBackgroundColor
        case .indexed(let index):
            return Self.paletteColor(Int(index), dark: isDark)
        case .rgb(let r, let g, let b):
            return NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        }
    }

    /// 256 色の表。最初の 16 色は、明るい背景・暗い背景のどちらでも読める色にする
    static func paletteColor(_ index: Int, dark: Bool) -> NSColor {
        let basic: [UInt32] = dark
            ? [0x3B3B3B, 0xFF6B6B, 0x5FD38D, 0xE5C07B, 0x61AFEF, 0xC678DD, 0x56B6C2, 0xD0D0D0,
               0x7F7F7F, 0xFF8787, 0x87E5A8, 0xF0D58C, 0x8CC8FF, 0xD99BEB, 0x7FD3DD, 0xFFFFFF]
            : [0x000000, 0xC4302B, 0x1E8A3E, 0x9A6B00, 0x2A62C9, 0x9B3BB0, 0x16818C, 0xBFBFBF,
               0x6E6E6E, 0xE0443E, 0x2EA44F, 0xB58A00, 0x3F7FE5, 0xB453CB, 0x1F9AA7, 0xFFFFFF]
        func rgb(_ value: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                    blue: CGFloat(value & 0xFF) / 255, alpha: 1)
        }
        switch index {
        case 0..<16:
            return rgb(basic[index])
        case 16..<232:
            let value = index - 16
            let steps: [CGFloat] = [0, 95, 135, 175, 215, 255]
            return NSColor(srgbRed: steps[value / 36] / 255, green: steps[(value / 6) % 6] / 255, blue: steps[value % 6] / 255, alpha: 1)
        default:
            let level = CGFloat(8 + (index - 232) * 10) / 255
            return NSColor(srgbRed: level, green: level, blue: level, alpha: 1)
        }
    }

    // MARK: - キー入力

    /// メニューのショートカットより先に、端末のキーとして受け取る（F5・Tab・⌃ のキーなど）。⌘ のキーと ⌃` はメニューに任せる
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) { return super.performKeyEquivalent(with: event) }
        if flags.contains(.control), event.charactersIgnoringModifiers == "`" { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        if isProcessExited {
            if event.keyCode == 36 || event.keyCode == 76 { onRestartRequest?() }
            return
        }
        scrollOffset = 0
        selectionStart = nil
        selectionEnd = nil
        // 変換中は、すべて日本語入力に任せる
        if hasMarkedText() {
            interpretKeyEvents([event])
            return
        }
        if let sequence = Self.sequence(for: event, applicationCursorKeys: emulator.applicationCursorKeys) {
            sendText(sequence)
            return
        }
        interpretKeyEvents([event])
    }

    /// 文字以外のキーを、端末の約束の文字列にする
    static func sequence(for event: NSEvent, applicationCursorKeys: Bool) -> String? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let option = flags.contains(.option)
        let shift = flags.contains(.shift)
        let control = flags.contains(.control)
        let arrowPrefix = applicationCursorKeys && !option && !shift && !control ? "\u{1B}O" : "\u{1B}["
        func arrow(_ letter: String) -> String {
            var modifier = 1
            if shift { modifier += 1 }
            if option { modifier += 2 }
            if control { modifier += 4 }
            return modifier == 1 ? arrowPrefix + letter : "\u{1B}[1;\(modifier)\(letter)"
        }
        switch event.keyCode {
        case 36, 76: return "\r"
        case 51: return option ? "\u{1B}\u{7F}" : "\u{7F}"
        case 117: return "\u{1B}[3~"
        case 48: return shift ? "\u{1B}[Z" : "\t"
        case 53: return "\u{1B}"
        case 123: return option && !shift && !control ? "\u{1B}b" : arrow("D")
        case 124: return option && !shift && !control ? "\u{1B}f" : arrow("C")
        case 125: return arrow("B")
        case 126: return arrow("A")
        case 115: return "\u{1B}[H"
        case 119: return "\u{1B}[F"
        case 116: return "\u{1B}[5~"
        case 121: return "\u{1B}[6~"
        case 122: return "\u{1B}OP"
        case 120: return "\u{1B}OQ"
        case 99: return "\u{1B}OR"
        case 118: return "\u{1B}OS"
        case 96: return "\u{1B}[15~"
        case 97: return "\u{1B}[17~"
        case 98: return "\u{1B}[18~"
        case 100: return "\u{1B}[19~"
        case 101: return "\u{1B}[20~"
        case 109: return "\u{1B}[21~"
        case 103: return "\u{1B}[23~"
        case 111: return "\u{1B}[24~"
        default: break
        }
        if control, let characters = event.charactersIgnoringModifiers?.lowercased(), let scalar = characters.unicodeScalars.first {
            // ⌃A〜⌃Z と ⌃@ ⌃[ ⌃\ ⌃] ⌃^ ⌃_ ⌃スペース
            switch scalar.value {
            case 0x61...0x7A: return String(Unicode.Scalar(scalar.value - 0x60)!)
            case 0x20, 0x40, 0x32: return "\u{0}"
            case 0x5B: return "\u{1B}"
            case 0x5C: return "\u{1C}"
            case 0x5D: return "\u{1D}"
            case 0x5E, 0x36: return "\u{1E}"
            case 0x5F, 0x2D: return "\u{1F}"
            default: break
            }
        }
        return nil
    }

    private func sendText(_ text: String) {
        send?(Data(text.utf8))
    }

    // MARK: - NSTextInputClient（日本語入力）

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        markedText = NSAttributedString()
        needsDisplay = true
        guard !text.isEmpty else { return }
        sendText(text)
    }

    override func doCommand(by selector: Selector) {
        // 日本語入力から戻ってきた操作（変換していないときの Return など）
        switch selector {
        case #selector(insertNewline(_:)): sendText("\r")
        case #selector(deleteBackward(_:)): sendText("\u{7F}")
        case #selector(insertTab(_:)): sendText("\t")
        case #selector(cancelOperation(_:)): sendText("\u{1B}")
        default: break
        }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if let attributed = string as? NSAttributedString {
            markedText = attributed
        } else {
            markedText = NSAttributedString(string: string as? String ?? "")
        }
        needsDisplay = true
    }

    func unmarkText() {
        markedText = NSAttributedString()
        needsDisplay = true
    }

    func selectedRange() -> NSRange { NSRange(location: 0, length: 0) }

    func markedRange() -> NSRange {
        markedText.length > 0 ? NSRange(location: 0, length: markedText.length) : NSRange(location: NSNotFound, length: 0)
    }

    func hasMarkedText() -> Bool { markedText.length > 0 }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [.underlineStyle] }

    /// 変換の候補の窓を、カーソルの下に出す
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        let rect = NSRect(
            x: inset.width + CGFloat(emulator.cursorX) * cellWidth,
            y: inset.height + CGFloat(emulator.cursorY + scrollOffset) * cellHeight,
            width: cellWidth,
            height: cellHeight
        )
        guard let window else { return .zero }
        return window.convertToScreen(convert(rect, to: nil))
    }

    func characterIndex(for point: NSPoint) -> Int { 0 }

    // MARK: - スクロール

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / cellHeight : event.scrollingDeltaY
        scrollRemainder += delta
        let lines = Int(scrollRemainder)
        guard lines != 0 else { return }
        scrollRemainder -= CGFloat(lines)
        if emulator.isAlternateScreen {
            // 全画面のアプリ（less・vim など）では、矢印キーとして送る
            let key = lines > 0 ? (emulator.applicationCursorKeys ? "\u{1B}OA" : "\u{1B}[A") : (emulator.applicationCursorKeys ? "\u{1B}OB" : "\u{1B}[B")
            sendText(String(repeating: key, count: min(abs(lines), 10)))
            return
        }
        scrollOffset = min(max(scrollOffset + lines, 0), emulator.scrollback.count)
        needsDisplay = true
    }

    // MARK: - 選択とコピー・貼り付け

    private func gridPosition(for event: NSEvent) -> (row: Int, column: Int) {
        let point = convert(event.locationInWindow, from: nil)
        let column = min(max(Int((point.x - inset.width) / cellWidth), 0), emulator.columns - 1)
        let visibleRow = min(max(Int((point.y - inset.height) / cellHeight), 0), emulator.rows - 1)
        return (emulator.scrollback.count - scrollOffset + visibleRow, column)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let position = gridPosition(for: event)
        if event.clickCount == 2 {
            selectWord(at: position)
        } else {
            selectionStart = position
            selectionEnd = nil
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard selectionStart != nil else { return }
        selectionEnd = gridPosition(for: event)
        needsDisplay = true
    }

    private func line(atAbsoluteRow row: Int) -> [TerminalCell] {
        let scrollback = emulator.scrollback
        if row < scrollback.count { return row >= 0 ? scrollback[row] : [] }
        let index = row - scrollback.count
        return index < emulator.lines.count ? emulator.lines[index] : []
    }

    private func selectWord(at position: (row: Int, column: Int)) {
        let line = line(atAbsoluteRow: position.row)
        guard position.column < line.count else { return }
        func isWord(_ cell: TerminalCell) -> Bool { cell.character != " " }
        guard isWord(line[position.column]) else { return }
        var start = position.column
        var end = position.column
        while start > 0, isWord(line[start - 1]) { start -= 1 }
        while end + 1 < line.count, isWord(line[end + 1]) { end += 1 }
        selectionStart = (position.row, start)
        selectionEnd = (position.row, end)
    }

    private var orderedSelection: (start: (row: Int, column: Int), end: (row: Int, column: Int))? {
        guard let start = selectionStart, let end = selectionEnd else { return nil }
        if start.row < end.row || (start.row == end.row && start.column <= end.column) { return (start, end) }
        return (end, start)
    }

    private func isSelected(row: Int, column: Int) -> Bool {
        guard let selection = orderedSelection else { return false }
        if row < selection.start.row || row > selection.end.row { return false }
        if row == selection.start.row, column < selection.start.column { return false }
        if row == selection.end.row, column > selection.end.column { return false }
        return true
    }

    var selectedText: String? {
        guard let selection = orderedSelection else { return nil }
        var lines: [String] = []
        for row in selection.start.row...selection.end.row {
            let cells = line(atAbsoluteRow: row)
            let from = row == selection.start.row ? selection.start.column : 0
            let to = row == selection.end.row ? min(selection.end.column, cells.count - 1) : cells.count - 1
            guard from <= to, from < cells.count else {
                lines.append("")
                continue
            }
            lines.append(TerminalEmulator.text(of: Array(cells[from...to])))
        }
        return lines.joined(separator: "\n")
    }

    @objc func copy(_ sender: Any?) {
        guard let text = selectedText, !text.isEmpty else {
            NSSound.beep()
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc func paste(_ sender: Any?) {
        guard !isProcessExited else { return }
        // ファイルを貼り付けたらパスにする
        var text = NSPasteboard.general.string(forType: .string) ?? ""
        if let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            text = urls.map { Self.shellQuoted($0.path) }.joined(separator: " ")
        }
        guard !text.isEmpty else { return }
        scrollOffset = 0
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\r").replacingOccurrences(of: "\n", with: "\r")
        sendText(emulator.bracketedPaste ? "\u{1B}[200~" + normalized + "\u{1B}[201~" : normalized)
    }

    override func selectAll(_ sender: Any?) {
        selectionStart = (0, 0)
        selectionEnd = (emulator.scrollback.count + emulator.rows - 1, emulator.columns - 1)
        needsDisplay = true
    }

    static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - ファイルのドロップ（パスを入れる）

    func registerForFileDrops() {
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        isProcessExited ? [] : .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else { return false }
        sendText(urls.map { Self.shellQuoted($0.path) }.joined(separator: " ") + " ")
        window?.makeFirstResponder(self)
        return true
    }
}
