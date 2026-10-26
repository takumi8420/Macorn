import AppKit

/// ターミナル・エディタ連携とパスのコピー（M5）、Git の状態表示（要件 6.3）。
extension FileBrowserViewController {
    /// 操作の対象: 選択中の項目。なければ表示中のフォルダ。
    private var targetURLs: [URL] {
        let selected = selectedURLs
        // タグの一覧には「表示中のフォルダ」がないので、選択中の項目だけを対象にする
        if selected.isEmpty, isTagView { return [] }
        return selected.isEmpty ? [state.currentURL] : selected
    }

    /// ターミナルで開くフォルダ: 選択中のフォルダが1つならそれ、そうでなければ表示中のフォルダ。
    private var terminalFolder: URL {
        let folders = selectedNodes.filter(\.entry.isFolder)
        return folders.count == 1 && selectedNodes.count == 1 ? folders[0].url : state.currentURL
    }

    @objc func openInTerminal(_ sender: Any?) {
        TerminalLauncher.open(terminalFolder)
    }

    @objc func openInEditor(_ sender: Any?) {
        EditorLauncher.open(targetURLs)
    }

    @objc func openRepositoryInEditor(_ sender: Any?) {
        guard let root = gitSnapshot?.root ?? GitRepository.root(containing: state.currentURL) else {
            NSSound.beep()
            return
        }
        EditorLauncher.open([root])
    }

    @objc func copyPath(_ sender: Any?) { copyPaths(.full) }
    @objc func copyTildePath(_ sender: Any?) { copyPaths(.tilde) }
    @objc func copyRelativePath(_ sender: Any?) { copyPaths(.relativeToRepository) }
    @objc func copyShellQuotedPath(_ sender: Any?) { copyPaths(.shellQuoted) }

    private func copyPaths(_ style: PathCopier.Style) {
        if !PathCopier.copy(targetURLs, style: style) { NSSound.beep() }
    }

    func validateIntegrationMenuItem(_ item: NSMenuItem) -> Bool? {
        switch item.action {
        case #selector(openInTerminal(_:)):
            return TerminalLauncher.selected != nil && terminalFolder.isFileURL
        case #selector(openInEditor(_:)):
            return EditorLauncher.selected != nil && !targetURLs.isEmpty
        case #selector(openRepositoryInEditor(_:)), #selector(copyRelativePath(_:)):
            return gitSnapshot != nil
        case #selector(copyPath(_:)), #selector(copyTildePath(_:)), #selector(copyShellQuotedPath(_:)):
            // 入力欄では普通のコピーを優先するため、パスのコピーは一覧のときだけ
            return !(view.window?.firstResponder is NSText) && !targetURLs.isEmpty
        default:
            return nil
        }
    }

    // MARK: - Git の状態

    /// 表示中のフォルダが Git リポジトリの中なら、状態を読み直す。続けて呼ばれたらまとめる。
    func refreshGitStatus() {
        if gitRefreshInProgress {
            gitRefreshPending = true
            return
        }
        gitRefreshInProgress = true
        let folder = state.currentURL
        Task {
            let snapshot = await Task.detached(priority: .utility) { () -> GitSnapshot? in
                guard let root = GitRepository.root(containing: folder) else { return nil }
                return GitRepository.snapshot(root: root)
            }.value
            gitRefreshInProgress = false
            if folder.path == state.currentURL.path, snapshot != gitSnapshot {
                gitSnapshot = snapshot
                state.gitBranch = snapshot?.branch
                state.gitChangeCount = snapshot?.changeCount ?? 0
                reloadVisibleRows()
            }
            if gitRefreshPending {
                gitRefreshPending = false
                try? await Task.sleep(for: .milliseconds(500))
                refreshGitStatus()
            }
        }
    }

    func reloadVisibleRows() {
        guard outlineView.numberOfRows > 0 else { return }
        outlineView.reloadData(
            forRowIndexes: IndexSet(integersIn: 0..<outlineView.numberOfRows),
            columnIndexes: IndexSet(integersIn: 0..<outlineView.numberOfColumns)
        )
    }
}
