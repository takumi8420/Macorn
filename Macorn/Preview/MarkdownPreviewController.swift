import AppKit
import WebKit

/// Markdown のプレビュー（VS Code のプレビューのように、一覧の右に整形して表示する）。
/// ファイルが保存されたら自動で表示し直し、読んでいた位置も保つ。
final class MarkdownPreviewController: NSViewController {
    static let extensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn"]

    static func isMarkdown(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    private(set) var fileURL: URL?
    private(set) var lastHTMLLength = 0
    var onOpenInEditor: ((URL) -> Void)?
    var onClose: (() -> Void)?
    /// プレビューの中のリンクから、別の Markdown を開いたとき
    var onOpenMarkdown: ((URL) -> Void)?

    private let webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        // Markdown に書かれたスクリプトは動かさない（表示し直すときのスクロール位置の保存はアプリ側から行う）
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }()
    private let titleLabel = NSTextField(labelWithString: "")
    private var watcher: DispatchSourceFileSystemObject?
    private var pendingScrollY: Double?
    private let htmlFile = FileManager.default.temporaryDirectory
        .appendingPathComponent("macorn-preview", isDirectory: true)
        .appendingPathComponent("\(UUID().uuidString).html")

    override func loadView() {
        let container = PaneBackgroundView()

        let header = NSStackView()
        header.orientation = .horizontal
        header.spacing = 8
        header.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 8)
        let icon = NSImageView(image: NSImage(systemSymbolName: "doc.richtext", accessibilityDescription: "Markdown")!)
        icon.contentTintColor = .secondaryLabelColor
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let editButton = Self.headerButton(symbol: "square.and.pencil", tip: "エディタで開く（⌥⌘E）", target: self, action: #selector(openInEditor(_:)))
        let closeButton = Self.headerButton(symbol: "xmark", tip: "プレビューを閉じる（⌥⌘P で切り替え）", target: self, action: #selector(closePreview(_:)))
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        [icon, titleLabel, spacer, editButton, closeButton].forEach(header.addArrangedSubview)

        let separator = NSBox()
        separator.boxType = .separator

        webView.navigationDelegate = self
        for subview in [header, separator, webView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 28),
            separator.topAnchor.constraint(equalTo: header.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view = container
    }

    private static func headerButton(symbol: String, tip: String, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!, target: target, action: action)
        button.isBordered = false
        button.toolTip = tip
        button.contentTintColor = .secondaryLabelColor
        return button
    }

    // MARK: - 表示

    func show(_ url: URL) {
        if fileURL?.standardizedFileURL.path != url.standardizedFileURL.path {
            fileURL = url
            pendingScrollY = nil
            startWatching(url)
        }
        titleLabel.stringValue = url.lastPathComponent
        titleLabel.toolTip = url.path
        reload(keepingScroll: false)
    }

    func stop() {
        watcher?.cancel()
        watcher = nil
        fileURL = nil
    }

    /// 表示し直す。keepingScroll なら、読んでいた位置に戻す
    func reload(keepingScroll: Bool) {
        guard let url = fileURL else { return }
        if keepingScroll {
            webView.evaluateJavaScript("window.scrollY") { [weak self] value, _ in
                MainActor.assumeIsolated {
                    self?.pendingScrollY = value as? Double
                    self?.render(url)
                }
            }
        } else {
            render(url)
        }
    }

    private func render(_ url: URL) {
        let text: String
        if let data = try? Data(contentsOf: url) {
            text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        } else {
            text = "*「\(url.lastPathComponent)」を読めませんでした。*"
        }
        let html = Self.page(body: MarkdownRenderer.render(text), baseURL: url.deletingLastPathComponent(), title: url.lastPathComponent)
        lastHTMLLength = html.count
        do {
            try FileManager.default.createDirectory(at: htmlFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try html.write(to: htmlFile, atomically: true, encoding: .utf8)
            // 画像など、Markdown と同じフォルダのファイルも読めるようにする
            webView.loadFileURL(htmlFile, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        } catch {
            webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
        }
    }

    // MARK: - 保存されたら表示し直す

    private func startWatching(_ url: URL) {
        watcher?.cancel()
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .extend, .rename, .delete], queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let url = self.fileURL else { return }
                // エディタは「別名で書いてから置き換える」ことが多いので、監視し直す
                if source.data.contains(.rename) || source.data.contains(.delete) {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(150))
                        self.startWatching(url)
                        self.reload(keepingScroll: true)
                    }
                } else {
                    self.reload(keepingScroll: true)
                }
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    // MARK: - ボタン

    @objc private func openInEditor(_ sender: Any?) {
        guard let fileURL else { return }
        onOpenInEditor?(fileURL)
    }

    @objc private func closePreview(_ sender: Any?) {
        onClose?()
    }

    #if DEBUG
    func debugSnapshot(to url: URL, completion: @escaping () -> Void) {
        webView.takeSnapshot(with: nil) { image, _ in
            MainActor.assumeIsolated {
                if let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                    try? rep.representation(using: .png, properties: [:])?.write(to: url)
                }
                completion()
            }
        }
    }
    #endif

    // MARK: - HTML

    static func page(body: String, baseURL: URL, title: String) -> String {
        let base = baseURL.absoluteString.hasSuffix("/") ? baseURL.absoluteString : baseURL.absoluteString + "/"
        let accent = Theme.accentHex
        return """
        <!DOCTYPE html>
        <html lang="ja">
        <head>
        <meta charset="utf-8">
        <base href="\(MarkdownRenderer.escape(base))">
        <title>\(MarkdownRenderer.escape(title))</title>
        <style>
        :root { color-scheme: light dark; --accent: \(accent); --text: #1f2328; --muted: #59636e; --border: #d1d9e0; --code-bg: #f6f8fa; --bg: transparent; }
        @media (prefers-color-scheme: dark) { :root { --text: #e6edf3; --muted: #9198a1; --border: #3d444d; --code-bg: rgba(110,118,129,0.18); } }
        html { font-size: 15px; }
        body { font-family: -apple-system, "Hiragino Sans", "Helvetica Neue", sans-serif; color: var(--text); background: var(--bg);
               line-height: 1.7; margin: 0; padding: 20px 28px 48px; max-width: 900px; word-wrap: break-word; }
        h1, h2, h3, h4, h5, h6 { line-height: 1.3; margin: 1.6em 0 0.6em; font-weight: 600; }
        h1 { font-size: 1.9em; padding-bottom: 0.3em; border-bottom: 1px solid var(--border); margin-top: 0.4em; }
        h2 { font-size: 1.45em; padding-bottom: 0.25em; border-bottom: 1px solid var(--border); }
        h3 { font-size: 1.2em; } h4 { font-size: 1.05em; } h5, h6 { font-size: 0.95em; color: var(--muted); }
        p, ul, ol, blockquote, pre, table { margin: 0 0 1em; }
        a { color: var(--accent); text-decoration: none; } a:hover { text-decoration: underline; }
        code { font-family: "SF Mono", Menlo, monospace; font-size: 0.88em; background: var(--code-bg); padding: 0.15em 0.4em; border-radius: 5px; }
        pre { background: var(--code-bg); padding: 14px 16px; border-radius: 8px; overflow-x: auto; line-height: 1.5; }
        pre code { background: none; padding: 0; font-size: 0.86em; }
        blockquote { margin-left: 0; padding: 0 1em; color: var(--muted); border-left: 4px solid var(--border); }
        ul, ol { padding-left: 1.8em; } li + li { margin-top: 0.25em; } li > ul, li > ol { margin: 0.25em 0 0; }
        li.task { list-style: none; margin-left: -1.4em; } li.task input { margin-right: 0.4em; accent-color: var(--accent); }
        hr { border: none; border-top: 1px solid var(--border); margin: 2em 0; }
        table { border-collapse: collapse; display: block; overflow-x: auto; }
        th, td { border: 1px solid var(--border); padding: 6px 12px; } th { font-weight: 600; background: var(--code-bg); }
        table.front-matter { font-size: 0.9em; color: var(--muted); } table.front-matter th { text-align: left; }
        img { max-width: 100%; border-radius: 4px; }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }
}

// MARK: - リンク

extension MarkdownPreviewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        // 同じページの見出しへのリンク
        if url.isFileURL, url.path == htmlFile.path, url.fragment != nil {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        if url.isFileURL, Self.isMarkdown(url) {
            onOpenMarkdown?(url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let y = pendingScrollY else { return }
        pendingScrollY = nil
        webView.evaluateJavaScript("window.scrollTo(0, \(y))")
    }
}
