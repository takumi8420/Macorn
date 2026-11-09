import AppKit

/// 絞り込み（要件 S-04）、Vim 風のキー操作（要件 K-02）、フォルダサイズ（要件 V-09）。
extension FileBrowserViewController {
    // MARK: - 絞り込み

    @objc func beginFilter(_ sender: Any?) {
        onActivate?()
        guard let filterBar = filterBarHeight?.firstItem as? NSView else { return }
        state.isFiltering = true
        updateFilterBarVisibility()
        // すでに開いているときは入力欄にフォーカスを戻す
        if let field = filterBar.firstTextField() {
            view.window?.makeFirstResponder(field)
        }
    }

    /// 絞り込みの欄を出すか。設定で「いつも出す」なら、使っていないときも出しておく
    func updateFilterBarVisibility() {
        guard let filterBar = filterBarHeight?.firstItem as? NSView else { return }
        state.isFilterBarAlwaysShown = Preferences.alwaysShowFilterBar
        let shows = state.isFilterBarAlwaysShown || state.isFiltering
        filterBar.isHidden = !shows
        filterBarHeight?.constant = shows ? 28 : 0
    }

    func setFilter(_ text: String) {
        state.filterText = text
        // いつも出している欄を直接クリックして打ったときも、絞り込み中として扱う（別のフォルダへ移ったら解く）
        if !text.isEmpty { state.isFiltering = true }
        applyFilter()
    }

    /// 表示中のフォルダの項目を、名前に入力した文字を含むものだけにする（大文字・小文字は区別しない）。
    /// 「サブフォルダも」がオンなら、サブフォルダの中まで探した結果を出す
    func applyFilter() {
        let text = state.filterText
        guard !text.isEmpty, state.filterIncludesSubfolders, canSearchSubfolders else {
            cancelSubfolderSearch()
            state.isShowingSubfolderResults = false
            state.isSubfolderSearchTruncated = false
            showFilterResults(text.isEmpty ? nil : (root.children ?? []).filter {
                SubfolderSearch.matches($0.entry.name, query: text)
            }, keepSelection: false)
            return
        }
        // 探し終わるまでは、直下の一致だけを先に出しておく（全部の項目が出たままにしない）
        if !state.isShowingSubfolderResults {
            showFilterResults((root.children ?? []).filter { SubfolderSearch.matches($0.entry.name, query: text) }, keepSelection: false)
        }
        searchSubfolders(for: text, keepSelection: false)
    }

    /// サブフォルダも探せるか（タグの一覧は、いろいろな場所の項目の集まりなので対象外）
    var canSearchSubfolders: Bool { !isTagView && root.url.isFileURL }

    /// 「サブフォルダも」を切り替える。選んだ方は次からも使う
    func setFilterIncludesSubfolders(_ on: Bool) {
        guard state.filterIncludesSubfolders != on else { return }
        state.filterIncludesSubfolders = on
        Preferences.filterIncludesSubfolders = on
        applyFilter()
    }

    @objc func toggleFilterSubfolders(_ sender: Any?) {
        if !state.isFiltering { beginFilter(sender) }
        setFilterIncludesSubfolders(!state.filterIncludesSubfolders)
    }

    /// サブフォルダの中まで探す。打つたびに走らないよう、少し待ってから探し、前の検索はやめる
    func searchSubfolders(for text: String, keepSelection: Bool) {
        subfolderSearchTask?.cancel()
        subfolderRefreshPending = false
        let url = root.url
        let includeHidden = Preferences.showHiddenFiles
        // 変更による探し直しは、前回かかった時間の倍（0.3〜30 秒）待つ。ホームのように変更が多くて大きいフォルダで、
        // ずっと探し続けないように
        let delay = keepSelection ? min(max(0.3, lastSubfolderSearchDuration * 2), 30) : 0.15
        subfolderSearchTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.state.isSearchingSubfolders = true // 待っている間は「探しています」を出さない
            let started = Date()
            let result = await SubfolderSearch.searchInBackground(in: url, query: text, includeHidden: includeHidden)
            guard !Task.isCancelled, self.state.filterText == text, self.root.url == url else { return }
            self.lastSubfolderSearchDuration = Date().timeIntervalSince(started)
            self.state.isSearchingSubfolders = false
            self.state.isSubfolderSearchTruncated = result.isTruncated
            self.state.isShowingSubfolderResults = true
            let nodes = self.root.makeChildren(result.entries, sort: Preferences.sort, reusing: self.filteredRootChildren ?? [])
            self.showFilterResults(nodes, keepSelection: keepSelection)
            self.subfolderSearchTask = nil
            if self.subfolderRefreshPending { self.refreshSubfolderResults() }
        }
    }

    func cancelSubfolderSearch() {
        subfolderSearchTask?.cancel()
        subfolderSearchTask = nil
        subfolderRefreshPending = false
        state.isSearchingSubfolders = false
    }

    /// サブフォルダまで探した結果を出しているとき、フォルダの中身が変わったら探し直す（選択はそのまま）。
    /// `changedPaths` を渡すと、探さない場所の中の変更だけなら探し直さない。
    /// 探している最中なら、やめずに終わってからもう1回探す（大きいフォルダで、変更のたびにやめて終わらなくならないように）
    func refreshSubfolderResults(changedPaths: [String]? = nil) {
        guard state.isShowingSubfolderResults, !state.filterText.isEmpty else { return }
        if let changedPaths {
            let includeHidden = Preferences.showHiddenFiles
            let relevant = changedPaths.contains { path in
                SubfolderSearch.isRelevantChange(path, root: root.url, includeHidden: includeHidden)
                    || SubfolderSearch.isRelevantChange(path, root: URL(fileURLWithPath: Self.realPath(root.path)), includeHidden: includeHidden)
            }
            guard relevant else { return }
        }
        if subfolderSearchTask != nil {
            subfolderRefreshPending = true
            return
        }
        searchSubfolders(for: state.filterText, keepSelection: true)
    }

    /// 絞り込んだ項目を一覧に出す。nil なら絞り込まずに全部出す
    private func showFilterResults(_ nodes: [FileNode]?, keepSelection: Bool) {
        let previous = filteredRootChildren
        filteredRootChildren = nodes
        state.visibleCount = nodes?.count ?? state.itemCount
        guard previous?.map(ObjectIdentifier.init) != nodes?.map(ObjectIdentifier.init) else {
            // 同じ項目のままでも、中身（更新日など）は変わっているかもしれない
            if keepSelection { reloadVisibleRows() }
            return
        }
        let selected = selectedURLs
        outlineView.reloadItem(nil, reloadChildren: true)
        if keepSelection {
            if !selected.isEmpty { select(selected, scroll: false) }
        } else if nodes?.isEmpty == false, outlineView.numberOfRows > 0 {
            // 絞り込んだら先頭を選んでおき、Enter・↓ ですぐ操作できるようにする
            outlineView.selectRowIndexes([0], byExtendingSelection: false)
            outlineView.scrollRowToVisible(0)
        }
    }

    /// clear が false なら絞り込んだまま一覧へ戻る。
    func endFilter(clear: Bool, focus: Bool = true) {
        if clear {
            let selected = selectedURLs
            cancelSubfolderSearch()
            state.filterText = ""
            state.isFiltering = false
            state.isShowingSubfolderResults = false
            state.isSubfolderSearchTruncated = false
            filteredRootChildren = nil
            state.visibleCount = state.itemCount
            updateFilterBarVisibility()
            outlineView.reloadItem(nil, reloadChildren: true)
            select(selected)
        } else if state.filterText.isEmpty {
            endFilter(clear: true, focus: focus)
            return
        }
        if focus { focusList() }
    }

    // MARK: - 一覧でのキー入力

    /// 一覧でのキー入力を先に見る。処理したら true。
    func handleListKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control])
        guard modifiers.isEmpty, let characters = event.charactersIgnoringModifiers else {
            pendingG = false
            return false
        }

        if event.keyCode == 53, state.isFiltering { // Esc で絞り込みをやめる
            endFilter(clear: true)
            return true
        }
        if characters == "/" {
            beginFilter(nil)
            return true
        }
        guard Preferences.vimKeyBindings else { return false }

        let wasG = pendingG
        pendingG = false
        switch characters {
        case "j": moveSelection(by: 1)
        case "k": moveSelection(by: -1)
        case "h": collapseOrGoUp()
        case "l": expandOrOpen()
        case "G": selectRow(outlineView.numberOfRows - 1)
        case "g":
            if wasG {
                selectRow(0)
            } else {
                pendingG = true
            }
        default:
            return false
        }
        return true
    }

    private func moveSelection(by delta: Int) {
        let current = outlineView.selectedRowIndexes.last ?? (delta > 0 ? -1 : outlineView.numberOfRows)
        selectRow(current + delta)
    }

    private func selectRow(_ row: Int) {
        guard outlineView.numberOfRows > 0 else { return }
        let row = min(max(row, 0), outlineView.numberOfRows - 1)
        outlineView.selectRowIndexes([row], byExtendingSelection: false)
        outlineView.scrollRowToVisible(row)
    }

    /// h: 展開中なら閉じる。中の項目なら親の行へ。いちばん上の階層なら親フォルダへ移動
    private func collapseOrGoUp() {
        guard let node = selectedNodes.first else {
            goToParent()
            return
        }
        if outlineView.isItemExpanded(node) {
            outlineView.collapseItem(node)
        } else if let parent = node.parent, parent !== root {
            selectRow(outlineView.row(forItem: parent))
        } else {
            goToParent()
        }
    }

    /// l: フォルダなら中へ移動、ファイルなら開く
    private func expandOrOpen() {
        openSelection()
    }

    // MARK: - フォルダのサイズ

    func requestFolderSizes(in node: FileNode) {
        guard Preferences.calculateFolderSizes else { return }
        let folders = (node.children ?? []).filter { ($0.entry.isFolder || $0.entry.isPackage) && $0.entry.size == nil }
        guard !folders.isEmpty else { return }
        FolderSizeService.shared.request(folders.map(\.url), owner: self) { [weak self] url, size in
            self?.folderSizeArrived(url, size: size)
        }
    }

    private func folderSizeArrived(_ url: URL, size: Int64) {
        let path = url.standardizedFileURL.path
        for folder in root.loadedFolders() {
            guard let child = folder.children?.first(where: { $0.path == path }) else { continue }
            child.setFolderSize(size)
            let row = outlineView.row(forItem: child)
            let column = outlineView.column(withIdentifier: FileColumn.size.identifier)
            if row >= 0, column >= 0 {
                outlineView.reloadData(forRowIndexes: [row], columnIndexes: [column])
            }
        }
        // サイズ順に並べているときは、まとめて並べ直す
        if Preferences.sort.key == .size, !resortForSizesScheduled {
            resortForSizesScheduled = true
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                resortForSizesScheduled = false
                let selected = selectedURLs
                root.resort(Preferences.sort)
                if state.isFiltering { filteredRootChildren = nil; applyFilter() }
                outlineView.reloadItem(nil, reloadChildren: true)
                select(selected, scroll: false)
            }
        }
    }
}

private extension NSView {
    func firstTextField() -> NSTextField? {
        for subview in subviews {
            if let field = subview as? NSTextField, field.isEditable { return field }
            if let found = subview.firstTextField() { return found }
        }
        return nil
    }
}
