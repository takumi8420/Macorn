import AppKit

/// ファイルのプレビュー（.md・.html・画像・PDF・動画などを選ぶと一覧の右に表示する）とテーマの反映。
extension FileBrowserViewController: NSSplitViewDelegate {
    func configureFilePreview() {
        filePreview.onClose = { [weak self] in
            Preferences.filePreview = false
            self?.hideFilePreview()
        }
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
        guard Preferences.filePreview || pinned, nodes.count == 1, let node = nodes.first,
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
        NotificationCenter.default.post(name: .macornDisplayPreferencesChanged, object: nil)
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

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        max(proposedMinimumPosition, 220)
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        min(proposedMaximumPosition, splitView.bounds.width - 240)
    }

    /// プレビューの幅を覚えておき、次に開いたときも同じ幅にする
    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard isFilePreviewVisible, contentSplit.bounds.width > 0 else { return }
        let fraction = filePreview.view.frame.width / contentSplit.bounds.width
        if fraction > 0.1, fraction < 0.9 { Preferences.filePreviewFraction = fraction }
    }
}
