import AppKit

/// ファイルのプレビュー（.md・.html・画像・PDF・動画などを選ぶと一覧の右に表示する）とテーマの反映。
extension FileBrowserViewController: NSSplitViewDelegate {
    func configureFilePreview() {
        // 「×」は今のファイルのプレビューだけを閉じる（設定は変えない。別のファイルを選べばまた出る）。
        // 以前は設定ごとオフにしていたため、一度閉じるとダブルクリックしないと出なくなっていた
        filePreview.onClose = { [weak self] in
            guard let self else { return }
            dismissedPreviewURL = filePreview.fileURL
            pinnedPreviewURL = nil
            hideFilePreview()
        }
        filePreview.onToggleMaximize = { [weak self] in self?.togglePreviewMaximized(nil) }
        filePreview.onCollapseList = { [weak self] in self?.setListCollapsed(true) }
        filePreview.onOpenInEditor = { url in EditorLauncher.open([url]) }
        filePreview.onOpenPreviewable = { [weak self] url in
            // プレビューの中のリンクから別の Markdown・HTML を開いたら、一覧もそのファイルの場所へ移る
            self?.navigate(to: url.deletingLastPathComponent(), selecting: url)
        }
    }

    var isFilePreviewVisible: Bool { !filePreview.view.isHidden }

    /// 選択が1つのプレビューできるファイル（Markdown・HTML・画像・PDF・動画など）ならプレビューを出し、それ以外なら閉じる
    func updateFilePreview() {
        let nodes = selectedNodes
        let pinned = nodes.count == 1 && pinnedPreviewURL.map { Self.comparablePath($0) == Self.comparablePath(nodes[0].url) } == true
        if !pinned && !nodes.isEmpty { pinnedPreviewURL = nil }
        // 「×」で閉じたファイルを選んでいる間は出さない。ほかを選んだら忘れる
        let dismissed = nodes.count == 1 && dismissedPreviewURL.map { Self.comparablePath($0) == Self.comparablePath(nodes[0].url) } == true
        if !dismissed { dismissedPreviewURL = nil }
        guard (Preferences.filePreview && !dismissed) || pinned, nodes.count == 1, let node = nodes.first,
              !node.entry.isFolder, FilePreviewController.kind(for: node.url) != nil else {
            if isFilePreviewVisible { hideFilePreview() }
            return
        }
        showFilePreview(node.url)
    }

    func showFilePreview(_ url: URL) {
        filePreview.show(url)
        guard !isFilePreviewVisible else { return }
        if filePreview.view.superview == nil { contentSplit.addArrangedSubview(filePreview.view) }
        filePreview.view.isHidden = false
        contentSplit.adjustSubviews()
        let width = contentSplit.bounds.width
        if width > 0 {
            contentSplit.setPosition(width * (1 - Preferences.filePreviewFraction), ofDividerAt: 0)
        }
    }

    func hideFilePreview() {
        // 最大化・一覧を畳んだまま閉じたら、元の並びに戻す
        if isPreviewMaximized { setPreviewMaximized(false) }
        if isListCollapsed { setListCollapsed(false) }
        filePreview.stop()
        filePreview.view.isHidden = true
        // 隠すだけだと境目の線が描かれたまま残るので、分割から外す（次に出すときに戻す）
        contentSplit.removeArrangedSubview(filePreview.view)
        filePreview.view.removeFromSuperview()
        contentSplit.adjustSubviews()
    }

    /// ⌥⌘P: プレビュー（Markdown・HTML）を使うかどうか
    @objc func toggleFilePreview(_ sender: Any?) {
        Preferences.filePreview.toggle()
        dismissedPreviewURL = nil
        NotificationCenter.default.post(name: .macornDisplayPreferencesChanged, object: nil)
    }

    // MARK: - プレビューの最大化と、一覧を畳む

    /// 一覧を畳んでいる（境目を左端へ寄せたか、最大化した）
    var isListCollapsed: Bool { listContainer.isHidden }

    /// ⇧⌘↩・プレビューのヘッダーのボタン: プレビューを最大化する／元に戻す。
    /// 最大化すると、この画面の一覧・サイドバー・ほかの画面を畳む（ターミナルはそのまま）
    @objc func togglePreviewMaximized(_ sender: Any?) {
        if isPreviewMaximized || isListCollapsed {
            setPreviewMaximized(false)
            setListCollapsed(false)
        } else {
            guard isFilePreviewVisible else { NSSound.beep(); return }
            setPreviewMaximized(true)
        }
    }

    func setPreviewMaximized(_ maximized: Bool) {
        guard maximized != isPreviewMaximized else { return }
        isPreviewMaximized = maximized
        setListCollapsed(maximized)
        onPreviewMaximizeChanged?(maximized)
    }

    /// 一覧を畳む・広げる。畳んでいる間のキー操作はプレビューに届く（↑↓ でスクロール）。広げたら一覧に戻す
    func setListCollapsed(_ collapsed: Bool) {
        guard collapsed != isListCollapsed else { return }
        guard !collapsed || isFilePreviewVisible else { return }
        listContainer.isHidden = collapsed
        contentSplit.adjustSubviews()
        if !collapsed {
            let width = contentSplit.bounds.width
            if width > 0 { contentSplit.setPosition(width * (1 - Preferences.filePreviewFraction), ofDividerAt: 0) }
        }
        if !collapsed { view.window?.makeFirstResponder(outlineView) }
        filePreview.setMaximized(collapsed)
    }

    // MARK: - プレビューの拡大・縮小（⌘+ ⌘− ⌘0）

    @objc func zoomInPreview(_ sender: Any?) { filePreview.zoomIn(sender) }
    @objc func zoomOutPreview(_ sender: Any?) { filePreview.zoomOut(sender) }
    @objc func resetPreviewZoom(_ sender: Any?) { filePreview.resetZoom(sender) }

    var canZoomPreview: Bool { isFilePreviewVisible && filePreview.canZoom }

    @objc func themeDidChange(_ notification: Notification) {
        outlineView.enumerateAvailableRowViews { rowView, _ in rowView.needsDisplay = true }
        reloadVisibleRows()
        if isFilePreviewVisible { filePreview.reload(keepingScroll: true) }
    }

    // MARK: - 一覧とプレビューの境目

    /// 一覧とプレビューの区切り線を掴みやすくする。一覧の右の余白（行が終わってから線までの帯）も掴めるようにする
    func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect, forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
        DividerGrab.rect(proposedEffectiveRect, vertical: splitView.isVertical, leading: Self.listInset + 2)
    }

    /// 境目を左端の近くまで寄せると、一覧を畳む（境目を右へ引けば戻る）
    /// 画面が狭いときに AppKit が勝手に畳まないよう、境目を操作している間だけ畳めるようにする
    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        subview === listContainer && contentSplit.isTrackingDivider
    }

    /// 境目をダブルクリックすると、一覧を畳む・広げる
    func splitView(_ splitView: NSSplitView, shouldCollapseSubview subview: NSView, forDoubleClickOnDividerAt dividerIndex: Int) -> Bool {
        subview === listContainer
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        max(proposedMinimumPosition, 220)
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        min(proposedMaximumPosition, splitView.bounds.width - 240)
    }

    /// プレビューの幅を覚えておき、次に開いたときも同じ幅にする
    func splitViewDidResizeSubviews(_ notification: Notification) {
        // ドラッグで畳んだ・広げたときも、ボタンの見た目を合わせる
        if filePreview.isMaximizedAppearance != isListCollapsed { filePreview.setMaximized(isListCollapsed) }
        if !isListCollapsed, isPreviewMaximized { setPreviewMaximized(false) }
        guard isFilePreviewVisible, !isListCollapsed, contentSplit.bounds.width > 0 else { return }
        let fraction = filePreview.view.frame.width / contentSplit.bounds.width
        if fraction > 0.1, fraction < 0.9 { Preferences.filePreviewFraction = fraction }
    }
}

/// 一覧とプレビューを分ける線。境目をドラッグ・ダブルクリックしている間かどうかを分かるようにする
final class PreviewSplitView: NSSplitView {
    private(set) var isTrackingDivider = false

    override func mouseDown(with event: NSEvent) {
        // NSSplitView は mouseDown の中でドラッグを追いかけるので、その間だけ立てておく
        isTrackingDivider = true
        defer { isTrackingDivider = false }
        super.mouseDown(with: event)
    }
}
