import AppKit
import AVKit
import PDFKit
import Quartz
import UniformTypeIdentifiers
import WebKit

/// ファイルのプレビュー（VS Code のプレビューのように、一覧の右に表示する）。
/// Markdown は整形して、HTML はそのページを、画像・PDF・動画・書類などはクイックルックで表示する。
/// ファイルが保存されたら自動で表示し直し、読んでいた位置も保つ。
final class FilePreviewController: NSViewController {
    enum Kind: Equatable {
        case markdown, html
        /// 画像・PDF・動画・音声・書類など、目で見て確認するもの
        case visual
    }

    /// 目で見て確認するもののうち、何で表示するか
    enum Viewer: Equatable {
        case image, pdf, media, quickLook
    }

    static func viewer(for url: URL) -> Viewer {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return .quickLook }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .audiovisualContent) { return .media }
        if type.conforms(to: .image) { return .image }
        return .quickLook
    }

    /// クイックルックで見せる種類（目で見て確認できるもの）
    static let visualTypes: [UTType] = [
        .image, .pdf, .audiovisualContent, .presentation, .spreadsheet,
        UTType("org.openxmlformats.wordprocessingml.document"),
        UTType("com.microsoft.word.doc"),
        UTType("com.apple.iwork.pages.sffpages"),
        .rtf,
    ].compactMap { $0 }

    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn"]
    static let htmlExtensions: Set<String> = ["html", "htm", "xhtml"]

    /// プレビューできるファイルの種類。できなければ nil
    /// 拡張子がほかの種類（動画など）と重なるソースコード
    static let sourceCodeExtensions: Set<String> = ["ts", "mts", "cts", "tsx"]

    static func kind(for url: URL) -> Kind? {
        let ext = url.pathExtension.lowercased()
        // TypeScript（.ts）は動画の MPEG-2 TS と同じ拡張子なので、動画として扱わない
        if sourceCodeExtensions.contains(ext) { return nil }
        if markdownExtensions.contains(ext) { return .markdown }
        if htmlExtensions.contains(ext) { return .html }
        if let type = UTType(filenameExtension: ext), visualTypes.contains(where: { type.conforms(to: $0) }) {
            return .visual
        }
        return nil
    }

    static func isMarkdown(_ url: URL) -> Bool { kind(for: url) == .markdown }

    private(set) var fileURL: URL?
    private(set) var kind: Kind = .markdown
    /// HTML のスクリプトを動かすか（安全のため初めは動かさない。ファイルごとにボタンで切り替える）
    private(set) var scriptsEnabled = false
    private(set) var lastHTMLLength = 0
    var onOpenInEditor: ((URL) -> Void)?
    var onClose: (() -> Void)?
    /// プレビューの中のリンクから、別のプレビューできるファイル（Markdown・HTML）を開いたとき
    var onOpenPreviewable: ((URL) -> Void)?

    private let webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        // ファイルに書かれたスクリプトは初めは動かさない（スクロール位置の保存はアプリ側から行うので動く）
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        // トラックパッドの2本指で拡大・縮小できるようにする
        webView.allowsMagnification = true
        return webView
    }()
    /// 画像・PDF・動画は macOS の部品で表示し、それ以外の書類はクイックルックで表示する
    private var quickLookView: QLPreviewView?
    private let imageView: NSImageView = {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyDown
        view.animates = true
        return view
    }()
    private let pdfView: PDFView = {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .clear
        return view
    }()
    private let playerView: AVPlayerView = {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        return view
    }()
    private(set) var viewer: Viewer = .quickLook
    private var editButton: NSButton?
    private let titleLabel = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private var scriptButton: NSButton?
    private var browserButton: NSButton?
    private var zoomControls: NSStackView?
    nonisolated(unsafe) private var magnifyMonitor: Any?
    private let zoomLabel = NSButton(title: "100%", target: nil, action: nil)

    /// 拡大・縮小の範囲と段階（ブラウザと同じくらい）
    static let zoomSteps: [Double] = [0.25, 0.33, 0.5, 0.67, 0.75, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 4.0, 5.0]
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
        let icon = iconView
        icon.contentTintColor = .secondaryLabelColor
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let scriptButton = Self.headerButton(symbol: "curlybraces", tip: "", target: self, action: #selector(toggleScripts(_:)))
        let browserButton = Self.headerButton(symbol: "safari", tip: "ブラウザで開く", target: self, action: #selector(openInBrowser(_:)))
        self.scriptButton = scriptButton
        self.browserButton = browserButton
        let editButton = Self.headerButton(symbol: "square.and.pencil", tip: "エディタで開く（⌥⌘E）", target: self, action: #selector(openInEditor(_:)))
        self.editButton = editButton
        let closeButton = Self.headerButton(symbol: "xmark", tip: "プレビューを閉じる（⌥⌘P で切り替え）", target: self, action: #selector(closePreview(_:)))
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let zoomOut = Self.headerButton(symbol: "minus.magnifyingglass", tip: "縮小（⌘−）", target: self, action: #selector(zoomOut(_:)))
        let zoomIn = Self.headerButton(symbol: "plus.magnifyingglass", tip: "拡大（⌘+）", target: self, action: #selector(zoomIn(_:)))
        zoomLabel.isBordered = false
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        zoomLabel.contentTintColor = .secondaryLabelColor
        zoomLabel.target = self
        zoomLabel.action = #selector(resetZoom(_:))
        zoomLabel.toolTip = "実際のサイズに戻す（PDF はページの幅に合わせる）（⌘0）"
        zoomLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 42).isActive = true
        let zoomControls = NSStackView(views: [zoomOut, zoomLabel, zoomIn])
        zoomControls.spacing = 2
        self.zoomControls = zoomControls
        [icon, titleLabel, spacer, zoomControls, scriptButton, browserButton, editButton, closeButton].forEach(header.addArrangedSubview)
        updateHeader()

        let separator = NSBox()
        separator.boxType = .separator

        webView.navigationDelegate = self
        let quickLook: QLPreviewView = QLPreviewView(frame: .zero, style: .normal)
        quickLook.autostarts = false
        quickLook.isHidden = true
        quickLookView = quickLook
        for subview in [header, separator, webView, quickLook, imageView, pdfView, playerView] {
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
            quickLook.topAnchor.constraint(equalTo: separator.bottomAnchor),
            quickLook.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            quickLook.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            quickLook.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        // 画像・PDF・動画も、同じ場所に重ねて置き、使うものだけを見せる
        for content in [imageView, pdfView, playerView] as [NSView] {
            content.isHidden = true
            NSLayoutConstraint.activate([
                content.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: content === imageView ? 12 : 0),
                content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: content === imageView ? 12 : 0),
                content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: content === imageView ? -12 : 0),
                content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: content === imageView ? -12 : 0),
            ])
        }
        view = container

        // ピンチで拡大・縮小したときも、倍率の表示を合わせる
        NotificationCenter.default.addObserver(self, selector: #selector(zoomChangedElsewhere(_:)), name: .PDFViewScaleChanged, object: pdfView)
        magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .endGesture) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window === self.view.window else { return }
                self.updateZoomLabel()
                if self.kind != .visual { Preferences.previewZoom = self.zoom }
            }
            return event
        }
    }

    @objc private func zoomChangedElsewhere(_ notification: Notification) {
        updateZoomLabel()
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
            kind = Self.kind(for: url) ?? .markdown
            viewer = Self.viewer(for: url)
            scriptsEnabled = false
            clearVisualContent()
            webView.magnification = 1
            webView.pageZoom = CGFloat(Preferences.previewZoom)
            pdfView.autoScales = true
            pendingScrollY = nil
            startWatching(url)
            updateHeader()
        }
        titleLabel.stringValue = url.lastPathComponent
        titleLabel.toolTip = url.path
        reload(keepingScroll: false)
    }

    func stop() {
        watcher?.cancel()
        watcher = nil
        fileURL = nil
        // 動画・音声の再生を止める
        clearVisualContent()
    }

    private func clearVisualContent() {
        quickLookView?.previewItem = nil
        playerView.player?.pause()
        playerView.player = nil
        pdfView.document = nil
        imageView.image = nil
    }

    /// 表示し直す。keepingScroll なら、読んでいた位置に戻す
    func reload(keepingScroll: Bool) {
        guard let url = fileURL else { return }
        if keepingScroll, kind != .visual {
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

    /// 画像・PDF・動画・書類を、それぞれに合った部品で表示する（保存し直されたら読み直す）
    private func renderVisual(_ url: URL) {
        switch viewer {
        case .image:
            if let image = NSImage(contentsOf: url) {
                imageView.image = image
            } else {
                // 読めない画像（一部の SVG など）はクイックルックに任せる
                viewer = .quickLook
                updateHeader()
                renderVisual(url)
            }
        case .pdf:
            let page = pdfView.currentPage.flatMap { pdfView.document?.index(for: $0) }
            pdfView.document = PDFDocument(url: url)
            if let page, let target = pdfView.document?.page(at: page) { pdfView.go(to: target) }
        case .media:
            if (playerView.player?.currentItem?.asset as? AVURLAsset)?.url.path != url.path {
                playerView.player?.pause()
                playerView.player = AVPlayer(url: url)
            }
        case .quickLook:
            guard let quickLookView else { return }
            if (quickLookView.previewItem as? NSURL)?.path == url.path {
                quickLookView.refreshPreviewItem()
            } else {
                quickLookView.previewItem = url as NSURL
            }
        }
    }

    private static func symbol(for viewer: Viewer) -> String {
        switch viewer {
        case .image: "photo"
        case .pdf: "doc.text.image"
        case .media: "play.rectangle"
        case .quickLook: "eye"
        }
    }

    /// 見出しのアイコンとボタンを、ファイルの種類に合わせる
    deinit {
        if let magnifyMonitor { NSEvent.removeMonitor(magnifyMonitor) }
    }

    // MARK: - 拡大・縮小

    /// 今のファイルで拡大・縮小できるか
    var canZoom: Bool {
        kind != .visual || viewer == .pdf
    }

    /// 今の倍率（Markdown・HTML はページの倍率、PDF は表示の倍率）
    var zoom: Double {
        if kind == .visual { return Double(pdfView.scaleFactor) }
        return Double(webView.pageZoom) * Double(webView.magnification)
    }

    @objc func zoomIn(_ sender: Any?) { stepZoom(up: true) }
    @objc func zoomOut(_ sender: Any?) { stepZoom(up: false) }

    @objc func resetZoom(_ sender: Any?) {
        if kind == .visual {
            pdfView.autoScales = true
        } else {
            webView.magnification = 1
            setWebZoom(1)
        }
        updateZoomLabel()
    }

    private func stepZoom(up: Bool) {
        guard canZoom else { return }
        let current = zoom
        // 今の倍率から少なくとも 5% は変わる段階へ進む（PDF の「幅に合わせる」の倍率は段階の間にあるため）
        let next = up
            ? Self.zoomSteps.first { $0 > current * 1.05 } ?? Self.zoomSteps.last!
            : Self.zoomSteps.last { $0 < current / 1.05 } ?? Self.zoomSteps.first!
        if kind == .visual {
            pdfView.autoScales = false
            pdfView.scaleFactor = CGFloat(next)
        } else {
            // ピンチで拡大していた分は、ページの倍率にまとめる
            webView.magnification = 1
            setWebZoom(next)
        }
        updateZoomLabel()
    }

    /// Markdown・HTML の倍率を変えて、次に開いたときのために覚えておく
    private func setWebZoom(_ value: Double) {
        webView.pageZoom = CGFloat(value)
        Preferences.previewZoom = value
    }

    private func updateZoomLabel() {
        zoomLabel.title = "\(Int((zoom * 100).rounded()))%"
    }

    private func updateHeader() {
        let isHTML = kind == .html
        let isVisual = kind == .visual
        let symbol = isVisual ? "eye" : (isHTML ? "globe" : "doc.richtext")
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: isVisual ? "プレビュー" : (isHTML ? "HTML" : "Markdown"))
        scriptButton?.isHidden = !isHTML
        // 拡大・縮小は、Markdown・HTML・PDF で使える
        zoomControls?.isHidden = !canZoom
        updateZoomLabel()
        // HTML は「ブラウザで開く」、画像・PDF・動画などは「既定のアプリで開く」
        browserButton?.isHidden = !(isHTML || isVisual)
        browserButton?.image = NSImage(systemSymbolName: isVisual ? "arrow.up.forward.app" : "safari", accessibilityDescription: nil)
        browserButton?.toolTip = isVisual ? "既定のアプリで開く" : "ブラウザで開く"
        editButton?.isHidden = isVisual
        webView.isHidden = isVisual
        quickLookView?.isHidden = !(isVisual && viewer == .quickLook)
        imageView.isHidden = !(isVisual && viewer == .image)
        pdfView.isHidden = !(isVisual && viewer == .pdf)
        playerView.isHidden = !(isVisual && viewer == .media)
        if isVisual, let fileURL {
            iconView.image = NSImage(systemSymbolName: Self.symbol(for: Self.viewer(for: fileURL)), accessibilityDescription: nil)
        }
        scriptButton?.contentTintColor = scriptsEnabled ? Theme.shared.accentColor : .secondaryLabelColor
        scriptButton?.toolTip = scriptsEnabled
            ? "スクリプトを動かしています（クリックで止める）"
            : "スクリプトは止めています（クリックで、このファイルに限って動かす）"
        // HTML は白い背景を前提に作られていることが多いので、背景を描く。Markdown は画面の背景になじませる
        webView.setValue(isHTML, forKey: "drawsBackground")
    }

    private func render(_ url: URL) {
        if kind == .visual {
            lastHTMLLength = Int((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            renderVisual(url)
            return
        }
        if kind == .html {
            lastHTMLLength = (try? Data(contentsOf: url).count) ?? 0
            // 同じフォルダの CSS・画像・スクリプトだけを読めるようにする
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            return
        }
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

    @objc private func toggleScripts(_ sender: Any?) {
        scriptsEnabled.toggle()
        updateHeader()
        reload(keepingScroll: true)
    }

    @objc private func openInBrowser(_ sender: Any?) {
        guard let fileURL else { return }
        NSWorkspace.shared.open(fileURL)
    }

    #if DEBUG
    func debugToggleScripts() { toggleScripts(nil) }

    var debugQuickLookState: String {
        "pdfPage=\(pdfView.currentPage.flatMap { pdfView.document?.index(for: $0) } ?? -1) pdfDoc=\(pdfView.documentView.map { "\(Int($0.frame.width))x\(Int($0.frame.height))" } ?? "-") scale=\(String(format: "%.2f", pdfView.scaleFactor)) pdfFrame=\(Int(pdfView.frame.width))x\(Int(pdfView.frame.height)) " + "viewer=\(viewer) image=\(imageView.image.map { "\(Int($0.size.width))x\(Int($0.size.height))" } ?? "-") pdfPages=\(pdfView.document?.pageCount ?? 0) player=\(playerView.player?.currentItem?.status.rawValue ?? -1) " + "ql hidden=\(quickLookView?.isHidden ?? true) item=\((quickLookView?.previewItem as? NSURL)?.lastPathComponent ?? "-") web hidden=\(webView.isHidden) edit hidden=\(editButton?.isHidden ?? true) open=\(browserButton?.toolTip ?? "-")"
    }

    /// 表示中の Web の領域（Markdown・HTML のときだけ）。ウィンドウの撮影では映らないので、宣伝用の撮影で別に撮って重ねる
    var debugVisibleWebView: NSView? {
        webView.window != nil && !webView.isHiddenOrHasHiddenAncestor ? webView : nil
    }

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

extension FilePreviewController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        // スクリプトは、HTML でボタンを押して許したときだけ動かす
        preferences.allowsContentJavaScript = kind == .html && scriptsEnabled
        guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
            decisionHandler(.allow, preferences)
            return
        }
        // 同じページの中へのリンク（#見出し）
        let currentPage = kind == .html ? fileURL?.path : htmlFile.path
        if url.isFileURL, url.path == currentPage, url.fragment != nil {
            decisionHandler(.allow, preferences)
            return
        }
        decisionHandler(.cancel, preferences)
        if url.isFileURL, Self.kind(for: url) != nil {
            onOpenPreviewable?(url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateZoomLabel()
        guard let y = pendingScrollY else { return }
        pendingScrollY = nil
        webView.evaluateJavaScript("window.scrollTo(0, \(y))")
    }
}
