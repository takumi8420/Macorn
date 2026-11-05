import Foundation

/// Markdown を HTML にする（プレビュー用）。外部ライブラリを使わず、よく使う書き方に対応する。
/// 見出し・段落・強調・打ち消し・インラインコード・コードブロック・引用・リスト（入れ子・チェックボックス）・
/// 表・水平線・リンク・画像・自動リンク・改行・HTML の埋め込み・先頭のメタデータ（front matter）。
nonisolated enum MarkdownRenderer {
    static func render(_ markdown: String) -> String {
        var lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: "\t", with: "    ") }
        var html = ""
        // 先頭の --- で囲まれたメタデータは、表として見せる
        if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") {
            html += frontMatter(Array(lines[1..<end]))
            lines = Array(lines[(end + 1)...])
        }
        var slugs: [String: Int] = [:]
        return html + renderBlocks(lines, slugs: &slugs)
    }

    // MARK: - プレビューでの編集

    /// プレビューで編集するための HTML と、元の文章の切れ目
    /// 文章は head + blocks[0].source + blocks[0].separator + … + blocks[n-1].source + tail で元どおりになる
    struct EditableDocument: Encodable {
        struct Block: Encodable {
            var source: String
            /// 次のブロックまでの空行など（最後のブロックでは空）
            var separator: String
        }
        var head: String
        var blocks: [Block]
        var tail: String
        /// 改行が CRLF だったか（保存するときに戻す）
        var crlf: Bool
    }

    /// 一番外側のブロックを `<div class="md-block" data-i="番号">` で包んだ HTML と、元の文章の切れ目を返す
    static func renderEditable(_ markdown: String) -> (html: String, document: EditableDocument) {
        let crlf = markdown.contains("\r\n")
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let original = normalized.components(separatedBy: "\n")
        let lines = original.map { $0.replacingOccurrences(of: "\t", with: "    ") }
        var html = ""
        var offset = 0
        if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") {
            let front = frontMatter(Array(lines[1..<end]))
            if !front.isEmpty { html += "<div class=\"md-front\" contenteditable=\"false\">\(front)</div>\n" }
            offset = end + 1
        }
        var ranges: [(start: Int, end: Int)] = []
        var slugs: [String: Int] = [:]
        _ = renderBlocks(Array(lines[offset...]), slugs: &slugs) { start, end, fragment, raw in
            // 閉じていないコードブロックは、最後の行の先まで進んでいることがある
            var end = min(end + offset, original.count)
            let start = start + offset
            // 後ろの空行はブロックに含めない
            while end > start + 1, original[end - 1].trimmingCharacters(in: .whitespaces).isEmpty { end -= 1 }
            let attributes = raw ? " data-raw contenteditable=\"false\"" : ""
            html += "<div class=\"md-block\" data-i=\"\(ranges.count)\"\(attributes)>\n\(fragment)</div>\n"
            ranges.append((start, end))
        }
        guard let first = ranges.first, let last = ranges.last else {
            return (html, EditableDocument(head: normalized, blocks: [], tail: "", crlf: crlf))
        }
        let head = original[0..<first.start].map { $0 + "\n" }.joined()
        var blocks: [EditableDocument.Block] = []
        for (index, range) in ranges.enumerated() {
            let source = original[range.start..<range.end].joined(separator: "\n")
            var separator = ""
            if index + 1 < ranges.count {
                separator = "\n" + original[range.end..<ranges[index + 1].start].map { $0 + "\n" }.joined()
            }
            blocks.append(.init(source: source, separator: separator))
        }
        let tail = last.end < original.count ? "\n" + original[last.end...].joined(separator: "\n") : ""
        return (html, EditableDocument(head: head, blocks: blocks, tail: tail, crlf: crlf))
    }

    // MARK: - ブロック

    /// 一番外側のブロックごとに、元の行の範囲（start..<end）と HTML を知らせる（プレビューでの編集用）
    typealias BlockRecorder = (_ start: Int, _ end: Int, _ html: String, _ raw: Bool) -> Void

    private static func renderBlocks(_ lines: [String], slugs: inout [String: Int], record: BlockRecorder? = nil) -> String {
        var html = ""
        var paragraph: [String] = []
        var paragraphStart = 0
        var index = 0

        func emit(_ start: Int, _ end: Int, _ fragment: String, raw: Bool = false) {
            html += fragment
            record?(start, end, fragment, raw)
        }

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            emit(paragraphStart, paragraphStart + paragraph.count, "<p>" + inline(paragraph.joined(separator: "\n")) + "</p>\n")
            paragraph = []
        }

        while index < lines.count {
            let line = lines[index]
            let blockStart = index
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            // フェンスで囲んだコード
            if let fence = fenceMarker(trimmed) {
                flushParagraph()
                let language = String(trimmed.dropFirst(fence.count)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    code.append(lines[index])
                    index += 1
                }
                index += 1
                let className = language.isEmpty ? "" : " class=\"language-\(escape(language.split(separator: " ").first.map(String.init) ?? ""))\""
                emit(blockStart, index, "<pre><code\(className)>" + escape(code.joined(separator: "\n")) + "</code></pre>\n")
                continue
            }

            // 見出し
            if let heading = heading(trimmed) {
                flushParagraph()
                let text = inline(heading.text)
                let slug = uniqueSlug(heading.text, slugs: &slugs)
                index += 1
                emit(blockStart, index, "<h\(heading.level) id=\"\(slug)\">\(text)</h\(heading.level)>\n")
                continue
            }

            // 水平線
            if isHorizontalRule(trimmed) {
                flushParagraph()
                index += 1
                emit(blockStart, index, "<hr>\n")
                continue
            }

            // 引用
            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoted: [String] = []
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    if current.hasPrefix(">") {
                        var rest = String(current.dropFirst())
                        if rest.hasPrefix(" ") { rest.removeFirst() }
                        quoted.append(rest)
                    } else if !current.isEmpty, !quoted.isEmpty, quoted.last?.isEmpty == false {
                        quoted.append(current) // 段落の続き
                    } else {
                        break
                    }
                    index += 1
                }
                emit(blockStart, index, "<blockquote>\n" + renderBlocks(quoted, slugs: &slugs) + "</blockquote>\n")
                continue
            }

            // 表
            if index + 1 < lines.count, line.contains("|"), isTableSeparator(lines[index + 1]) {
                flushParagraph()
                let (table, next) = renderTable(lines, start: index)
                index = next
                emit(blockStart, index, table)
                continue
            }

            // リスト
            if listMarker(line) != nil {
                flushParagraph()
                let (list, next) = renderList(lines, start: index, slugs: &slugs)
                index = next
                emit(blockStart, index, list)
                continue
            }

            // 4文字下げたコード（段落の途中でなければ）
            if paragraph.isEmpty, line.hasPrefix("    ") {
                var code: [String] = []
                while index < lines.count, lines[index].hasPrefix("    ") || lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    code.append(String(lines[index].dropFirst(min(4, lines[index].count))))
                    index += 1
                }
                while code.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { code.removeLast() }
                emit(blockStart, index, "<pre><code>" + escape(code.joined(separator: "\n")) + "</code></pre>\n")
                continue
            }

            // HTML の埋め込み（そのまま出す）
            if paragraph.isEmpty, trimmed.hasPrefix("<"), trimmed.range(of: #"^</?[a-zA-Z][^>]*>"#, options: .regularExpression) != nil {
                var block: [String] = []
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    block.append(lines[index])
                    index += 1
                }
                emit(blockStart, index, block.joined(separator: "\n") + "\n", raw: true)
                continue
            }

            if paragraph.isEmpty { paragraphStart = index }
            paragraph.append(line.trimmingCharacters(in: .whitespaces) + (line.hasSuffix("  ") ? "  " : ""))
            index += 1
        }
        flushParagraph()
        return html
    }

    private static func fenceMarker(_ line: String) -> String? {
        if line.hasPrefix("```") { return "```" }
        if line.hasPrefix("~~~") { return "~~~" }
        return nil
    }

    private static func heading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        guard rest.isEmpty || rest.first == " " else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        // 末尾の「 ##」は飾りなので外す
        if let range = text.range(of: #"\s+#+$"#, options: .regularExpression) { text.removeSubrange(range) }
        return (hashes, text)
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    // MARK: - リスト

    private struct ListMarker {
        var indent: Int
        var ordered: Bool
        var start: Int
        /// 本文が始まる位置（マーカーと空白の後）
        var contentOffset: Int
    }

    private static func listMarker(_ line: String) -> ListMarker? {
        let indent = line.prefix { $0 == " " }.count
        let rest = line.dropFirst(indent)
        guard let first = rest.first else { return nil }
        if "-*+".contains(first), rest.dropFirst().first == " " {
            // 「---」などの水平線はリストではない
            if isHorizontalRule(String(rest)) { return nil }
            return ListMarker(indent: indent, ordered: false, start: 1, contentOffset: indent + 2)
        }
        let digits = rest.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 9 else { return nil }
        let after = rest.dropFirst(digits.count)
        guard let delimiter = after.first, delimiter == "." || delimiter == ")", after.dropFirst().first == " " else { return nil }
        return ListMarker(indent: indent, ordered: true, start: Int(digits) ?? 1, contentOffset: indent + digits.count + 2)
    }

    private static func renderList(_ lines: [String], start: Int, slugs: inout [String: Int]) -> (String, Int) {
        guard let first = listMarker(lines[start]) else { return ("", start + 1) }
        var items: [[String]] = []
        var loose = false
        var index = start
        var contentOffset = first.contentOffset

        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                // 空行のあとも、同じリストの続き（字下げ・次の項目）なら続ける
                let next = lines[(index + 1)...].first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                guard let next, next.prefix(while: { $0 == " " }).count >= contentOffset
                    || (listMarker(next).map { $0.indent <= first.indent + 1 && $0.ordered == first.ordered } ?? false) else { break }
                if listMarker(next).map({ $0.indent <= first.indent + 1 }) ?? false { loose = true }
                items[items.count - 1].append("")
                index += 1
                continue
            }
            if let marker = listMarker(line), marker.indent <= first.indent + 1 {
                guard marker.ordered == first.ordered else { break }
                contentOffset = marker.contentOffset
                items.append([String(line.dropFirst(marker.contentOffset))])
                index += 1
                continue
            }
            guard !items.isEmpty else { break }
            let indent = line.prefix { $0 == " " }.count
            if indent >= first.indent + 2 {
                items[items.count - 1].append(String(line.dropFirst(min(indent, contentOffset))))
            } else if items[items.count - 1].last?.isEmpty == false, !isBlockStart(line) {
                items[items.count - 1].append(line.trimmingCharacters(in: .whitespaces)) // 段落の続き
            } else {
                break
            }
            index += 1
        }

        let tag = first.ordered ? "ol" : "ul"
        let startAttribute = first.ordered && first.start != 1 ? " start=\"\(first.start)\"" : ""
        var html = "<\(tag)\(startAttribute)>\n"
        for var item in items {
            while item.last?.isEmpty == true { item.removeLast() }
            var checkbox = ""
            if let firstLine = item.first, let match = firstLine.range(of: #"^\[( |x|X)\]\s"#, options: .regularExpression) {
                let checked = firstLine[match].lowercased().contains("x")
                checkbox = "<input type=\"checkbox\" disabled\(checked ? " checked" : "")> "
                item[0] = String(firstLine[match.upperBound...])
            }
            var body = renderBlocks(item, slugs: &slugs)
            // 詰めたリストでは、段落の <p> を付けない
            if !loose, body.hasPrefix("<p>"), let close = body.range(of: "</p>\n") {
                body = String(body[body.index(body.startIndex, offsetBy: 3)..<close.lowerBound]) + "\n" + body[close.upperBound...]
            }
            let classAttribute = checkbox.isEmpty ? "" : " class=\"task\""
            html += "<li\(classAttribute)>" + checkbox + body.trimmingCharacters(in: .newlines) + "</li>\n"
        }
        return (html + "</\(tag)>\n", index)
    }

    private static func isBlockStart(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return heading(trimmed) != nil || fenceMarker(trimmed) != nil || trimmed.hasPrefix(">") || isHorizontalRule(trimmed) || listMarker(line) != nil
    }

    // MARK: - 表

    private static func isTableSeparator(_ line: String) -> Bool {
        line.range(of: #"^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$"#, options: .regularExpression) != nil && line.contains("-")
    }

    private static func tableCells(_ line: String) -> [String] {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("|") { text.removeFirst() }
        if text.hasSuffix("|"), !text.hasSuffix("\\|") { text.removeLast() }
        // 「\|」は区切りではなく文字としての |
        let placeholder = "\u{F8FF}"
        return text.replacingOccurrences(of: "\\|", with: placeholder)
            .components(separatedBy: "|")
            .map { $0.replacingOccurrences(of: placeholder, with: "|").trimmingCharacters(in: .whitespaces) }
    }

    private static func renderTable(_ lines: [String], start: Int) -> (String, Int) {
        let header = tableCells(lines[start])
        let alignments: [String?] = tableCells(lines[start + 1]).map { cell in
            switch (cell.hasPrefix(":"), cell.hasSuffix(":")) {
            case (true, true): "center"
            case (false, true): "right"
            case (true, false): "left"
            default: nil
            }
        }
        func cell(_ tag: String, _ text: String, _ column: Int) -> String {
            let align = column < alignments.count ? alignments[column] : nil
            return "<\(tag)\(align.map { " style=\"text-align:\($0)\"" } ?? "")>\(inline(text))</\(tag)>"
        }
        var html = "<table>\n<thead><tr>" + header.enumerated().map { cell("th", $1, $0) }.joined() + "</tr></thead>\n<tbody>\n"
        var index = start + 2
        while index < lines.count, lines[index].contains("|"), !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            let cells = tableCells(lines[index])
            let padded = (0..<header.count).map { $0 < cells.count ? cells[$0] : "" }
            html += "<tr>" + padded.enumerated().map { cell("td", $1, $0) }.joined() + "</tr>\n"
            index += 1
        }
        return (html + "</tbody>\n</table>\n", index)
    }

    private static func frontMatter(_ lines: [String]) -> String {
        let rows = lines.compactMap { line -> String? in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            return "<tr><th>\(escape(key))</th><td>\(escape(value))</td></tr>"
        }
        guard !rows.isEmpty else { return "" }
        return "<table class=\"front-matter\">\n" + rows.joined(separator: "\n") + "\n</table>\n"
    }

    // MARK: - 行の中

    /// 強調・リンク・コードなど、行の中の書き方を HTML にする
    static func inline(_ text: String) -> String {
        var placeholders: [String] = []
        func protect(_ html: String) -> String {
            placeholders.append(html)
            return "\u{E000}\(placeholders.count - 1)\u{E001}"
        }

        var result = text
        // 1. インラインコード（中は書き方として扱わない）
        result = replace(#"(`+)(.+?)\1"#, in: result) { match in
            protect("<code>" + escape(match[2].trimmingCharacters(in: .whitespaces)) + "</code>")
        }
        // 2. 「\*」などのエスケープ
        result = replace(#"\\([\\`*_{}\[\]()#+\-.!|~<>])"#, in: result) { match in protect(escape(match[1])) }
        // 3. 自動リンク <https://…>
        result = replace(#"<(https?://[^>\s]+)>"#, in: result) { match in
            protect("<a href=\"\(escapeAttribute(match[1]))\">\(escape(match[1]))</a>")
        }
        // 4. HTML のタグはそのまま残す
        result = replace(#"</?[a-zA-Z][a-zA-Z0-9-]*(\s[^<>]*)?/?>"#, in: result) { match in protect(match[0]) }
        // 5. 残りの文字をエスケープ
        result = escape(result)
        // 6. 画像とリンク
        result = replace(#"!\[([^\]]*)\]\(([^)\s]+)(?:\s+&quot;([^&]*)&quot;)?\)"#, in: result) { match in
            let title = match[3].isEmpty ? "" : " title=\"\(match[3])\""
            return protect("<img src=\"\(match[2])\" alt=\"\(match[1])\"\(title)>")
        }
        result = replace(#"\[([^\]]+)\]\(([^)\s]+)(?:\s+&quot;([^&]*)&quot;)?\)"#, in: result) { match in
            let title = match[3].isEmpty ? "" : " title=\"\(match[3])\""
            return "<a href=\"\(match[2])\"\(title)>\(match[1])</a>"
        }
        // 7. 本文中の URL
        result = replace(#"(?<![\"'=\w/])(https?://[^\s<]+[^\s<.,;:!?)\]'\"])"#, in: result) { match in
            "<a href=\"\(match[1])\">\(match[1])</a>"
        }
        // 8. 強調・打ち消し
        result = replace(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#, in: result) { "<strong>\($0[2])</strong>" }
        result = replace(#"(?<![\w*])\*(?=\S)(.+?)(?<=\S)\*(?![\w*])"#, in: result) { "<em>\($0[1])</em>" }
        result = replace(#"(?<![\w_])_(?=\S)(.+?)(?<=\S)_(?![\w_])"#, in: result) { "<em>\($0[1])</em>" }
        result = replace(#"~~(?=\S)(.+?)(?<=\S)~~"#, in: result) { "<del>\($0[1])</del>" }
        // 9. 改行（行末の2つの空白、または \）
        result = result.replacingOccurrences(of: "  \n", with: "<br>\n")

        // 守っておいた部分を戻す
        for (index, html) in placeholders.enumerated().reversed() {
            result = result.replacingOccurrences(of: "\u{E000}\(index)\u{E001}", with: html)
        }
        return result
    }

    private static func replace(_ pattern: String, in text: String, _ transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let groups = (0..<match.numberOfRanges).map { index -> String in
                let range = match.range(at: index)
                return range.location == NSNotFound ? "" : ns.substring(with: range)
            }
            result += transform(groups)
            last = match.range.location + match.range.length
        }
        return result + ns.substring(from: last)
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func escapeAttribute(_ text: String) -> String { escape(text) }

    /// 見出しへのリンク用の ID（GitHub と同じく小文字・空白はハイフン。同じ見出しには -1, -2）
    private static func uniqueSlug(_ text: String, slugs: inout [String: Int]) -> String {
        let plain = text.replacingOccurrences(of: #"[`*_~\[\]()]"#, with: "", options: .regularExpression)
        var slug = plain.lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s-]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
        if slug.isEmpty { slug = "section" }
        let count = slugs[slug, default: 0]
        slugs[slug] = count + 1
        return count == 0 ? escape(slug) : escape("\(slug)-\(count)")
    }
}
