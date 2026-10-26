import AppKit

/// Markdown のプレビュー（.md を選ぶと一覧の右に整形して表示する）とテーマの反映。
extension FileBrowserViewController: NSSplitViewDelegate {
    func configureMarkdownPreview() {
        markdownPreview.onClose = { [weak self] in
            Preferences.markdownPreview = false
            self?.hideMarkdownPreview()
        }
        markdownPreview.onOpenInEditor = { url in EditorLauncher.open([url]) }
        markdownPreview.onOpenMarkdown = { [weak self] url in
            // プレビューの中のリンクから別の Markdown を開いたら、一覧もそのファイルの場所へ移る
            self?.navigate(to: url.deletingLastPathComponent(), selecting: url)
        }
    }

    var isMarkdownPreviewVisible: Bool { !markdownPreview.view.isHidden }

    /// 選択が1つの Markdown ならプレビューを出し、それ以外なら閉じる
    func updateMarkdownPreview() {
        let nodes = selectedNodes
        guard Preferences.markdownPreview, nodes.count == 1, let node = nodes.first,
              !node.entry.isFolder, MarkdownPreviewController.isMarkdown(node.url) else {
            if isMarkdownPreviewVisible { hideMarkdownPreview() }
            return
        }
        showMarkdownPreview(node.url)
    }

    func showMarkdownPreview(_ url: URL) {
        markdownPreview.show(url)
        guard !isMarkdownPreviewVisible else { return }
        markdownPreview.view.isHidden = false
        contentSplit.adjustSubviews()
        let width = contentSplit.bounds.width
        if width > 0 {
            contentSplit.setPosition(width * (1 - Preferences.markdownPreviewFraction), ofDividerAt: 0)
        }
    }

    func hideMarkdownPreview() {
        markdownPreview.stop()
        markdownPreview.view.isHidden = true
        contentSplit.adjustSubviews()
    }

    /// ⌥⌘P: Markdown のプレビューを使うかどうか
    @objc func toggleMarkdownPreview(_ sender: Any?) {
        Preferences.markdownPreview.toggle()
        NotificationCenter.default.post(name: .macornDisplayPreferencesChanged, object: nil)
    }

    @objc func themeDidChange(_ notification: Notification) {
        outlineView.enumerateAvailableRowViews { rowView, _ in rowView.needsDisplay = true }
        reloadVisibleRows()
        if isMarkdownPreviewVisible { markdownPreview.reload(keepingScroll: true) }
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
        guard isMarkdownPreviewVisible, contentSplit.bounds.width > 0 else { return }
        let fraction = markdownPreview.view.frame.width / contentSplit.bounds.width
        if fraction > 0.1, fraction < 0.9 { Preferences.markdownPreviewFraction = fraction }
    }
}
