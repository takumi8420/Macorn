import AppKit
import SwiftUI

protocol FileBrowserDelegate: AnyObject {
    func browser(_ browser: FileBrowserViewController, didNavigateTo url: URL)
    func browser(_ browser: FileBrowserViewController, openInNewTab url: URL)
}

/// 1つの画面（ペイン）。パスバー・ファイル一覧・ステータスバーをまとめて持つ。
/// M3 の2画面表示では、これを左右に2つ並べる。
final class FileBrowserViewController: NSViewController {
    let state: PaneState
    weak var delegate: FileBrowserDelegate?
    /// この画面がクリック・フォーカスされたとき（2画面表示で操作対象を切り替える）
    var onActivate: (() -> Void)?
    var onSwitchPane: (() -> Void)?

    private(set) var root: FileNode
    let outlineView = FileOutlineView()
    let scrollView = NSScrollView()
    private var messageHost: NSHostingView<PaneMessageView>?
    var filterBarHeight: NSLayoutConstraint?
    /// 絞り込み中の、表示中のフォルダの項目
    var filteredRootChildren: [FileNode]?
    /// Vim 風のキー操作で「g」を1回押した状態
    var pendingG = false
    var resortForSizesScheduled = false
    private let headerMenu = NSMenu()
    private let rowMenu = NSMenu()

    private var watcher: DirectoryWatcher?
    private var rootLoadToken = UUID()
    private var loadingFolders = Set<ObjectIdentifier>()
    /// 次に読み込みが終わったときに選択する項目と、名前の変更を始める項目
    var pendingSelection: [URL] = []
    var pendingRename: URL?
    /// 名前の変更中は、外部の変更による再読み込みを後回しにする（入力欄が消えないように）
    var renamingNode: FileNode?
    var renameCancelled = false
    var needsRefreshAfterRename = false
    var previewItems: [URL] = []
    var pendingSelectionDeadline = Date.distantPast
    /// ドラッグ中の項目（Dock のゴミ箱へのドロップ用）
    var draggedURLs: [URL] = []
    var gitSnapshot: GitSnapshot?
    var bulkRenameSheet: NSWindow?
    var gitRefreshInProgress = false
    var gitRefreshPending = false
    private var isApplyingSort = false
    private var lastShowHiddenFiles = Preferences.showHiddenFiles
    private var lastSort = Preferences.sort
    private var lastFolderSizes = Preferences.calculateFolderSizes
    /// 最初に表示されたときに一覧へフォーカスを移すか（2画面で後から追加した側は移さない）
    var focusesOnFirstAppear = true
    private var hasFocusedOnce = false

    init(url: URL) {
        let url = url.standardizedFileURL
        state = PaneState(url: url)
        root = FileNode(entry: DirectoryReader.entry(for: url))
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 画面の組み立て

    override func loadView() {
        let container = NSView()

        let pathBar = NSHostingView(rootView: PathBarView(state: state, actions: pathBarActions))
        pathBar.sizingOptions = []
        let statusBar = NSHostingView(rootView: StatusBarView(state: state))
        statusBar.sizingOptions = []
        let messageHost = NSHostingView(rootView: PaneMessageView(state: state, onOpenSettings: Self.openPrivacySettings))
        messageHost.sizingOptions = []
        messageHost.isHidden = true
        self.messageHost = messageHost

        configureOutlineView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let filterBar = NSHostingView(rootView: FilterBarView(
            state: state,
            onChange: { [weak self] text in self?.setFilter(text) },
            onFinish: { [weak self] clear in self?.endFilter(clear: clear) }
        ))
        filterBar.sizingOptions = []
        filterBar.clipsToBounds = true

        for subview in [pathBar, filterBar, scrollView, statusBar, messageHost] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(subview)
        }

        NSLayoutConstraint.activate([
            pathBar.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
            pathBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            pathBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            pathBar.heightAnchor.constraint(equalToConstant: 30),

            filterBar.topAnchor.constraint(equalTo: pathBar.bottomAnchor),
            filterBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            filterBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: filterBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            statusBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 24),

            messageHost.topAnchor.constraint(equalTo: scrollView.topAnchor),
            messageHost.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            messageHost.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            messageHost.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
        ])

        let height = filterBar.heightAnchor.constraint(equalToConstant: 0)
        height.isActive = true
        filterBarHeight = height
        filterBar.isHidden = true

        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(listFrameChanged(_:)),
            name: NSView.frameDidChangeNotification, object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(columnDidResize(_:)),
            name: NSTableView.columnDidResizeNotification, object: outlineView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displayPreferencesChanged(_:)),
            name: .noxyDisplayPreferencesChanged,
            object: nil
        )
        navigate(to: state.currentURL, recordHistory: false)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if !hasFocusedOnce {
            hasFocusedOnce = true
            if focusesOnFirstAppear { focusList() }
        }
    }

    private func configureOutlineView() {
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.style = .fullWidth
        outlineView.usesAlternatingRowBackgroundColors = true
        outlineView.allowsMultipleSelection = true
        outlineView.allowsEmptySelection = true
        outlineView.allowsColumnReordering = true
        outlineView.allowsColumnResizing = true
        outlineView.allowsTypeSelect = true
        // 名前の列が残りの幅をすべて使うよう、自前で合わせる（fitNameColumn）
        outlineView.columnAutoresizingStyle = .noColumnAutoresizing
        outlineView.autoresizesOutlineColumn = false
        outlineView.indentationPerLevel = 14
        outlineView.rowHeight = 22

        for column in FileColumn.allCases {
            let tableColumn = NSTableColumn(identifier: column.identifier)
            tableColumn.title = column.title
            tableColumn.width = column.defaultWidth
            tableColumn.minWidth = column.minWidth
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: column.sortKey.rawValue, ascending: true)
            tableColumn.resizingMask = .userResizingMask
            if column == .size { tableColumn.headerCell.alignment = .right }
            outlineView.addTableColumn(tableColumn)
            if column == .name { outlineView.outlineTableColumn = tableColumn }
        }

        // 列の幅・順番・表示状態はアプリ全体で保存する
        outlineView.autosaveName = "noxy.FileList"
        outlineView.autosaveTableColumns = true

        isApplyingSort = true
        outlineView.sortDescriptors = [Preferences.sort.descriptor]
        isApplyingSort = false

        headerMenu.delegate = self
        outlineView.headerView?.menu = headerMenu
        rowMenu.delegate = self
        outlineView.menu = rowMenu

        outlineView.target = self
        outlineView.doubleAction = #selector(rowDoubleClicked(_:))

        // ドラッグ＆ドロップ（要件 F-05）。外のアプリとはリンクの作成も許す
        outlineView.registerForDraggedTypes([.fileURL])
        outlineView.setDraggingSourceOperationMask([.copy, .move, .link, .generic], forLocal: false)
        outlineView.setDraggingSourceOperationMask([.copy, .move, .generic], forLocal: true)
        outlineView.draggingDestinationFeedbackStyle = .regular

        outlineView.onReturn = { [weak self] in self?.renameSelection(nil) }
        outlineView.onSpace = { [weak self] in self?.toggleQuickLook(nil) }
        outlineView.onFocus = { [weak self] in self?.onActivate?() }
        outlineView.onTab = { [weak self] in self?.onSwitchPane?() }
        outlineView.onKeyDown = { [weak self] event in self?.handleListKey(event) ?? false }
    }

    @objc private func listFrameChanged(_ notification: Notification) {
        fitNameColumn()
    }

    @objc private func columnDidResize(_ notification: Notification) {
        // 名前以外の列の幅を変えたら、名前の列で残りを埋める
        let column = notification.userInfo?["NSTableColumn"] as? NSTableColumn
        if column?.identifier != FileColumn.name.identifier { fitNameColumn() }
    }

    /// 名前の列の幅を「一覧の幅 − ほかの列の幅」にする。狭いときは最小幅で止め、横スクロールにする。
    func fitNameColumn() {
        guard let name = outlineView.tableColumn(withIdentifier: FileColumn.name.identifier) else { return }
        let visible = outlineView.tableColumns.filter { !$0.isHidden }
        let others = visible.filter { $0 !== name }.reduce(0) { $0 + $1.width }
        let spacing = outlineView.intercellSpacing.width * CGFloat(visible.count)
        let available = scrollView.contentView.bounds.width
        guard available > 0 else { return }
        let width = max(name.minWidth, floor(available - others - spacing))
        if abs(name.width - width) > 0.5 { name.width = width }
    }

    private var pathBarActions: PathBarActions {
        PathBarActions(
            navigate: { [weak self] url in
                self?.onActivate?()
                self?.navigate(to: url)
            },
            commitPath: { [weak self] text in self?.commitPath(text) ?? false },
            complete: { [weak self] text in
                guard let self else { return text }
                return PathCompletion.complete(text, relativeTo: state.currentURL)
            },
            endEditing: { [weak self] in self?.focusList() }
        )
    }

    // MARK: - 移動

    func navigate(to url: URL, selecting selection: URL? = nil, recordHistory: Bool = true) {
        let url = url.standardizedFileURL
        if recordHistory { state.history.visit(url) }

        root = FileNode(entry: DirectoryReader.entry(for: url))
        loadingFolders.removeAll()
        pendingSelection = selection.map { [$0] } ?? []
        pendingSelectionDeadline = Date().addingTimeInterval(5)
        pendingRename = nil
        renamingNode = nil
        state.itemCount = 0
        state.selectedCount = 0
        state.isEditingPath = false
        FolderSizeService.shared.cancel(owner: self)
        if state.isFiltering { endFilter(clear: true, focus: false) }
        setError(nil)
        outlineView.reloadData()

        loadRoot()
        startWatching()
        updateAvailableCapacity()
        gitSnapshot = nil
        state.gitBranch = nil
        state.gitChangeCount = 0
        refreshGitStatus()
        if recordHistory { FolderHistory.shared.visit(url) }
        delegate?.browser(self, didNavigateTo: url)
    }

    func goBack() {
        let from = state.currentURL
        guard let to = state.history.goBack() else { return }
        navigate(to: to, selecting: Self.child(from, of: to), recordHistory: false)
    }

    func goForward() {
        let from = state.currentURL
        guard let to = state.history.goForward() else { return }
        navigate(to: to, selecting: Self.child(from, of: to), recordHistory: false)
    }

    /// 親フォルダへ移動し、今までいたフォルダを選択する（Finder と同じ動き）。
    func goToParent() {
        let current = state.currentURL
        guard current.path != "/" else { return }
        navigate(to: current.deletingLastPathComponent(), selecting: current)
    }

    var canGoToParent: Bool { state.currentURL.path != "/" }

    func beginEditingPath() {
        onActivate?()
        state.isEditingPath = true
    }

    private func commitPath(_ text: String) -> Bool {
        guard let target = PathCompletion.resolve(text, relativeTo: state.currentURL) else { return false }
        if target.isDirectory {
            navigate(to: target.url)
        } else {
            navigate(to: target.url.deletingLastPathComponent(), selecting: target.url)
        }
        return true
    }

    private static func child(_ url: URL, of folder: URL) -> URL? {
        url.deletingLastPathComponent().path == folder.path ? url : nil
    }

    func focusList() {
        view.window?.makeFirstResponder(outlineView)
    }

    // MARK: - 開く

    var selectedNodes: [FileNode] {
        outlineView.selectedRowIndexes.compactMap { outlineView.item(atRow: $0) as? FileNode }
    }

    /// 選択中のフォルダ。なければ表示中のフォルダ。
    var selectedFolderURLsOrCurrent: [URL] {
        let folders = selectedNodes.filter(\.entry.isFolder).map(\.url)
        return folders.isEmpty ? [state.currentURL] : folders
    }

    func openSelection() {
        open(selectedNodes)
    }

    @objc private func rowDoubleClicked(_ sender: Any?) {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FileNode else { return }
        open([node])
    }

    private func open(_ nodes: [FileNode]) {
        guard !nodes.isEmpty else { return }
        let folders = nodes.filter(\.entry.isFolder)
        let files = nodes.filter { !$0.entry.isFolder }
        if folders.count == 1 && files.isEmpty {
            navigate(to: folders[0].url)
            return
        }
        // 複数のフォルダは、それぞれ新しいタブで開く
        for folder in folders {
            delegate?.browser(self, openInNewTab: folder.url)
        }
        for file in files {
            NSWorkspace.shared.open(file.url)
        }
    }

    // MARK: - 読み込み

    private func loadRoot() {
        let token = UUID()
        rootLoadToken = token
        let node = root
        let url = node.url
        let includeHidden = Preferences.showHiddenFiles
        state.isLoading = true
        Task {
            let result = await DirectoryReader.readInBackground(url, includeHidden: includeHidden)
            guard token == rootLoadToken else { return }
            state.isLoading = false
            apply(result, to: node)
        }
    }

    /// 展開されたフォルダや、変更のあったフォルダを読み直す。
    func load(_ node: FileNode) {
        let id = ObjectIdentifier(node)
        guard !loadingFolders.contains(id) else { return }
        loadingFolders.insert(id)
        let url = node.url
        let includeHidden = Preferences.showHiddenFiles
        Task {
            let result = await DirectoryReader.readInBackground(url, includeHidden: includeHidden)
            loadingFolders.remove(id)
            guard node.treeRoot === root else { return }
            apply(result, to: node)
        }
    }

    private func apply(_ result: Result<[FileEntry], any Error>, to node: FileNode) {
        let isRoot = node === root
        switch result {
        case .success(let entries):
            preservingSelection {
                node.setChildren(entries, sort: Preferences.sort)
                outlineView.reloadItem(isRoot ? nil : node, reloadChildren: true)
            }
            if isRoot {
                state.itemCount = entries.count
                setError(nil)
            }
            if isRoot, state.isFiltering { applyFilter() }
            requestFolderSizes(in: node)
        case .failure(let error):
            node.children = []
            outlineView.reloadItem(isRoot ? nil : node, reloadChildren: true)
            if isRoot {
                state.itemCount = 0
                setError(Self.paneError(for: error, url: node.url))
            }
        }
        state.selectedCount = outlineView.selectedRowIndexes.count
        applyPendingSelection()
    }

    private func setError(_ error: PaneError?) {
        state.error = error
        messageHost?.isHidden = error == nil
    }

    private static func paneError(for error: any Error, url: URL) -> PaneError {
        let name = url.path == "/" ? "/" : url.lastPathComponent
        let code = (error as? CocoaError)?.code
        if code == .fileReadNoPermission {
            // EPERM は macOS のプライバシー保護（フルディスクアクセスで解決できる）、
            // EACCES はファイル自体の権限（フルディスクアクセスでは解決できない）
            let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError
            if underlying?.domain == NSPOSIXErrorDomain, underlying?.code == Int(EACCES) {
                return PaneError(
                    message: "「\(name)」を開くアクセス権がありません。\nこのフォルダは所有者以外が読めない設定になっています。",
                    needsPermission: false
                )
            }
            return PaneError(
                message: "「\(name)」を開くアクセス権がありません。\nシステム設定の「プライバシーとセキュリティ」→「フルディスクアクセス」で noxy を許可してください。",
                needsPermission: true
            )
        }
        if code == .fileReadNoSuchFile {
            return PaneError(message: "「\(name)」が見つかりません。", needsPermission: false)
        }
        return PaneError(message: "「\(name)」を開けませんでした。\n\(error.localizedDescription)", needsPermission: false)
    }

    private static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    private func updateAvailableCapacity() {
        let url = state.currentURL
        Task {
            let capacity = await DirectoryReader.availableCapacity(for: url)
            guard url.path == state.currentURL.path else { return }
            state.availableCapacity = capacity
        }
    }

    // MARK: - 選択

    func select(_ urls: [URL]) {
        // /tmp と /private/tmp のような表記の違いがあっても同じ場所として扱う
        let paths = Set(urls.map(Self.comparablePath))
        let rows = IndexSet((0..<outlineView.numberOfRows).filter { row in
            guard let node = outlineView.item(atRow: row) as? FileNode else { return false }
            return paths.contains(Self.comparablePath(node.url))
        })
        outlineView.selectRowIndexes(rows, byExtendingSelection: false)
        if let first = rows.first { outlineView.scrollRowToVisible(first) }
    }

    static func comparablePath(_ url: URL) -> String {
        realPath(url.standardizedFileURL.path)
    }

    /// シンボリックリンクを解決した実体のパス（/tmp → /private/tmp）。
    /// URL.resolvingSymlinksInPath は先頭の /private を取り除いてしまうため、realpath を使う。
    static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// 再読み込みしても選択状態を保つ。
    private func preservingSelection(_ body: () -> Void) {
        let selected = selectedNodes.map(\.url)
        body()
        if !selected.isEmpty { select(selected) }
    }

    // MARK: - 外部の変更・設定の変更

    private func startWatching() {
        watcher?.stop()
        watcher = DirectoryWatcher(url: root.url) { [weak self] paths in
            self?.handleFileSystemEvents(paths)
        }
    }

    /// ウィンドウを閉じるときに呼ぶ。
    func tearDown() {
        watcher?.stop()
        watcher = nil
    }

    private func handleFileSystemEvents(_ paths: [String]) {
        if renamingNode != nil {
            needsRefreshAfterRename = true
            return
        }
        // 表示中のフォルダ自体が消えたら、残っている一番近い親フォルダへ移動する
        var existing = root.url
        while !FileManager.default.fileExists(atPath: existing.path), existing.path != "/" {
            existing = existing.deletingLastPathComponent()
        }
        if existing.path != root.path {
            state.history.replaceCurrent(with: existing)
            navigate(to: existing, recordHistory: false)
            return
        }

        // FSEvents は /private/var のように実体のパスで届くことがあるので、両方で照合する
        var lookup: [String: FileNode] = [:]
        for folder in root.loadedFolders() {
            lookup[folder.path] = folder
            lookup[Self.realPath(folder.path)] = folder
        }
        var targets: [ObjectIdentifier: FileNode] = [:]
        for raw in paths {
            let path = raw.count > 1 && raw.hasSuffix("/") ? String(raw.dropLast()) : raw
            // 中身が変わったフォルダのサイズは計算し直す
            FolderSizeService.shared.invalidate(path: path)
            if let folder = lookup[path] { FolderSizeService.shared.invalidate(path: folder.path) }
            if let folder = lookup[path] {
                targets[ObjectIdentifier(folder)] = folder
            }
        }
        targets.values.forEach(load)
        refreshGitStatus()
    }

    @objc private func displayPreferencesChanged(_ notification: Notification) {
        let sort = Preferences.sort
        if sort != lastSort {
            lastSort = sort
            isApplyingSort = true
            outlineView.sortDescriptors = [sort.descriptor]
            isApplyingSort = false
            preservingSelection {
                root.resort(sort)
                outlineView.reloadItem(nil, reloadChildren: true)
            }
        }

        let folderSizes = Preferences.calculateFolderSizes
        if folderSizes != lastFolderSizes {
            lastFolderSizes = folderSizes
            if folderSizes {
                root.loadedFolders().forEach(requestFolderSizes(in:))
            } else {
                FolderSizeService.shared.cancel(owner: self)
                reloadAllFolders()
            }
        }

        let showHidden = Preferences.showHiddenFiles
        if showHidden != lastShowHiddenFiles {
            lastShowHiddenFiles = showHidden
            reloadAllFolders()
        }
    }

    /// 表示中のフォルダと展開中のフォルダを読み直す。閉じているフォルダは次に開いたときに読む。
    func reloadAllFolders() {
        for folder in root.loadedFolders() {
            if folder === root || outlineView.isItemExpanded(folder) {
                load(folder)
            } else {
                folder.children = nil
            }
        }
    }
}

// MARK: - NSOutlineViewDataSource

extension FileBrowserViewController: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        let node = (item as? FileNode) ?? root
        guard let children = displayedChildren(of: node) else {
            if item != nil { load(node) }
            return 0
        }
        return children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        let node = (item as? FileNode) ?? root
        return displayedChildren(of: node)![index]
    }

    /// 絞り込み中は、表示中のフォルダの項目だけを絞る（展開したフォルダの中身はそのまま）
    private func displayedChildren(of node: FileNode) -> [FileNode]? {
        if node === root, let filteredRootChildren { return filteredRootChildren }
        return node.children
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? FileNode)?.entry.isFolder ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard !isApplyingSort,
              let descriptor = outlineView.sortDescriptors.first,
              let sort = FileSort(descriptor: descriptor) else { return }
        // 通知を受けて、すべてのウィンドウ（このウィンドウも含む）が並べ替える
        Preferences.sort = sort
    }
}

// MARK: - NSOutlineViewDelegate

extension FileBrowserViewController: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FileNode,
              let identifier = tableColumn?.identifier,
              let column = FileColumn(rawValue: identifier.rawValue) else { return nil }
        let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? FileCellView
            ?? FileCellView(column: column)
        cell.configure(with: node, gitStatus: gitSnapshot?.status(for: node.url))
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        state.selectedCount = outlineView.selectedRowIndexes.count
        updatePreviewPanel()
    }

    func outlineView(_ outlineView: NSOutlineView, typeSelectStringFor tableColumn: NSTableColumn?, item: Any) -> String? {
        guard tableColumn?.identifier == FileColumn.name.identifier else { return nil }
        return (item as? FileNode)?.entry.name
    }
}

// MARK: - 右クリックメニュー

extension FileBrowserViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if menu === headerMenu {
            buildHeaderMenu(menu)
        } else if menu === rowMenu {
            buildRowMenu(menu)
        }
    }

    /// 列の表示・非表示（名前の列は常に表示）。
    private func buildHeaderMenu(_ menu: NSMenu) {
        for column in FileColumn.allCases where column != .name {
            guard let tableColumn = outlineView.tableColumn(withIdentifier: column.identifier) else { continue }
            let item = NSMenuItem(title: column.title, action: #selector(toggleColumn(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = column.rawValue
            item.state = tableColumn.isHidden ? .off : .on
            menu.addItem(item)
        }
    }

    @objc private func toggleColumn(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let tableColumn = outlineView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(raw)) else { return }
        tableColumn.isHidden.toggle()
        fitNameColumn()
    }

    /// 右クリックした行が選択に含まれていれば選択全体、そうでなければその行だけが対象。
    private var contextNodes: [FileNode] {
        let row = outlineView.clickedRow
        guard row >= 0, let clicked = outlineView.item(atRow: row) as? FileNode else { return [] }
        return outlineView.selectedRowIndexes.contains(row) ? selectedNodes : [clicked]
    }

    private func buildRowMenu(_ menu: NSMenu) {
        let nodes = contextNodes
        guard !nodes.isEmpty else {
            buildBackgroundMenu(menu)
            return
        }
        // 右クリックした行が選択に含まれていなければ、その行を選択し直す（以降の操作の対象をはっきりさせる）
        let clickedRow = outlineView.clickedRow
        if !outlineView.selectedRowIndexes.contains(clickedRow) {
            outlineView.selectRowIndexes([clickedRow], byExtendingSelection: false)
        }
        let urls = nodes.map(\.url)
        let folders = nodes.filter(\.entry.isFolder).map(\.url)

        menu.addItem(menuItem("開く", #selector(openFromMenu(_:)), urls))

        if nodes.count == 1, !nodes[0].entry.isFolder {
            menu.addItem(openWithMenuItem(for: nodes[0].url))
        }
        if !folders.isEmpty {
            menu.addItem(menuItem("新しいタブで開く", #selector(openInNewTabFromMenu(_:)), folders))
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "ゴミ箱に入れる", action: #selector(moveToTrash(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "情報を見る", action: #selector(showInfo(_:)), keyEquivalent: ""))
        if nodes.count == 1 {
            menu.addItem(NSMenuItem(title: "名前を変更", action: #selector(renameSelection(_:)), keyEquivalent: ""))
        } else {
            menu.addItem(NSMenuItem(title: "\(nodes.count) 項目の名前を変更…", action: #selector(bulkRename(_:)), keyEquivalent: ""))
        }
        menu.addItem(NSMenuItem(title: nodes.count == 1 ? "「\(nodes[0].entry.name)」を圧縮" : "\(nodes.count) 項目を圧縮", action: #selector(compress(_:)), keyEquivalent: ""))
        if nodes.contains(where: { Self.isZip($0.url) }) {
            menu.addItem(NSMenuItem(title: "展開", action: #selector(expandArchive(_:)), keyEquivalent: ""))
        }
        menu.addItem(NSMenuItem(title: "複製", action: #selector(duplicate(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "シンボリックリンクを作成", action: #selector(makeSymbolicLink(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "クイックルック", action: #selector(toggleQuickLook(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "コピー", action: #selector(copy(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "カット", action: #selector(cut(_:)), keyEquivalent: ""))

        menu.addItem(.separator())
        menu.addItem(menuItem("Finder で表示", #selector(revealInFinder(_:)), urls))
        if !folders.isEmpty {
            menu.addItem(menuItem("サイドバーに追加", #selector(addToSidebarFromMenu(_:)), folders))
        }
        for item in menu.items where item.target == nil && item.action != nil {
            item.target = self
        }
    }

    /// 何もない所を右クリックしたときのメニュー。
    private func buildBackgroundMenu(_ menu: NSMenu) {
        outlineView.deselectAll(nil)
        menu.addItem(NSMenuItem(title: "新規フォルダ", action: #selector(newFolder(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "新規ファイル", action: #selector(newFile(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "ペースト", action: #selector(paste(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(menuItem("Finder で表示", #selector(revealInFinder(_:)), [state.currentURL]))
        for item in menu.items where item.target == nil && item.action != nil {
            item.target = self
        }
    }

    private func menuItem(_ title: String, _ action: Selector, _ urls: [URL]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = urls
        return item
    }

    private func openWithMenuItem(for url: URL) -> NSMenuItem {
        let item = NSMenuItem(title: "このアプリケーションで開く", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let defaultApp = NSWorkspace.shared.urlForApplication(toOpen: url)
        var apps = NSWorkspace.shared.urlsForApplications(toOpen: url)
        if let defaultApp {
            apps.removeAll { $0.path == defaultApp.path }
            apps.insert(defaultApp, at: 0)
        }
        for (index, app) in apps.enumerated() {
            var title = FileManager.default.displayName(atPath: app.path)
            if index == 0, defaultApp != nil { title += "（デフォルト）" }
            let appItem = NSMenuItem(title: title, action: #selector(openWithApplication(_:)), keyEquivalent: "")
            appItem.target = self
            appItem.representedObject = [url, app]
            let icon = NSWorkspace.shared.icon(forFile: app.path)
            icon.size = NSSize(width: 16, height: 16)
            appItem.image = icon
            submenu.addItem(appItem)
            if index == 0, defaultApp != nil, apps.count > 1 { submenu.addItem(.separator()) }
        }
        if apps.isEmpty {
            submenu.addItem(NSMenuItem(title: "開けるアプリケーションがありません", action: nil, keyEquivalent: ""))
        }
        item.submenu = submenu
        return item
    }

    private func urls(from sender: NSMenuItem) -> [URL] {
        sender.representedObject as? [URL] ?? []
    }

    @objc private func openFromMenu(_ sender: NSMenuItem) {
        open(contextNodesMatching(urls(from: sender)))
    }

    private func contextNodesMatching(_ urls: [URL]) -> [FileNode] {
        let paths = Set(urls.map(\.path))
        return (0..<outlineView.numberOfRows).compactMap { row in
            guard let node = outlineView.item(atRow: row) as? FileNode, paths.contains(node.path) else { return nil }
            return node
        }
    }

    @objc private func openInNewTabFromMenu(_ sender: NSMenuItem) {
        for url in urls(from: sender) {
            delegate?.browser(self, openInNewTab: url)
        }
    }

    @objc private func revealInFinder(_ sender: NSMenuItem) {
        NSWorkspace.shared.activateFileViewerSelecting(urls(from: sender))
    }

    @objc private func addToSidebarFromMenu(_ sender: NSMenuItem) {
        urls(from: sender).forEach(SidebarStore.shared.addFavorite)
    }

    @objc private func openWithApplication(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [URL], pair.count == 2 else { return }
        NSWorkspace.shared.open([pair[0]], withApplicationAt: pair[1], configuration: NSWorkspace.OpenConfiguration())
    }
}

// MARK: - メニューの有効・無効

extension FileBrowserViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        validateFileMenuItem(menuItem) ?? validateIntegrationMenuItem(menuItem) ?? validateExtrasMenuItem(menuItem) ?? true
    }
}
