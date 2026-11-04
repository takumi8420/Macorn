import AppKit
import Quartz

/// ファイル操作（M2）: 新規作成・名前の変更・コピー/カット/ペースト・ゴミ箱・削除・
/// ドラッグ＆ドロップ・クイックルック。
extension FileBrowserViewController {
    var selectedURLs: [URL] { selectedNodes.map(\.url) }

    private var operations: FileOperationManager { .shared }

    /// 文字の入力中（パス入力・名前の変更）は、ファイル操作のショートカットを効かせない。
    private var isEditingText: Bool {
        view.window?.firstResponder is NSText
    }

    // MARK: - 操作のあとの再読み込みと選択

    /// 変更のあったフォルダを読み直し、新しくできた項目を選択する。
    func refreshAfterChange(selecting urls: [URL], rename: URL? = nil) {
        pendingSelection = urls
        pendingRename = rename
        pendingSelectionDeadline = Date().addingTimeInterval(3)
        let parents = Set(urls.map { Self.comparablePath($0.deletingLastPathComponent()) })
        var reloaded = false
        for folder in root.loadedFolders() where parents.contains(Self.comparablePath(folder.url)) {
            load(folder)
            reloaded = true
        }
        if !reloaded { load(root) }
    }

    /// 読み込みが終わるたびに呼ばれる。待っていた項目が一覧に出たら選択する。
    func applyPendingSelection() {
        guard !pendingSelection.isEmpty else { return }
        guard Date() < pendingSelectionDeadline else {
            pendingSelection = []
            pendingRename = nil
            return
        }
        let wanted = Set(pendingSelection.map(Self.comparablePath))
        var rows = IndexSet()
        var renameNode: FileNode?
        for row in 0..<outlineView.numberOfRows {
            guard let node = outlineView.item(atRow: row) as? FileNode else { continue }
            let path = Self.comparablePath(node.url)
            guard wanted.contains(path) else { continue }
            rows.insert(row)
            if let pendingRename, Self.comparablePath(pendingRename) == path { renameNode = node }
        }
        guard !rows.isEmpty else { return }
        outlineView.selectRowIndexes(rows, byExtendingSelection: false)
        outlineView.scrollRowToVisible(rows.first!)
        if rows.count == wanted.count { pendingSelection = [] }
        if let renameNode {
            pendingRename = nil
            beginRename(renameNode)
        }
    }

    // MARK: - コピー・カット・ペースト

    @objc func copy(_ sender: Any?) {
        FileClipboard.write(selectedURLs, cut: false)
    }

    @objc func cut(_ sender: Any?) {
        FileClipboard.write(selectedURLs, cut: true)
    }

    @objc func paste(_ sender: Any?) {
        pasteFiles(move: FileClipboard.isCut)
    }

    /// ⌥⌘V: コピーした項目をここへ移動する（Finder と同じ）。
    @objc func moveHere(_ sender: Any?) {
        pasteFiles(move: true)
    }

    private func pasteFiles(move: Bool) {
        let urls = FileClipboard.fileURLs
        guard !urls.isEmpty else { return }
        let wasCut = FileClipboard.isCut
        let destination = state.currentURL
        Task {
            let results = await operations.transfer(urls, to: destination, mode: move ? .move : .copy, window: view.window)
            if move, wasCut, !results.isEmpty { FileClipboard.finishCut() }
            refreshAfterChange(selecting: results)
        }
    }

    /// ⌘D: 同じフォルダに「〜 のコピー」を作る。
    @objc func duplicate(_ sender: Any?) {
        let groups = Dictionary(grouping: selectedURLs) { $0.deletingLastPathComponent() }
        Task {
            var results: [URL] = []
            for (folder, urls) in groups {
                results += await operations.transfer(urls, to: folder, mode: .copy, window: view.window)
            }
            refreshAfterChange(selecting: results)
        }
    }

    // MARK: - 新規作成

    @objc func newFolder(_ sender: Any?) {
        let folder = state.currentURL
        Task {
            guard let url = await operations.createFolder(in: folder, window: view.window) else { return }
            refreshAfterChange(selecting: [url], rename: url)
        }
    }

    @objc func newFile(_ sender: Any?) {
        let folder = state.currentURL
        Task {
            guard let url = await operations.createFile(in: folder, window: view.window) else { return }
            refreshAfterChange(selecting: [url], rename: url)
        }
    }

    // MARK: - ゴミ箱・削除

    @objc func moveToTrash(_ sender: Any?) {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        Task { await operations.moveToTrash(urls, window: view.window) }
    }

    @objc func deleteImmediately(_ sender: Any?) {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        Task { await operations.deletePermanently(urls, window: view.window) }
    }

    // MARK: - 名前の変更

    /// Return: 1つなら一覧のその場で、複数なら一括で名前を変更する
    @objc func renameSelection(_ sender: Any?) {
        if selectedNodes.count > 1 {
            bulkRename(sender)
            return
        }
        guard let node = selectedNodes.first else { return }
        beginRename(node)
    }

    func beginRename(_ node: FileNode) {
        let row = outlineView.row(forItem: node)
        let column = outlineView.column(withIdentifier: FileColumn.name.identifier)
        guard row >= 0, column >= 0 else { return }
        outlineView.selectRowIndexes([row], byExtendingSelection: false)
        outlineView.scrollRowToVisible(row)
        guard let cell = outlineView.view(atColumn: column, row: row, makeIfNecessary: true) as? FileCellView,
              let field = cell.textField else { return }

        renamingNode = node
        renameCancelled = false
        cell.beginEditing(delegate: self)
        view.window?.makeFirstResponder(field)
        // 拡張子の前までを選択した状態で始める
        field.currentEditor()?.selectedRange = FileNaming.editableRange(for: node.entry.name, isDirectory: node.entry.isFolder)
    }

    private func finishRename(field: NSTextField) {
        guard let node = renamingNode else { return }
        renamingNode = nil
        let newName = field.stringValue
        let cancelled = renameCancelled
        renameCancelled = false
        (field.superview as? FileCellView)?.endEditing()

        guard !cancelled, newName != node.entry.name else {
            field.stringValue = node.entry.name
            flushDeferredRefresh()
            return
        }
        let oldURL = node.url
        Task {
            if let newURL = await operations.rename(oldURL, to: newName, window: view.window) {
                refreshAfterChange(selecting: [newURL])
            } else {
                field.stringValue = node.entry.name
            }
            flushDeferredRefresh()
        }
    }

    /// 名前の変更中・ドラッグ中に後回しにした再読み込みを行う。
    func flushDeferredRefresh() {
        guard needsRefreshAfterRename, renamingNode == nil, !isDragging else { return }
        needsRefreshAfterRename = false
        for folder in root.loadedFolders() where folder === root || outlineView.isItemExpanded(folder) {
            load(folder)
        }
    }

    // MARK: - クイックルック（要件 S-03）

    @objc func toggleQuickLook(_ sender: Any?) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists(), panel.isVisible {
            panel.orderOut(nil)
            return
        }
        guard !selectedURLs.isEmpty else { return }
        previewItems = selectedURLs
        if DebugFlags.isAutomating {
            panel.orderFront(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
        // 通常はパネルがレスポンダチェーンからこの画面を見つけるが、
        // ウインドウがキーでないときは見つけられないので、直接つなぐ
        if (panel.dataSource as AnyObject?) !== self {
            panel.dataSource = self
            panel.delegate = self
            panel.reloadData()
        }
    }

    func updatePreviewPanel() {
        guard QLPreviewPanel.sharedPreviewPanelExists(),
              let panel = QLPreviewPanel.shared(),
              panel.isVisible,
              (panel.dataSource as AnyObject?) === self else { return }
        previewItems = selectedURLs
        panel.reloadData()
    }

    // クイックルックのパネルはメインスレッドからしか呼ばれないが、宣言上は nonisolated になっている
    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = self
            panel.delegate = self
            previewItems = selectedURLs
            panel.reloadData()
        }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = nil
            panel.delegate = nil
        }
    }

    // MARK: - メニューの有効・無効

    func validateFileMenuItem(_ item: NSMenuItem) -> Bool? {
        switch item.action {
        case #selector(copy(_:)), #selector(cut(_:)), #selector(moveToTrash(_:)),
             #selector(deleteImmediately(_:)), #selector(duplicate(_:)):
            return !isEditingText && !selectedNodes.isEmpty
        case #selector(toggleQuickLook(_:)):
            return !isEditingText && (!selectedNodes.isEmpty || (QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible))
        case #selector(renameSelection(_:)):
            return !isEditingText && !selectedNodes.isEmpty
        case #selector(paste(_:)), #selector(moveHere(_:)):
            return !isEditingText && !isTagView && state.error == nil && FileClipboard.hasFiles
        case #selector(newFolder(_:)), #selector(newFile(_:)):
            // タグの一覧には「ここ」に当たるフォルダがない
            return !isEditingText && !isTagView && state.error == nil
        default:
            return nil
        }
    }
}

// MARK: - 名前の変更の入力欄

extension FileBrowserViewController: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard renamingNode != nil else { return false }
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)):
            renameCancelled = true
            focusList()
            return true
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
            focusList()
            return true
        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        finishRename(field: field)
    }
}

// MARK: - クイックルックのデータ

extension FileBrowserViewController: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewItems.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        previewItems[index] as NSURL
    }

    /// プレビュー表示中も矢印キーで一覧を移動できるようにする。
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown else { return false }
        outlineView.keyDown(with: event)
        return true
    }

    func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: (any QLPreviewItem)!) -> NSRect {
        guard let url = item as? URL,
              let window = view.window else { return .zero }
        let column = outlineView.column(withIdentifier: FileColumn.name.identifier)
        for row in 0..<outlineView.numberOfRows {
            guard let node = outlineView.item(atRow: row) as? FileNode, node.path == url.path,
                  let cell = outlineView.view(atColumn: column, row: row, makeIfNecessary: false) as? FileCellView,
                  let imageView = cell.imageView else { continue }
            return window.convertToScreen(imageView.convert(imageView.bounds, to: nil))
        }
        return .zero
    }
}

// MARK: - ドラッグ＆ドロップ

extension FileBrowserViewController {
    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
        (item as? FileNode)?.url as NSURL?
    }

    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItems draggedItems: [Any]) {
        draggedURLs = draggedItems.compactMap { ($0 as? FileNode)?.url }
        isDragSourceActive = true
        DragLog.note("source began \(draggedURLs.map(\.lastPathComponent))")
    }

    /// ドラッグの途中は一覧を読み直さない（行が入れ替わると、置き先やスクロールの位置がずれる）
    var isDragging: Bool {
        (isDragSourceActive && NSEvent.pressedMouseButtons & 1 != 0) || outlineView.isDragTargeted
    }

    func dragDidFinish() {
        flushDeferredRefresh()
    }

    /// ドラッグ中に後回しにした読み直しを、ドラッグが終わったら行う（終わりの知らせが届かなくても行えるよう、見張る）
    func flushWhenDragEnds() {
        guard !dragEndWatchScheduled else { return }
        dragEndWatchScheduled = true
        Task {
            while isDragging { try? await Task.sleep(for: .milliseconds(200)) }
            dragEndWatchScheduled = false
            flushDeferredRefresh()
        }
    }

    /// Dock のゴミ箱へドロップされたら、ゴミ箱へ入れる。
    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation.contains(.delete), !draggedURLs.isEmpty {
            let urls = draggedURLs
            Task { await FileOperationManager.shared.moveToTrash(urls, window: view.window) }
        }
        DragLog.note("source ended op=\(operation.rawValue)")
        draggedURLs = []
        isDragSourceActive = false
        dragDidFinish()
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        validateDrop info: any NSDraggingInfo,
        proposedItem item: Any?,
        proposedChildIndex index: Int
    ) -> NSDragOperation {
        let urls = Self.fileURLs(from: info)
        guard !urls.isEmpty else { return [] }

        // フォルダの上ならそのフォルダ、ファイルの上や行の間ならそのファイルがあるフォルダへ入れる
        var target = item as? FileNode
        if let node = target, !node.entry.isFolder { target = node.parent }
        if target === root { target = nil }
        outlineView.setDropItem(target, dropChildIndex: NSOutlineViewDropOnItemIndex)

        // タグの一覧に落としたら、そのタグを付ける（ファイルは動かさない）
        if target == nil, isTagView { return .link }

        return Self.dropOperation(for: info, urls: urls, folder: (target ?? root).url)
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: any NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        let urls = Self.fileURLs(from: info)
        let targetNode = (item as? FileNode) ?? root
        DragLog.note("accept \(urls.map(\.lastPathComponent)) → \(targetNode.url.lastPathComponent)")
        if targetNode === root, let tag = currentTag {
            TagStore.shared.assign(tag.id, to: urls)
            refreshAfterChange(selecting: urls)
            return true
        }
        let folder = targetNode.url
        let operation = Self.dropOperation(for: info, urls: urls, folder: folder)
        guard !operation.isEmpty else { return false }

        Task {
            let results = await FileOperationManager.shared.transfer(
                urls, to: folder, mode: operation == .copy ? .copy : .move, window: view.window
            )
            if targetNode === root {
                refreshAfterChange(selecting: results)
            } else {
                load(targetNode)
            }
            // 移動したときは、移動元のフォルダも読み直す（一覧に残ったままにしない）
            if operation == .move {
                let sourceFolders = Set(urls.map { Self.comparablePath($0.deletingLastPathComponent()) })
                for folder in root.loadedFolders()
                where folder !== targetNode && sourceFolders.contains(Self.comparablePath(folder.url)) {
                    load(folder)
                }
            }
        }
        return true
    }

    static func fileURLs(from info: any NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
    }

    /// Finder と同じ決め方: ⌥ でコピー、⌘ で移動。何も押さなければ同じボリュームなら移動、別ならコピー。
    static func dropOperation(for info: any NSDraggingInfo, urls: [URL], folder: URL) -> NSDragOperation {
        dropOperation(mask: info.draggingSourceOperationMask, urls: urls, folder: folder)
    }

    static func dropOperation(mask: NSDragOperation, urls: [URL], folder: URL) -> NSDragOperation {
        if urls.contains(where: { folder.path == $0.path || folder.path.hasPrefix($0.path + "/") }) {
            return []
        }
        let operation: NSDragOperation
        if mask == .copy {
            operation = .copy
        } else if mask == .generic {
            operation = .move
        } else if mask.contains(.move), urls.allSatisfy({ FileTransfer.isSameVolume($0, folder) }) {
            operation = .move
        } else if mask.contains(.copy) {
            operation = .copy
        } else if mask.contains(.generic) || mask.contains(.move) {
            operation = .move
        } else {
            return []
        }
        // 同じフォルダへの移動は意味がないので受け付けない
        if operation == .move, urls.allSatisfy({ $0.deletingLastPathComponent().path == folder.path }) {
            return []
        }
        return operation
    }
}
