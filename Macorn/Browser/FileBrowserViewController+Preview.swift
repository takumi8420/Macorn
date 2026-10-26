import AppKit

/// ファイルのプレビュー（.md・.html を選ぶと一覧の右に表示する）とテーマの反映。
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

    /// 選択が1つのプレビューできるファイル（Markdown・HTML）ならプレビューを出し、それ以外なら閉じる
    func updateFilePreview() {
        let nodes = selectedNodes
        guard Preferences.filePreview, nodes.count == 1, let node = nodes.first,
              !node.entry.isFolder, FilePreviewController.kind(for: node.url) != nil else {
            if isFilePreviewVisible { hideFilePreview() }
            return
        }
        showFilePreview(node.url)
    }

    func showFilePreview(_ url: URL) {
        filePreview.show(url)
        guard !isFilePreviewVisible else { return }
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
        contentSplit.adjustSubviews()
    }

    /// ⌥⌘P: プレビュー（Markdown・HTML）を使うかどうか
    @objc func toggleFilePreview(_ sender: Any?) {
        Preferences.filePreview.toggle()
        NotificationCenter.default.post(name: .macornDisplayPreferencesChanged, object: nil)
    }

    @objc func themeDidChange(_ notification: Notification) {
        outlineView.enumerateAvailableRowViews { rowView, _ in rowView.needsDisplay = true }
        reloadVisibleRows()
        if isFilePreviewVisible { filePreview.reload(keepingScroll: true) }
    }

    // MARK: - 一覧とプレビューの境目

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
