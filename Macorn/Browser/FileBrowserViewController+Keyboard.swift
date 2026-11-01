import AppKit

/// 絞り込み（要件 S-04）、Vim 風のキー操作（要件 K-02）、フォルダサイズ（要件 V-09）。
extension FileBrowserViewController {
    // MARK: - 絞り込み

    @objc func beginFilter(_ sender: Any?) {
        onActivate?()
        guard let filterBar = filterBarHeight?.firstItem as? NSView else { return }
        state.isFiltering = true
        filterBar.isHidden = false
        filterBarHeight?.constant = 28
        // すでに開いているときは入力欄にフォーカスを戻す
        if let field = filterBar.firstTextField() {
            view.window?.makeFirstResponder(field)
        }
    }

    func setFilter(_ text: String) {
        state.filterText = text
        applyFilter()
    }

    /// 表示中のフォルダの項目を、名前に入力した文字を含むものだけにする（大文字・小文字は区別しない）
    func applyFilter() {
        let text = state.filterText
        let previous = filteredRootChildren
        if text.isEmpty {
            filteredRootChildren = nil
        } else {
            filteredRootChildren = (root.children ?? []).filter {
                $0.entry.name.range(of: text, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil
            }
        }
        state.visibleCount = filteredRootChildren?.count ?? state.itemCount
        guard previous?.map(ObjectIdentifier.init) != filteredRootChildren?.map(ObjectIdentifier.init) else { return }
        outlineView.reloadItem(nil, reloadChildren: true)
        // 絞り込んだら先頭を選んでおき、Enter・↓ ですぐ操作できるようにする
        if !text.isEmpty, outlineView.numberOfRows > 0 {
            outlineView.selectRowIndexes([0], byExtendingSelection: false)
            outlineView.scrollRowToVisible(0)
        }
    }

    /// clear が false なら絞り込んだまま一覧へ戻る。
    func endFilter(clear: Bool, focus: Bool = true) {
        if clear {
            let selected = selectedURLs
            state.filterText = ""
            state.isFiltering = false
            filteredRootChildren = nil
            state.visibleCount = state.itemCount
            filterBarHeight?.constant = 0
            (filterBarHeight?.firstItem as? NSView)?.isHidden = true
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
