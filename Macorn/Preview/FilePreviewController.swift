import AppKit
import AVKit
import PDFKit
import Quartz
import UniformTypeIdentifiers
import WebKit

/// ファイルのプレビュー（VS Code のプレビューのように、一覧の右に表示する）。
/// Markdown は整形して、CSV・TSV は表にして、HTML はそのページを、画像・PDF・動画・書類などはクイックルックで表示する。
/// ファイルが保存されたら自動で表示し直し、読んでいた位置も保つ。
final class FilePreviewController: NSViewController {
    enum Kind: Equatable {
        case markdown, html
        /// テキスト（.txt。書いてあるとおりに見せ、その場で書き換えられる）
        case text
        /// CSV・TSV（表にして見せる）
        case csv
        /// 画像・PDF・動画・音声・書類など、目で見て確認するもの
        case visual
    }

    /// 目で見て確認するもののうち、何で表示するか
    enum Viewer: Equatable {
        /// document は Word の書類（クイックルックの HTML を、幅に合わせて折り返して Web の領域に出す）
        case image, pdf, media, document, quickLook
    }

    static func viewer(for url: URL) -> Viewer {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return .quickLook }
        if WordRenderer.isWord(url) { return .document }
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
    static let csvExtensions: Set<String> = ["csv", "tsv", "tab"]
    static let textExtensions: Set<String> = ["txt", "text"]

    /// プレビューできるファイルの種類。できなければ nil
    /// 拡張子がほかの種類（動画など）と重なるソースコード
    static let sourceCodeExtensions: Set<String> = ["ts", "mts", "cts", "tsx"]

    static func kind(for url: URL) -> Kind? {
        let ext = url.pathExtension.lowercased()
        // TypeScript（.ts）は動画の MPEG-2 TS と同じ拡張子なので、動画として扱わない
        if sourceCodeExtensions.contains(ext) { return nil }
        if markdownExtensions.contains(ext) { return .markdown }
        if htmlExtensions.contains(ext) { return .html }
        if csvExtensions.contains(ext) { return .csv }
        if textExtensions.contains(ext) { return .text }
        if let type = UTType(filenameExtension: ext), visualTypes.contains(where: { type.conforms(to: $0) }) {
            return .visual
        }
        return nil
    }

    static func isMarkdown(_ url: URL) -> Bool { kind(for: url) == .markdown }

    /// プレビューのまま書き換えられる種類（Markdown・テキスト）
    var isEditableKind: Bool { kind == .markdown || kind == .text }

    private(set) var fileURL: URL?
    private(set) var kind: Kind = .markdown
    /// HTML のスクリプトを動かすか（安全のため初めは動かさない。ファイルごとにボタンで切り替える）
    private(set) var scriptsEnabled = false
    private(set) var lastHTMLLength = 0
    var onOpenInEditor: ((URL) -> Void)?
    var onClose: (() -> Void)?
    /// ヘッダーの「最大化」ボタン（一覧・サイドバー・ほかの画面を畳んで、プレビューを広げる）
    var onToggleMaximize: (() -> Void)?
    /// ヘッダーの左端の「一覧を畳む」ボタン（一覧だけを畳む）
    var onCollapseList: (() -> Void)?
    /// プレビューの中のリンクから、別のプレビューできるファイル（Markdown・HTML）を開いたとき
    var onOpenPreviewable: ((URL) -> Void)?

    private let webView: PreviewWebView = {
        let configuration = WKWebViewConfiguration()
        // ファイルに書かれたスクリプトは初めは動かさない（スクロール位置の保存はアプリ側から行うので動く）
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        // Markdown をプレビューで編集するためのスクリプト（ページのスクリプトとは別の場所で動く）
        configuration.userContentController.addUserScript(MarkdownEditor.userScript)
        let webView = PreviewWebView(frame: .zero, configuration: configuration)
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
    private var maximizeButton: NSButton?
    /// 一覧を畳んでいるときだけ左上に出す「一覧を表示」ボタン（戻し方が分かるように）
    private var showListButton: NSButton?
    /// 一覧を出しているときに左上に出す「一覧を畳む」ボタン（「一覧を表示」と同じ位置）
    private var hideListButton: NSButton?
    private var zoomControls: NSStackView?
    nonisolated(unsafe) private var magnifyMonitor: Any?
    private let zoomLabel = NSButton(title: "100%", target: nil, action: nil)

    /// 拡大・縮小の範囲と段階（ブラウザと同じくらい）
    static let zoomSteps: [Double] = [0.25, 0.33, 0.5, 0.67, 0.75, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 4.0, 5.0]
    /// Word の書類を HTML にする作業場所と、今の変換の印（古い変換の結果を出さないため）
    private let wordDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("macorn-word", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    private var wordRenderID = UUID()
    private var watcher: DispatchSourceFileSystemObject?
    /// プレビューでの編集で最後に保存した中身（自分で保存したときは表示し直さないため）
    private var savedByEditor: [String: Data] = [:]
    /// 編集できるように表示した Markdown（ほかのファイルへ移った直後に届いた保存も受け付けるため）
    private var editablePaths: Set<String> = []
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
        let browserButton = Self.headerButton(symbol: "safari", tip: "このファイルをブラウザで開く", target: self, action: #selector(openInBrowser(_:)))
        self.scriptButton = scriptButton
        self.browserButton = browserButton
        let editButton = Self.headerButton(symbol: "square.and.pencil", tip: "このファイルをエディタで開く（⌥⌘E）", target: self, action: #selector(openInEditor(_:)))
        self.editButton = editButton
        let maximizeButton = Self.headerButton(symbol: "arrow.up.left.and.arrow.down.right", tip: "", target: self, action: #selector(toggleMaximize(_:)))
        self.maximizeButton = maximizeButton
        let showListButton = NSButton(title: "一覧を表示", image: NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "一覧を表示")!, target: self, action: #selector(toggleMaximize(_:)))
        showListButton.bezelStyle = .accessoryBarAction
        showListButton.controlSize = .small
        showListButton.font = .systemFont(ofSize: 11, weight: .medium)
        showListButton.imagePosition = .imageLeading
        showListButton.toolTip = "畳んだファイルの一覧を表示する（⇧⌘↩）"
        showListButton.isHidden = true
        self.showListButton = showListButton
        let hideListButton = Self.headerButton(symbol: "sidebar.left", tip: "ファイルの一覧を畳む（もう一度押すと戻す）", target: self, action: #selector(collapseList(_:)))
        self.hideListButton = hideListButton
        setMaximized(false)
        let closeButton = Self.headerButton(symbol: "xmark", tip: "このファイルのプレビューを閉じる（別のファイルを選ぶとまた出ます。出さないようにするには ⌥⌘P）", target: self, action: #selector(closePreview(_:)))
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let zoomOut = Self.headerButton(symbol: "minus.magnifyingglass", tip: "プレビューを縮小（⌘−）", target: self, action: #selector(zoomOut(_:)))
        let zoomIn = Self.headerButton(symbol: "plus.magnifyingglass", tip: "プレビューを拡大（⌘+）", target: self, action: #selector(zoomIn(_:)))
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
        [showListButton, hideListButton, icon, titleLabel, spacer, zoomControls, scriptButton, browserButton, editButton, maximizeButton, closeButton].forEach(header.addArrangedSubview)
        updateHeader()

        let separator = NSBox()
        separator.boxType = .separator

        webView.navigationDelegate = self
        webView.configuration.userContentController.add(EditorMessageProxy(self), contentWorld: MarkdownEditor.world, name: MarkdownEditor.messageName)
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
                if self.usesWebView { Preferences.previewZoom = self.zoom }
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
        let switching = fileURL?.standardizedFileURL.path != url.standardizedFileURL.path
        if switching {
            flushEditor()
            fileURL = url
            kind = Self.kind(for: url) ?? .markdown
            viewer = Self.viewer(for: url)
            scriptsEnabled = false
            clearVisualContent()
            // Word の書類は変換を待つ間、前のファイルを見せない
            if kind == .visual, viewer == .document { webView.loadHTMLString("", baseURL: nil) }
            webView.magnification = 1
            webView.pageZoom = CGFloat(Preferences.previewZoom)
            pdfView.autoScales = true
            pendingScrollY = nil
            startWatching(url)
            updateHeader()
        }
        titleLabel.stringValue = url.lastPathComponent
        titleLabel.toolTip = url.path
        // プレビューで編集して保存しただけなら、表示し直さない（一覧の更新で呼ばれても、カーソルを保つ）
        if !switching, isEditableKind, let saved = savedByEditor[url.path], (try? Data(contentsOf: url)) == saved { return }
        reload(keepingScroll: false)
    }

    func stop() {
        flushEditor()
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
        if keepingScroll, usesWebView {
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
        case .document:
            let id = UUID()
            wordRenderID = id
            Task {
                let page = await WordRenderer.render(url, into: wordDirectory.appendingPathComponent(id.uuidString, isDirectory: true))
                guard wordRenderID == id, fileURL?.path == url.path, viewer == .document else { return }
                if let page {
                    lastHTMLLength = (try? Data(contentsOf: page).count) ?? 0
                    webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
                    // 前の変換の作業場所を片付ける
                    for old in (try? FileManager.default.contentsOfDirectory(at: wordDirectory, includingPropertiesForKeys: nil)) ?? []
                    where old.lastPathComponent != id.uuidString {
                        try? FileManager.default.removeItem(at: old)
                    }
                } else {
                    // 変換できなければ、これまでどおりクイックルックで見せる
                    viewer = .quickLook
                    updateHeader()
                    renderVisual(url)
                }
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
        case .document: "doc.text"
        case .quickLook: "eye"
        }
    }

    /// 見出しのアイコンとボタンを、ファイルの種類に合わせる
    deinit {
        if let magnifyMonitor { NSEvent.removeMonitor(magnifyMonitor) }
        try? FileManager.default.removeItem(at: wordDirectory)
    }

    // MARK: - 拡大・縮小

    /// Web の領域で見せているか（Markdown・HTML・CSV・Word の書類）
    var usesWebView: Bool {
        kind != .visual || viewer == .document
    }

    /// 今のファイルで拡大・縮小できるか
    var canZoom: Bool {
        usesWebView || viewer == .pdf
    }

    /// 今の倍率（Markdown・HTML・Word はページの倍率、PDF は表示の倍率）
    var zoom: Double {
        if !usesWebView { return Double(pdfView.scaleFactor) }
        return Double(webView.pageZoom) * Double(webView.magnification)
    }

    @objc func zoomIn(_ sender: Any?) { stepZoom(up: true) }
    @objc func zoomOut(_ sender: Any?) { stepZoom(up: false) }

    @objc func resetZoom(_ sender: Any?) {
        if !usesWebView {
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
        if !usesWebView {
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
        let isCSV = kind == .csv
        let isText = kind == .text
        let symbol = isVisual ? "eye" : isHTML ? "globe" : isCSV ? "tablecells" : isText ? "doc.plaintext" : "doc.richtext"
        iconView.image = NSImage(systemSymbolName: symbol,
                                 accessibilityDescription: isVisual ? "プレビュー" : isHTML ? "HTML" : isCSV ? "CSV" : isText ? "テキスト" : "Markdown")
        scriptButton?.isHidden = !isHTML
        // 拡大・縮小は、Markdown・HTML・PDF で使える
        zoomControls?.isHidden = !canZoom
        updateZoomLabel()
        // HTML は「ブラウザで開く」、画像・PDF・動画などは「既定のアプリで開く」、CSV は表計算などの「ほかのアプリで開く」
        browserButton?.isHidden = !(isHTML || isVisual || isCSV)
        browserButton?.image = NSImage(systemSymbolName: isHTML ? "safari" : "arrow.up.forward.app", accessibilityDescription: nil)
        browserButton?.toolTip = isHTML ? "ブラウザで開く" : isCSV ? "ほかのアプリで開く" : "既定のアプリで開く"
        editButton?.isHidden = isVisual
        webView.isHidden = !usesWebView
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
        // Word の書類も白い紙を前提にしているので、背景を描く
        webView.setValue(isHTML || (isVisual && viewer == .document), forKey: "drawsBackground")
    }

    private func render(_ url: URL) {
        if kind == .visual {
            lastHTMLLength = Int((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            renderVisual(url)
            return
        }
        webView.claimsEditingKeys = false
        if kind == .html {
            lastHTMLLength = (try? Data(contentsOf: url).count) ?? 0
            // 同じフォルダの CSS・画像・スクリプトだけを読めるようにする
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            return
        }
        let html: String
        if kind == .csv {
            let body = (try? Data(contentsOf: url)).map {
                CSVRenderer.render(CSVRenderer.table(from: $0, fileExtension: url.pathExtension))
            } ?? "<p>「\(MarkdownRenderer.escape(url.lastPathComponent))」を読めませんでした。</p>"
            webView.claimsEditingKeys = false
            html = Self.page(body: body, baseURL: url.deletingLastPathComponent(), title: url.lastPathComponent, extraStyle: CSVRenderer.style)
        } else {
            let text: String
            let data = try? Data(contentsOf: url)
            // UTF-8 で読める Markdown・テキストだけを、プレビューで編集できるようにする（ほかの文字コードを書き換えないため）
            let strict = data.flatMap { String(data: $0, encoding: .utf8) }
            if let data {
                text = strict ?? String(decoding: data, as: UTF8.self)
            } else {
                text = kind == .text ? "「\(url.lastPathComponent)」を読めませんでした。" : "*「\(url.lastPathComponent)」を読めませんでした。*"
            }
            let editable = strict != nil
            let body: String
            let document: MarkdownRenderer.EditableDocument
            if kind == .text {
                // テキストは書いてあるとおりに見せる（改行の形だけ LF にそろえ、保存のときに戻す）
                let crlf = text.contains("\r\n")
                let plain = text.replacingOccurrences(of: "\r\n", with: "\n")
                body = "<div id=\"md-plain\">\(MarkdownRenderer.escape(plain))</div>"
                document = MarkdownRenderer.EditableDocument(head: "", blocks: [], tail: plain, crlf: crlf)
            } else {
                (body, document) = MarkdownRenderer.renderEditable(text)
            }
            let payload = EditorPayload(path: url.path, editable: editable, plain: kind == .text, document: document)
            // スクリプトを止めたページでは <script> の要素が消えるので、属性で渡す
            let json = (try? JSONEncoder().encode(payload)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            if editable { editablePaths.insert(url.path) }
            webView.claimsEditingKeys = editable
            html = Self.page(body: body, baseURL: url.deletingLastPathComponent(), title: url.lastPathComponent,
                             extraStyle: (kind == .text ? MarkdownEditor.plainStyle : "") + (editable ? MarkdownEditor.style : ""),
                             extraHead: "<meta name=\"macorn-md\" content=\"\(MarkdownRenderer.escape(json))\">")
        }
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
                // プレビューでの編集を保存しただけなら、表示し直さない（打っている途中のカーソルを保つ）
                // 書き込みの途中（中身を空にした直後）にも知らせが来るので、少し待ってから中身を比べる
                if let saved = self.savedByEditor[url.path] {
                    let events = source.data
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(150))
                        guard self.fileURL?.path == url.path else { return }
                        if events.contains(.rename) || events.contains(.delete) { self.startWatching(url) }
                        if (try? Data(contentsOf: url)) == saved { return }
                        self.savedByEditor[url.path] = nil
                        self.reload(keepingScroll: true)
                    }
                    return
                }
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

    @objc private func collapseList(_ sender: Any?) {
        onCollapseList?()
    }

    @objc private func toggleMaximize(_ sender: Any?) {
        onToggleMaximize?()
    }

    /// 「最大化」ボタンの見た目。広げている（一覧を畳んでいる）ときは「元に戻す」にする
    func setMaximized(_ maximized: Bool) {
        isMaximizedAppearance = maximized
        showListButton?.isHidden = !maximized
        hideListButton?.isHidden = maximized
        let symbol = maximized ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
        let tip = maximized ? "元の大きさに戻す（⇧⌘↩）" : "プレビューを最大化（一覧・サイドバー・ほかの画面を畳む）（⇧⌘↩）"
        maximizeButton?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        maximizeButton?.toolTip = tip
    }

    private(set) var isMaximizedAppearance = false

    @objc private func toggleScripts(_ sender: Any?) {
        scriptsEnabled.toggle()
        updateHeader()
        reload(keepingScroll: true)
    }

    @objc private func openInBrowser(_ sender: Any?) {
        guard let fileURL else { return }
        // HTML の既定のアプリを Macorn にしていても、ブラウザなどほかのアプリで開く
        DefaultFileApps.openOutside(fileURL)
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

    static func page(body: String, baseURL: URL, title: String, extraStyle: String = "", extraHead: String = "") -> String {
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
        \(extraStyle)
        </style>
        \(extraHead)
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

// MARK: - プレビューでの Markdown の編集

extension FilePreviewController {
    /// 編集用のスクリプトに渡すもの
    struct EditorPayload: Encodable {
        var path: String
        var editable: Bool
        /// テキスト（Markdown の書き方を使わず、書いたとおりに保存する）
        var plain: Bool
        var document: MarkdownRenderer.EditableDocument
    }

    /// 打ちかけの編集を、すぐに保存させる（ほかのファイルへ移る前など）
    func flushEditor() {
        guard isEditableKind, fileURL != nil else { return }
        webView.evaluateJavaScript("window.__macornEditorFlush && window.__macornEditorFlush()", in: nil, in: MarkdownEditor.world) { _ in }
    }

    func handleEditorMessage(_ body: Any) {
        guard let message = body as? [String: Any], let type = message["type"] as? String else { return }
        switch type {
        case "save":
            guard let path = message["path"] as? String, editablePaths.contains(path), let text = message["text"] as? String else { return }
            saveEditedMarkdown(text, to: URL(fileURLWithPath: path))
        case "open":
            guard let href = message["href"] as? String, let url = URL(string: href) else { return }
            if url.isFileURL, Self.kind(for: url) != nil {
                onOpenPreviewable?(url)
            } else {
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }
    }

    /// 編集した Markdown を保存する。改行の形（LF・CRLF）は元のファイルに合わせる
    /// ファイルを置き換えず、中身だけを書き換える（タグなどが追いかけているファイルの同一性を保つため）
    func saveEditedMarkdown(_ text: String, to url: URL) {
        var text = text
        if let current = try? Data(contentsOf: url), let original = String(data: current, encoding: .utf8), original.contains("\r\n") {
            text = text.replacingOccurrences(of: "\n", with: "\r\n")
        }
        let data = Data(text.utf8)
        if (try? Data(contentsOf: url)) == data { return }
        savedByEditor[url.path] = data
        do {
            try data.write(to: url)
        } catch {
            savedByEditor[url.path] = nil
            let alert = NSAlert()
            alert.messageText = "「\(url.lastPathComponent)」を保存できませんでした"
            alert.informativeText = error.localizedDescription
            if let window = view.window { alert.beginSheetModal(for: window) } else { alert.runModal() }
        }
    }

    #if DEBUG
    /// 編集用のスクリプトの場所で JavaScript を動かす（自動操作での確認用）
    func debugEditorEvaluate(_ script: String, completion: @escaping (String) -> Void) {
        webView.evaluateJavaScript(script, in: nil, in: MarkdownEditor.world) { result in
            MainActor.assumeIsolated {
                switch result {
                case .success(let value): completion(String(describing: value))
                case .failure(let error): completion("error: \(error)")
                }
            }
        }
    }
    #endif
}

/// スクリプトからの知らせを受けるもの（WKUserContentController が強く持つので、コントローラーは弱く持つ）
private final class EditorMessageProxy: NSObject, WKScriptMessageHandler {
    weak var controller: FilePreviewController?

    init(_ controller: FilePreviewController) {
        self.controller = controller
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            controller?.handleEditorMessage(message.body)
        }
    }
}
