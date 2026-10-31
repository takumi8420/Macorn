import Foundation
import Testing
@testable import Macorn

/// CSV・TSV を表にする
struct CSVRendererTests {
    @Test func parsesQuotedFields() {
        let text = "名前,メモ,数\n\"山田, 太郎\",\"1行目\n2行目\",3\n\"引用\"\"符\",,\n"
        let rows = CSVRenderer.parse(text, delimiter: ",")
        #expect(rows == [["名前", "メモ", "数"], ["山田, 太郎", "1行目\n2行目", "3"], ["引用\"符", "", ""]])
    }

    @Test func handlesCRLFAndMissingNewline() {
        #expect(CSVRenderer.parse("a,b\r\n1,2", delimiter: ",") == [["a", "b"], ["1", "2"]])
    }

    @Test func detectsDelimiter() {
        #expect(CSVRenderer.delimiter(for: "a\tb\tc\n1\t2\t3", fileExtension: "csv") == "\t")
        #expect(CSVRenderer.delimiter(for: "a;b;c", fileExtension: "csv") == ";")
        #expect(CSVRenderer.delimiter(for: "\"x;y\",b", fileExtension: "csv") == ",")
        #expect(CSVRenderer.delimiter(for: "a,b", fileExtension: "tsv") == "\t")
        #expect(CSVRenderer.delimiter(for: "single", fileExtension: "csv") == ",")
    }

    @Test func decodesShiftJIS() throws {
        let data = try #require("品名,価格\nりんご,120\n".data(using: .shiftJIS))
        #expect(CSVRenderer.decode(data).hasPrefix("品名,価格"))
        let bom = Data([0xEF, 0xBB, 0xBF]) + Data("a,b".utf8)
        #expect(CSVRenderer.decode(bom) == "a,b")
    }

    @Test func rendersTable() {
        let table = CSVRenderer.Table(rows: [["名前", "金額"], ["<b>", "1,200"], ["短い"]], delimiter: ",", truncated: false)
        let html = CSVRenderer.render(table)
        #expect(html.contains("2 行 × 2 列（区切り：カンマ）"))
        #expect(html.contains("<th>名前</th><th>金額</th>"))
        #expect(html.contains("&lt;b&gt;"))
        #expect(html.contains("<td class=\"num\">1,200</td>"))
        #expect(html.contains("<td>短い</td><td></td>"))
    }

    @Test func truncatesLargeFiles() {
        let text = (0...CSVRenderer.maxRows + 50).map { "\($0),x" }.joined(separator: "\n")
        let table = CSVRenderer.table(from: Data(text.utf8), fileExtension: "csv")
        #expect(table.truncated)
        #expect(table.rows.count == CSVRenderer.maxRows)
    }

    @Test func recognizesNumbers() {
        for value in ["12", "-3.5", "1,234,567", "12%", "¥1,000", "1e5"] { #expect(CSVRenderer.isNumber(value), "\(value)") }
        for value in ["", "abc", "1,23", "2026-11-01", "03-1234"] { #expect(!CSVRenderer.isNumber(value), "\(value)") }
    }

    @Test func previewKind() {
        #expect(FilePreviewController.kind(for: URL(fileURLWithPath: "/tmp/a.csv")) == .csv)
        #expect(FilePreviewController.kind(for: URL(fileURLWithPath: "/tmp/a.TSV")) == .csv)
    }
}
