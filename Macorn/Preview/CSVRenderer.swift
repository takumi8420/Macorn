import Foundation

/// CSV・TSV を表（HTML）にする（外部ライブラリなし）。
/// 引用符で囲んだ値（中のカンマ・改行・"" を含む）に対応し、文字コードは UTF-8 のほか Excel が書く Shift_JIS も読む。
enum CSVRenderer {
    /// 表示する行数の上限（大きなファイルでもプレビューが重くならないように）
    static let maxRows = 2000

    struct Table: Equatable {
        var rows: [[String]]
        var delimiter: Character
        /// 上限で切ったか
        var truncated: Bool
    }

    // MARK: - 読む

    /// ファイルの中身を文字列にする。BOM・UTF-8・Shift_JIS・UTF-16 の順に試す
    static func decode(_ data: Data) -> String {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(decoding: data.dropFirst(3), as: UTF8.self)
        }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]), let text = String(data: data, encoding: .utf16) {
            return text
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .shiftJIS) { return text }
        return String(decoding: data, as: UTF8.self)
    }

    /// 区切り文字を決める。.tsv はタブ、それ以外は1行目に多く出るもの（カンマ・タブ・セミコロン）
    static func delimiter(for text: Substring, fileExtension: String) -> Character {
        if ["tsv", "tab"].contains(fileExtension.lowercased()) { return "\t" }
        var counts: [Character: Int] = [",": 0, "\t": 0, ";": 0]
        var quoted = false
        for character in text {
            if character == "\"" { quoted.toggle() }
            if !quoted, character.isNewline { break }
            if !quoted, counts[character] != nil { counts[character, default: 0] += 1 }
        }
        // 同じ数ならカンマ・タブ・セミコロンの順に選ぶ
        var best: Character = ","
        for candidate in [",", "\t", ";"] as [Character] where counts[candidate, default: 0] > counts[best, default: 0] {
            best = candidate
        }
        return best
    }

    /// 行と値に分ける（RFC 4180 に沿う。引用符の中の区切り・改行はそのまま値に入る）
    static func parse(_ text: String, delimiter: Character, limit: Int = maxRows + 1) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var afterQuote = false
        var iterator = text.makeIterator()
        var pending: Character?

        func endField() {
            row.append(field)
            field = ""
            afterQuote = false
        }
        func endRow() {
            endField()
            rows.append(row)
            row = []
        }

        while let character = pending ?? iterator.next() {
            pending = nil
            if quoted {
                if character == "\"" {
                    // "" は引用符そのもの、" だけなら囲みの終わり
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { quoted = false; afterQuote = true; pending = next }
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }
            if character == "\"", field.isEmpty, !afterQuote {
                quoted = true
            } else if character == delimiter {
                endField()
            } else if character.isNewline {
                endRow()
                if rows.count >= limit { return rows }
            } else {
                field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty || quoted { endRow() }
        return rows
    }

    static func table(from data: Data, fileExtension: String) -> Table {
        let text = decode(data)
        let delimiter = delimiter(for: text[...], fileExtension: fileExtension)
        var rows = parse(text, delimiter: delimiter)
        let truncated = rows.count > maxRows
        if truncated { rows.removeLast(rows.count - maxRows) }
        return Table(rows: rows, delimiter: delimiter, truncated: truncated)
    }

    // MARK: - 描く

    /// 1行目を見出しにした表。左に行番号を付け、数値は右に寄せる
    static func render(_ table: Table) -> String {
        guard let header = table.rows.first else {
            return "<p class=\"csv-meta\">空のファイルです。</p>"
        }
        let columns = table.rows.map(\.count).max() ?? 0
        let body = table.rows.dropFirst()
        let delimiterName = switch table.delimiter {
        case "\t": "タブ"
        case ";": "セミコロン"
        default: "カンマ"
        }
        var html = "<p class=\"csv-meta\">\(body.count) 行 × \(columns) 列（区切り：\(delimiterName)）"
        if table.truncated { html += "・先頭の \(maxRows - 1) 行だけを表示しています" }
        html += "</p>\n<table class=\"csv\">\n<thead><tr><th class=\"rn\"></th>"
        for index in 0..<columns {
            html += "<th>\(MarkdownRenderer.escape(index < header.count ? header[index] : ""))</th>"
        }
        html += "</tr></thead>\n<tbody>\n"
        for (number, row) in body.enumerated() {
            html += "<tr><td class=\"rn\">\(number + 1)</td>"
            for index in 0..<columns {
                let value = index < row.count ? row[index] : ""
                // 長い値は省略して見せるので、マウスを乗せたら全文を出す
                let title = value.count > 40 ? " title=\"\(MarkdownRenderer.escape(value))\"" : ""
                html += isNumber(value) ? "<td class=\"num\"\(title)>" : "<td\(title)>"
                html += MarkdownRenderer.escape(value) + "</td>"
            }
            html += "</tr>\n"
        }
        return html + "</tbody>\n</table>"
    }

    /// 数値に見えるか（1,234 や -3.5、12% も数値として右に寄せる）
    static func isNumber(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        return trimmed.range(of: #"^[-+]?[¥$€]?\d{1,3}(,\d{3})*(\.\d+)?%?$|^[-+]?[¥$€]?\d+(\.\d+)?([eE][-+]?\d+)?%?$"#,
                             options: .regularExpression) != nil
    }

    /// 表のための見た目（プレビューの共通の見た目に足す）
    static let style = """
    body { max-width: none; padding: 12px 16px 32px; }
    .csv-meta { color: var(--muted); font-size: 0.85em; margin: 0 0 8px; }
    table.csv { display: table; border-collapse: separate; border-spacing: 0; font-size: 0.88em; line-height: 1.45; margin: 0; }
    table.csv th, table.csv td { border: none; border-right: 1px solid var(--border); border-bottom: 1px solid var(--border);
        padding: 4px 10px; white-space: pre; vertical-align: top; max-width: 360px; overflow: hidden; text-overflow: ellipsis;
        text-align: left; }
    table.csv thead th { position: sticky; top: 0; z-index: 1; background: Canvas; font-weight: 600;
        border-top: 1px solid var(--border); }
    table.csv tr > :first-child { border-left: 1px solid var(--border); }
    table.csv .rn { position: sticky; left: 0; background: Canvas; color: var(--muted); text-align: right;
        font-variant-numeric: tabular-nums; min-width: 2em; }
    table.csv thead th.rn { z-index: 2; }
    table.csv td.num { text-align: right; font-variant-numeric: tabular-nums; white-space: nowrap; }
    table.csv tbody tr:hover td { background-color: color-mix(in srgb, var(--accent) 8%, Canvas); }
    """
}
