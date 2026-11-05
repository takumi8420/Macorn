import Foundation
import Testing
@testable import Macorn

@MainActor
struct WordRendererTests {
    @Test func recognizesWordFiles() {
        #expect(WordRenderer.isWord(URL(fileURLWithPath: "/tmp/a.docx")))
        #expect(WordRenderer.isWord(URL(fileURLWithPath: "/tmp/a.DOC")))
        #expect(!WordRenderer.isWord(URL(fileURLWithPath: "/tmp/a.pdf")))
        #expect(!WordRenderer.isWord(URL(fileURLWithPath: "/tmp/a.xlsx")))
        // Word の書類は、Web の領域で幅に合わせて折り返す
        #expect(FilePreviewController.viewer(for: URL(fileURLWithPath: "/tmp/a.docx")) == .document)
        #expect(FilePreviewController.kind(for: URL(fileURLWithPath: "/tmp/a.docx")) == .visual)
        // Excel・PowerPoint はこれまでどおりクイックルック
        #expect(FilePreviewController.viewer(for: URL(fileURLWithPath: "/tmp/a.xlsx")) == .quickLook)
    }

    @Test func addsWidthStyleIntoHead() {
        let html = "<html><head><title>a</title></head><body class=\"s0\"><div class=\"s1\">本文</div></body></html>"
        let result = WordRenderer.styled(html)
        let style = result.range(of: "macorn-word")!
        let headEnd = result.range(of: "</head>")!
        #expect(style.lowerBound < headEnd.lowerBound)
        #expect(result.contains("width: auto !important"))
        #expect(result.hasSuffix("</html>"))
    }

    @Test func addsStyleWithoutHead() {
        #expect(WordRenderer.styled("<p>本文</p>").hasPrefix(WordRenderer.style))
    }

    /// macOS の変換（qlmanage）で、実際の .docx が HTML になり、幅の決め打ちが外れる
    @Test func rendersDocx() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("macorn-word-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let text = directory.appendingPathComponent("a.txt")
        try "Word のテスト文書です。".write(to: text, atomically: true, encoding: .utf8)
        let docx = directory.appendingPathComponent("a.docx")
        let convert = Process()
        convert.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        convert.arguments = ["-convert", "docx", text.path, "-output", docx.path]
        try convert.run()
        convert.waitUntilExit()
        let page = try #require(await WordRenderer.render(docx, into: directory.appendingPathComponent("out")))
        let html = try String(contentsOf: page, encoding: .utf8)
        #expect(html.contains("macorn-word"))
        #expect(html.contains("Word のテスト文書です。"))
    }
}
