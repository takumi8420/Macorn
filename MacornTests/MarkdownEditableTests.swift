import Foundation
import Testing
@testable import Macorn

/// プレビューでの編集用に分けたブロックが、元の文章を崩さないこと
struct MarkdownEditableTests {
    nonisolated private static let samples = [
        "",
        "本文だけ",
        "# 見出し\n本文\n",
        "---\ntitle: テスト\n---\n\n# 見出し\n\n段落の1行目\n2行目\n\n\n- a\n- b\n  - c\n\n- [ ] やる\n- [x] 済み\n\n```swift\nlet a = 1\n```\n\n| a | b |\n| - | -: |\n| 1 | 2 |\n\n> 引用\n> 続き\n\n<div>HTML</div>\n\n    字下げのコード\n\n最後\n",
        "\n\n先頭に空行\n\n\n末尾に空行\n\n\n",
        "```\n閉じていないコード\n本文",
        "1. 一\n2. 二\n\n---\n\n***\n",
        "タブ\tを含む\n\n-\tリスト\n",
    ]

    /// head + 各ブロック（と次までの間）+ tail で、元の文章に戻る
    @Test(arguments: samples)
    func reconstructsSource(_ markdown: String) {
        let document = MarkdownRenderer.renderEditable(markdown).document
        let rebuilt = document.head + document.blocks.map { $0.source + $0.separator }.joined() + document.tail
        #expect(rebuilt == markdown)
    }

    @Test func crlfIsRemembered() {
        let document = MarkdownRenderer.renderEditable("# a\r\n\r\nb\r\n").document
        #expect(document.crlf)
        #expect(document.head + document.blocks.map { $0.source + $0.separator }.joined() + document.tail == "# a\n\nb\n")
    }

    @Test func blocksAreWrapped() {
        let (html, document) = MarkdownRenderer.renderEditable("# 見出し\n\n本文\n\n<div>x</div>\n")
        #expect(document.blocks.map(\.source) == ["# 見出し", "本文", "<div>x</div>"])
        #expect(html.contains("<div class=\"md-block\" data-i=\"0\">"))
        #expect(html.contains("<h1 id=\"見出し\">見出し</h1>"))
        // HTML のまま書かれた部分は、ダブルクリックで元の文章を直す
        #expect(html.contains("data-i=\"2\" data-raw contenteditable=\"false\""))
    }

    @Test func frontMatterIsNotEditable() {
        let (html, document) = MarkdownRenderer.renderEditable("---\ntitle: a\n---\n本文\n")
        #expect(html.contains("<div class=\"md-front\" contenteditable=\"false\">"))
        #expect(document.head == "---\ntitle: a\n---\n")
        #expect(document.blocks.map(\.source) == ["本文"])
    }

    /// 編集用の HTML でも、ふつうの表示と同じ中身になる（包みを外せば同じ）
    @Test(arguments: samples)
    func sameContentAsPreview(_ markdown: String) {
        let editable = MarkdownRenderer.renderEditable(markdown).html
            .replacingOccurrences(of: #"<div class="md-block" data-i="\d+"( data-raw contenteditable="false")?>\n"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"<div class="md-front" contenteditable="false">"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "</div>\n", with: "")
        let plain = MarkdownRenderer.render(markdown).replacingOccurrences(of: "</div>\n", with: "").replacingOccurrences(of: "</div>", with: "")
        #expect(editable.replacingOccurrences(of: "</div>", with: "") == plain)
    }
}
