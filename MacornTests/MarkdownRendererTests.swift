import Foundation
import Testing
@testable import Macorn

struct MarkdownRendererTests {
    private func render(_ text: String) -> String { MarkdownRenderer.render(text) }

    @Test func headingsWithIDs() {
        let html = render("# はじめに\n## Getting Started\n## Getting Started")
        #expect(html.contains("<h1 id=\"はじめに\">はじめに</h1>"))
        #expect(html.contains("<h2 id=\"getting-started\">Getting Started</h2>"))
        #expect(html.contains("<h2 id=\"getting-started-1\">"))
    }

    @Test func paragraphsAndInline() {
        let html = render("これは **太字** と *斜体* と `code` と ~~消し~~ です。")
        #expect(html.contains("<strong>太字</strong>"))
        #expect(html.contains("<em>斜体</em>"))
        #expect(html.contains("<code>code</code>"))
        #expect(html.contains("<del>消し</del>"))
        #expect(html.hasPrefix("<p>"))
    }

    @Test func escapesHTMLInCodeAndText() {
        #expect(render("`<div>`").contains("<code>&lt;div&gt;</code>"))
        #expect(render("```\n<b>x</b>\n```").contains("&lt;b&gt;x&lt;/b&gt;"))
        #expect(render("a < b & c").contains("a &lt; b &amp; c"))
    }

    @Test func fencedCodeWithLanguage() {
        let html = render("```swift\nlet a = 1\n```")
        #expect(html.contains("<pre><code class=\"language-swift\">let a = 1</code></pre>"))
    }

    @Test func linksAndImages() {
        let html = render("[サイト](https://example.com \"例\") と ![図](img/a.png) と https://apple.com")
        #expect(html.contains("<a href=\"https://example.com\" title=\"例\">サイト</a>"))
        #expect(html.contains("<img src=\"img/a.png\" alt=\"図\">"))
        #expect(html.contains("<a href=\"https://apple.com\">https://apple.com</a>"))
    }

    @Test func nestedAndTaskLists() {
        let html = render("- 親\n  - 子\n- [x] 済み\n- [ ] まだ\n\n1. 一\n2. 二")
        #expect(html.contains("<ul>\n<li>親\n<ul>\n<li>子</li>"))
        #expect(html.contains("<input type=\"checkbox\" disabled checked> 済み"))
        #expect(html.contains("<input type=\"checkbox\" disabled> まだ"))
        #expect(html.contains("<ol>\n<li>一</li>\n<li>二</li>\n</ol>"))
    }

    @Test func orderedListStart() {
        #expect(render("3. 三\n4. 四").contains("<ol start=\"3\">"))
    }

    @Test func tablesWithAlignment() {
        let html = render("| 名前 | 数 |\n|:--|--:|\n| りんご | 3 |\n| み\\|かん | 5 |")
        #expect(html.contains("<th style=\"text-align:left\">名前</th>"))
        #expect(html.contains("<td style=\"text-align:right\">3</td>"))
        #expect(html.contains("み|かん"))
    }

    @Test func blockquoteAndRule() {
        let html = render("> 引用\n> 続き\n\n---\n")
        #expect(html.contains("<blockquote>\n<p>引用\n続き</p>\n</blockquote>"))
        #expect(html.contains("<hr>"))
    }

    @Test func frontMatterBecomesTable() {
        let html = render("---\ntitle: 議事録\ndate: 2026-10-26\n---\n# 本文")
        #expect(html.contains("<table class=\"front-matter\">"))
        #expect(html.contains("<th>title</th><td>議事録</td>"))
        #expect(html.contains("<h1"))
    }

    @Test func emphasisDoesNotBreakSnakeCase() {
        #expect(!render("file_name_here").contains("<em>"))
    }

    @Test func lineBreakWithTrailingSpaces() {
        #expect(render("一行目  \n二行目").contains("一行目<br>\n二行目"))
    }
}

struct FilePreviewKindTests {
    @Test func detectsPreviewableFiles() {
        #expect(FilePreviewController.kind(for: URL(fileURLWithPath: "/a/README.md")) == .markdown)
        #expect(FilePreviewController.kind(for: URL(fileURLWithPath: "/a/notes.MARKDOWN")) == .markdown)
        #expect(FilePreviewController.kind(for: URL(fileURLWithPath: "/a/index.html")) == .html)
        #expect(FilePreviewController.kind(for: URL(fileURLWithPath: "/a/page.HTM")) == .html)
        #expect(FilePreviewController.kind(for: URL(fileURLWithPath: "/a/app.swift")) == nil)
    }
}

struct VisualPreviewKindTests {
    @Test func detectsVisualFiles() {
        for name in ["photo.png", "photo.JPG", "scan.heic", "icon.svg", "paper.pdf", "clip.mov", "clip.mp4", "song.mp3", "deck.key", "deck.pptx", "sheet.xlsx", "doc.docx"] {
            #expect(FilePreviewController.kind(for: URL(fileURLWithPath: "/a/" + name)) == .visual, "\(name)")
        }
        for name in ["app.swift", "data.json", "archive.zip"] {
            #expect(FilePreviewController.kind(for: URL(fileURLWithPath: "/a/" + name)) == nil, "\(name)")
        }
    }
}

struct PreviewViewerTests {
    @Test func picksNativeViewers() {
        #expect(FilePreviewController.viewer(for: URL(fileURLWithPath: "/a/p.png")) == .image)
        #expect(FilePreviewController.viewer(for: URL(fileURLWithPath: "/a/p.pdf")) == .pdf)
        #expect(FilePreviewController.viewer(for: URL(fileURLWithPath: "/a/c.mov")) == .media)
        #expect(FilePreviewController.viewer(for: URL(fileURLWithPath: "/a/s.mp3")) == .media)
        #expect(FilePreviewController.viewer(for: URL(fileURLWithPath: "/a/d.key")) == .quickLook)
    }
}
