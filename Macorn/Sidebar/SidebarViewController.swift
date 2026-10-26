import AppKit
import Observation

/// サイドバーの1行。セクションの見出し・お気に入り・タグ・場所・タグのセクションの項目。
/// NSOutlineView は行をオブジェクトの同一性で覚えるため、作り直しても同じ ID なら同じオブジェクトを使う。
final class SidebarNode {
    enum Kind {
        case section(SidebarSection)
        case favorite(SidebarItem)
        case tag(Tag)
        case volume(SidebarItem)
        case taggedItem(URL)
        case hint(String)
    }

    let id: String
    var kind: Kind
    var children: [SidebarNode] = []

    init(id: String, kind: Kind) {
        self.id = id
        self.kind = kind
    }

    var section: SidebarSection? {
        if case .section(let section) = kind { return section }
        return nil
    }
}

/// サイドバーの中でドラッグするもの。ファイルのドラッグと区別するため、専用の種類で受け渡す
private enum SidebarDrag {
    static let type = NSPasteboard.PasteboardType("dev.macorn.sidebar-item")

    case section(SidebarSection)
    case tag(UUID)
    case favorite(String)

    var string: String {
        switch self {
        case .section(let section): "section:" + section.id
        case .tag(let id): "tag:" + id.uuidString
        case .favorite(let id): "favorite:" + id
        }
    }

    init?(_ string: String) {
        if string.hasPrefix("section:"), let section = SidebarSection(id: String(string.dropFirst(8))) {
            self = .section(section)
        } else if string.hasPrefix("tag:"), let id = UUID(uuidString: String(string.dropFirst(4))) {
            self = .tag(id)
        } else if string.hasPrefix("favorite:") {
            self = .favorite(String(string.dropFirst(9)))
        } else {
            return nil
        }
    }
}

/// サイドバー（Finder や メール と同じ NSOutlineView のソースリスト）。
/// 見出し・タグ・お気に入りはドラッグで並べ替えられ、ドラッグ中は行が動いて置き場所が空く。
final class SidebarViewController: NSViewController {
    private let store: SidebarStore
    private let tags: TagStore
    private let window: WindowModel
    private let onSelect: (URL) -> Void

    private let outlineView = NSOutlineView()
    private var roots: [SidebarNode] = []
    private var nodeCache: [String: SidebarNode] = [:]
    private var isSyncingSelection = false
    private var isRestoringExpansion = false
    /// 閉じたタグの行（"tag:<ID>"）。次に開いたときも閉じたままにする
    private var collapsedTagIDs = Set(UserDefaults.standard.stringArray(forKey: "sidebarCollapsedTags") ?? []) {
        didSet { UserDefaults.standard.set(Array(collapsedTagIDs).sorted(), forKey: "sidebarCollapsedTags") }
    }
    private var lastRetarget: (node: SidebarNode?, index: Int) = (nil, -1)
    private let contextMenu = NSMenu()

    init(store: SidebarStore = .shared, tags: TagStore = .shared, window: WindowModel, onSelect: @escaping (URL) -> Void) {
        self.store = store
        self.tags = tags
        self.window = window
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sidebar"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.floatsGroupRows = false
        outlineView.rowSizeStyle = .default
        outlineView.indentationPerLevel = 12
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(rowClicked(_:))

        // ドラッグ＆ドロップ: 行の間に置き場所を空けて見せる（Finder のサイドバーと同じ動き）
        outlineView.registerForDraggedTypes([SidebarDrag.type, .fileURL])
        outlineView.draggingDestinationFeedbackStyle = .gap
        // 置き先が .move を返すので「＋」は出ない。項目（タグのセクションのファイル）を一覧へ落とす場合に備えて、ほかの操作も許す
        outlineView.setDraggingSourceOperationMask([.move, .copy, .link, .generic], forLocal: true)
        outlineView.setDraggingSourceOperationMask([.copy, .link, .generic], forLocal: false)

        contextMenu.delegate = self
        outlineView.menu = contextMenu

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        view = scrollView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(storesChanged(_:)), name: .macornTagsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(storesChanged(_:)), name: .macornThemeChanged, object: nil)
        observeSidebarStore()
        reload()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        store.refreshMissing()
    }

    /// お気に入り・セクション・場所が変わったら作り直す
    private func observeSidebarStore() {
        withObservationTracking {
            _ = store.favorites
            _ = store.sections
            _ = store.hiddenSections
            _ = store.volumes
            _ = tags.tags
            _ = window.activePane.currentURL
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.reload()
                self?.observeSidebarStore()
            }
        }
    }

    @objc private func storesChanged(_ notification: Notification) {
        reload()
    }

    // MARK: - 木の組み立て

    private func node(_ id: String, _ kind: SidebarNode.Kind, children: [SidebarNode] = []) -> SidebarNode {
        let node = nodeCache[id] ?? SidebarNode(id: id, kind: kind)
        node.kind = kind
        node.children = children
        nodeCache[id] = node
        return node
    }

    private func tagNode(_ tag: Tag) -> SidebarNode {
        node("tag:" + tag.id.uuidString, .tag(tag), children: tags.children(of: tag).map { tagNode($0) })
    }

    private func buildTree() -> [SidebarNode] {
        store.visibleSections.map { section in
            var children: [SidebarNode]
            switch section {
            case .favorites:
                children = store.favorites.map { node("favorite:" + $0.id, .favorite($0)) }
                if children.isEmpty { children = [node("hint:favorites", .hint("フォルダやタグをここへドラッグ"))] }
            case .tags:
                children = tags.rootTags.map(tagNode)
                if children.isEmpty { children = [node("hint:tags", .hint("項目を右クリック ›「タグ」で作れます"))] }
            case .locations:
                children = store.volumes.map { node("volume:" + $0.id, .volume($0)) }
            case .tag(let id):
                let urls = tags.urls(taggedWith: id).filter { FileManager.default.fileExists(atPath: $0.path) }
                children = urls.map { node("tagged:\(id.uuidString):" + $0.path, .taggedItem($0)) }
                if children.isEmpty { children = [node("hint:" + section.id, .hint("このタグが付いた項目はまだありません"))] }
            }
            return node("section:" + section.id, .section(section), children: children)
        }
    }

    func reload() {
        guard isViewLoaded else { return }
        roots = buildTree()
        outlineView.reloadData()
        // セクションはいつも開いておく。子のあるタグは、閉じたものを除いて開く
        isRestoringExpansion = true
        for root in roots { outlineView.expandItem(root) }
        func expandTags(_ nodes: [SidebarNode]) {
            for node in nodes where !node.children.isEmpty {
                if case .tag = node.kind, collapsedTagIDs.contains(node.id) { continue }
                outlineView.expandItem(node)
                expandTags(node.children)
            }
        }
        for root in roots { expandTags(root.children) }
        isRestoringExpansion = false
        syncSelection()
    }

    /// 表示中のフォルダ（またはタグ）に当たる行を選択状態にする
    func syncSelection() {
        let url = window.activePane.currentURL
        let wanted: String? = TagLocation.tagID(from: url).map { "tag:" + $0.uuidString }
        var match: SidebarNode?
        func visit(_ nodes: [SidebarNode]) {
            for node in nodes where match == nil {
                switch node.kind {
                case .favorite(let item):
                    if let wanted, item.tagID != nil, "tag:" + item.tagID!.uuidString == wanted { match = node }
                    if wanted == nil, item.tagID == nil, item.url.path == url.path { match = node }
                case .tag(let tag):
                    if wanted == "tag:" + tag.id.uuidString { match = node }
                case .volume(let item):
                    if wanted == nil, item.url.path == url.path { match = node }
                case .taggedItem(let itemURL):
                    if wanted == nil, itemURL.path == url.path { match = node }
                default:
                    break
                }
                visit(node.children)
            }
        }
        visit(roots)
        isSyncingSelection = true
        defer { isSyncingSelection = false }
        if let match, case let row = outlineView.row(forItem: match), row >= 0 {
            outlineView.selectRowIndexes([row], byExtendingSelection: false)
        } else {
            outlineView.deselectAll(nil)
        }
    }

    // MARK: - クリック

    @objc private func rowClicked(_ sender: Any?) {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? SidebarNode else { return }
        open(node)
    }

    private func open(_ node: SidebarNode) {
        switch node.kind {
        case .favorite(let item): onSelect(item.url)
        case .tag(let tag): onSelect(TagLocation.url(for: tag.id))
        case .volume(let item): onSelect(item.url)
        case .taggedItem(let url): onSelect(url)
        case .section, .hint: break
        }
    }

    private func sectionNode(containing node: SidebarNode) -> SidebarNode? {
        var current: SidebarNode? = node
        while let candidate = current {
            if candidate.section != nil { return candidate }
            current = outlineView.parent(forItem: candidate) as? SidebarNode
        }
        return nil
    }
}

// MARK: - データ

extension SidebarViewController: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? SidebarNode)?.children.count ?? roots.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? SidebarNode)?.children[index] ?? roots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !((item as? SidebarNode)?.children.isEmpty ?? true)
    }

    // MARK: ドラッグ

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
        guard let node = item as? SidebarNode else { return nil }
        let drag: SidebarDrag
        switch node.kind {
        case .section(let section): drag = .section(section)
        case .tag(let tag): drag = .tag(tag.id)
        case .favorite(let item): drag = .favorite(item.id)
        case .taggedItem(let url): return url as NSURL
        default: return nil
        }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(drag.string, forType: SidebarDrag.type)
        return pasteboardItem
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: any NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        validateDrop(info.draggingPasteboard, target: item as? SidebarNode, index: index)
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: any NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        acceptDrop(info.draggingPasteboard, target: item as? SidebarNode, index: index)
    }

    /// 置き先を変える（行の上・行の間）。デバッグ用に最後の置き先も覚えておく
    private func retarget(_ node: SidebarNode?, dropChildIndex index: Int) {
        lastRetarget = (node, index)
        outlineView.setDropItem(node, dropChildIndex: index)
    }

    private func validateDrop(_ pasteboard: NSPasteboard, target: SidebarNode?, index: Int) -> NSDragOperation {
        lastRetarget = (target, index)
        if let string = pasteboard.string(forType: SidebarDrag.type), let drag = SidebarDrag(string) {
            return validateInternalDrop(drag, target: target, index: index)
        }
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return [] }
        return validateFileDrop(urls, target: target, index: index)
    }

    private func validateInternalDrop(_ drag: SidebarDrag, target: SidebarNode?, index: Int) -> NSDragOperation {
        switch drag {
        case .section:
            // 見出しどうしの間にだけ置ける
            return retargetBetweenSections(target: target, index: index) ? .move : []
        case .tag(let id):
            if let favorites = favoritesTarget(target: target, index: index) {
                retarget(favorites.node, dropChildIndex: favorites.index)
                return .move
            }
            // 「タグ」の中: ほかのタグの上なら、その下の階層へ。見出しの上なら、いちばん上の階層へ
            if let parent = tagParentTarget(target: target) {
                guard tags.canMoveTag(id, under: parent.parentID) else { return [] }
                retarget(parent.node, dropChildIndex: NSOutlineViewDropOnItemIndex)
                return .move
            }
            // 見出しの間に置くと、そのタグのセクションになる（自分のセクションの中は除く）
            if let target, let section = sectionNode(containing: target), section.section == .tag(id) { return [] }
            return retargetBetweenSections(target: target, index: index) ? .move : []
        case .favorite:
            guard let favorites = favoritesTarget(target: target, index: index) else { return [] }
            retarget(favorites.node, dropChildIndex: favorites.index)
            return .move
        }
    }

    /// お気に入りの中に置くときの、置き先（お気に入りの見出しと何番目か）
    private func favoritesTarget(target: SidebarNode?, index: Int) -> (node: SidebarNode, index: Int)? {
        guard let target, let section = sectionNode(containing: target), section.section == .favorites else { return nil }
        let count = store.favorites.count
        if target === section {
            return (section, index == NSOutlineViewDropOnItemIndex ? count : min(index, count))
        }
        // お気に入りの行の上に置いたら、その行の前に入れる
        let position = section.children.firstIndex { $0 === target } ?? count
        return (section, min(position, count))
    }

    /// 「タグ」のセクションの中に置くときの、新しい親（タグの行ならそのタグ、見出しや空き場所なら nil ＝いちばん上）
    private func tagParentTarget(target: SidebarNode?) -> (node: SidebarNode, parentID: UUID?)? {
        guard let target, let section = sectionNode(containing: target), section.section == .tags else { return nil }
        if case .tag(let tag) = target.kind { return (target, tag.id) }
        return (section, nil)
    }

    /// 見出しの間（ルート）に置き先を合わせる。セクションの中に入ったら、そのセクションの前にする
    private func retargetBetweenSections(target: SidebarNode?, index: Int) -> Bool {
        if target == nil {
            return index != NSOutlineViewDropOnItemIndex
        }
        guard let section = sectionNode(containing: target!), let position = roots.firstIndex(where: { $0 === section }) else { return false }
        retarget(nil, dropChildIndex: position)
        return true
    }

    private func validateFileDrop(_ urls: [URL], target: SidebarNode?, index: Int) -> NSDragOperation {
        guard let target else { return [] }
        // タグの行・お気に入りのタグ・タグのセクションへ置くと、そのタグを付ける
        if let tagID = tagID(for: target) {
            retarget(target, dropChildIndex: NSOutlineViewDropOnItemIndex)
            _ = tagID
            return .link
        }
        // お気に入りへ置くと、フォルダをその位置に入れる
        if urls.contains(where: FileTransfer.isDirectory), let favorites = favoritesTarget(target: target, index: index) {
            retarget(favorites.node, dropChildIndex: favorites.index)
            return .link
        }
        return []
    }

    private func tagID(for node: SidebarNode) -> UUID? {
        switch node.kind {
        case .tag(let tag): return tag.id
        case .favorite(let item): return item.tagID
        case .section(.tag(let id)): return id
        default: return nil
        }
    }

    private func acceptDrop(_ pasteboard: NSPasteboard, target: SidebarNode?, index: Int) -> Bool {
        if let string = pasteboard.string(forType: SidebarDrag.type), let drag = SidebarDrag(string) {
            return acceptInternalDrop(drag, target: target, index: index)
        }
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard let target, !urls.isEmpty else { return false }
        if let tagID = tagID(for: target) {
            tags.assign(tagID, to: urls)
            return true
        }
        if target.section == .favorites {
            for (offset, url) in urls.filter(FileTransfer.isDirectory).enumerated() {
                store.addFavorite(url, at: index + offset)
            }
            return true
        }
        return false
    }

    private func acceptInternalDrop(_ drag: SidebarDrag, target: SidebarNode?, index: Int) -> Bool {
        // ルートの index 番目の見出しの前（最後なら nil）
        let sectionBefore: SidebarSection? = target == nil && index < roots.count ? roots[index].section : nil
        switch drag {
        case .section(let section):
            guard target == nil else { return false }
            if let sectionBefore { store.moveSection(section, before: sectionBefore) } else { store.moveSectionToEnd(section) }
        case .tag(let id):
            if target?.section == .favorites {
                store.addFavoriteTag(id, at: index)
            } else if let target, let parent = tagParentTarget(target: target) {
                if parent.parentID != nil { collapsedTagIDs.remove(parent.node.id) }
                return tags.moveTag(id, under: parent.parentID)
            } else if target == nil {
                store.placeTagSection(id, before: sectionBefore)
            } else {
                return false
            }
        case .favorite(let id):
            guard target?.section == .favorites else { return false }
            store.moveFavorite(id: id, to: index)
        }
        return true
    }
}

#if DEBUG
extension SidebarViewController {
    /// デバッグ用: ドラッグ＆ドロップを、本物と同じ確認・処理の流れで行う。
    /// drag は "section:tags" "tag:<名前>" "favorite:<パス>"、onto は行の ID（"section:favorites" "tag:<名前>" など）か "root"
    /// デバッグ用: 表示中の行（字下げ＝階層）
    func debugRows() -> String {
        (0..<outlineView.numberOfRows).compactMap { row in
            guard let node = outlineView.item(atRow: row) as? SidebarNode else { return nil }
            let indent = String(repeating: "  ", count: outlineView.level(forRow: row))
            let title: String
            switch node.kind {
            case .section(let section): title = "[" + section.title + "]"
            case .favorite(let item): title = item.name
            case .tag(let tag): title = "#" + tag.leafName
            case .volume(let item): title = item.name
            case .taggedItem(let url): title = url.lastPathComponent
            case .hint(let text): title = "(" + text + ")"
            }
            return indent + title + (outlineView.selectedRow == row ? " *" : "")
        }.joined(separator: " / ")
    }

    func debugDrop(drag: String, onto: String, index: Int) -> String {
        func resolve(_ text: String) -> String {
            guard text.hasPrefix("tag:"), UUID(uuidString: String(text.dropFirst(4))) == nil else { return text }
            return tags.tag(named: String(text.dropFirst(4))).map { "tag:" + $0.id.uuidString } ?? text
        }
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("dev.macorn.debug-drop"))
        pasteboard.clearContents()
        pasteboard.setString(resolve(drag), forType: SidebarDrag.type)
        let target: SidebarNode? = onto == "root" ? nil : nodeCache[resolve(onto)]
        if onto != "root", target == nil { return "no-target" }
        let operation = validateDrop(pasteboard, target: target, index: index)
        guard !operation.isEmpty else { return "refused" }
        let (node, retargetIndex) = lastRetarget
        return acceptDrop(pasteboard, target: node, index: retargetIndex) ? "moved→\(node?.id ?? "root")@\(retargetIndex)" : "failed"
    }
}
#endif

// MARK: - 見た目

extension SidebarViewController: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        (item as? SidebarNode)?.section != nil
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let node = item as? SidebarNode else { return false }
        switch node.kind {
        case .section, .hint: return false
        default: return true
        }
    }

    func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool {
        // 見出しの「隠す」ボタンは出さない（隠すのは右クリックから）
        (item as? SidebarNode)?.section == nil
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !isRestoringExpansion, let node = notification.userInfo?["NSObject"] as? SidebarNode, case .tag = node.kind else { return }
        collapsedTagIDs.insert(node.id)
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !isRestoringExpansion, let node = notification.userInfo?["NSObject"] as? SidebarNode, case .tag = node.kind else { return }
        collapsedTagIDs.remove(node.id)
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        ThemedRowView()
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? SidebarNode else { return nil }
        if case .section(let section) = node.kind {
            let header = outlineView.makeView(withIdentifier: SidebarHeaderView.identifier, owner: self) as? SidebarHeaderView ?? SidebarHeaderView()
            header.configure(section: section, tags: tags) { [weak self] in
                guard let self else { return }
                SidebarPrompts.createTag(parent: nil, in: tags)
            }
            return header
        }
        let cell = outlineView.makeView(withIdentifier: SidebarCellView.identifier, owner: self) as? SidebarCellView ?? SidebarCellView()
        switch node.kind {
        case .favorite(let item):
            if let tagID = item.tagID {
                let tag = tags.tag(id: tagID)
                cell.configure(
                    title: item.customName ?? tag?.name ?? "（削除されたタグ）",
                    symbol: "tag.fill", tint: NSColor(hex: tag?.color ?? "#8E8E93"),
                    count: tag.map { tags.count(for: $0.id) }, dimmed: tag == nil
                )
            } else {
                let color = tags.folderColor(for: item.url)
                cell.configure(
                    title: item.name,
                    symbol: item.isMissing ? "exclamationmark.triangle" : (color != nil && item.symbol == "folder" ? "folder.fill" : item.symbol),
                    tint: color.map(NSColor.init(hex:)), dimmed: item.isMissing
                )
            }
            cell.toolTip = item.url.isFileURL ? item.url.path : nil
        case .tag(let tag):
            cell.configure(title: tag.leafName, dotColor: NSColor(hex: tag.color), count: tags.count(for: tag.id))
            cell.toolTip = tag.name
        case .volume(let item):
            cell.configure(title: item.name, symbol: item.symbol, ejectable: item.isEjectable) { [weak self] in
                self?.store.eject(item)
            }
            cell.toolTip = item.url.path
        case .taggedItem(let url):
            if FileTransfer.isDirectory(url) {
                cell.configure(title: url.lastPathComponent, symbol: "folder.fill", tint: tags.folderColor(for: url).map(NSColor.init(hex:)))
            } else {
                cell.configure(title: url.lastPathComponent, image: NSWorkspace.shared.icon(forFile: url.path))
            }
            cell.toolTip = url.path
        case .hint(let text):
            cell.configure(title: text, hint: true)
            cell.toolTip = nil
        case .section:
            break
        }
        return cell
    }
}

// MARK: - 右クリック

extension SidebarViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? SidebarNode else {
            menu.addItem(item("サイドバーをカスタマイズ…") { SettingsWindowController.shared.show(tab: .sidebar) })
            return
        }
        switch node.kind {
        case .section(let section): sectionMenu(menu, section)
        case .favorite(let favorite): favoriteMenu(menu, favorite)
        case .tag(let tag): tagMenu(menu, tag)
        case .volume(let volume):
            if volume.isEjectable { menu.addItem(item("取り出す") { [weak self] in self?.store.eject(volume) }) }
        case .taggedItem(let url):
            menu.addItem(item("Finder で表示") { NSWorkspace.shared.activateFileViewerSelecting([url]) })
        case .hint:
            break
        }
    }

    private func sectionMenu(_ menu: NSMenu, _ section: SidebarSection) {
        let visible = store.visibleSections
        let up = item("上へ移動") { [weak self] in self?.store.moveSection(section, by: -1) }
        up.isEnabled = visible.first != section
        let down = item("下へ移動") { [weak self] in self?.store.moveSection(section, by: 1) }
        down.isEnabled = visible.last != section
        [up, down].forEach(menu.addItem)
        menu.addItem(.separator())
        if case .tag(let id) = section {
            menu.addItem(item("サイドバーから外す") { [weak self] in self?.store.removeTagSection(id) })
        } else {
            menu.addItem(item("「\(section.title)」を隠す") { [weak self] in self?.store.setSection(section, hidden: true) })
        }
        if section == .tags {
            menu.addItem(item("タグを作る…") { [weak self] in
                guard let self else { return }
                SidebarPrompts.createTag(parent: nil, in: tags)
            })
        }
        menu.addItem(.separator())
        menu.addItem(item("サイドバーをカスタマイズ…") { SettingsWindowController.shared.show(tab: .sidebar) })
    }

    private func favoriteMenu(_ menu: NSMenu, _ favorite: SidebarItem) {
        menu.addItem(item("名前を変更…") { [weak self] in
            guard let self else { return }
            SidebarPrompts.renameFavorite(favorite, in: store)
        })
        if favorite.customName != nil {
            menu.addItem(item(favorite.tagID == nil ? "フォルダ名に戻す" : "タグの名前に戻す") { [weak self] in
                self?.store.renameFavorite(favorite.url, to: "")
            })
        }
        if favorite.tagID == nil {
            let reveal = item("Finder で表示") { NSWorkspace.shared.activateFileViewerSelecting([favorite.url]) }
            reveal.isEnabled = !favorite.isMissing
            menu.addItem(reveal)
        }
        menu.addItem(.separator())
        menu.addItem(item("お気に入りから外す") { [weak self] in
            if let tagID = favorite.tagID { self?.store.removeFavoriteTag(tagID) } else { self?.store.removeFavorite(favorite.url) }
        })
    }

    private func tagMenu(_ menu: NSMenu, _ tag: Tag) {
        menu.addItem(item("名前を変更…") { [weak self] in
            guard let self else { return }
            SidebarPrompts.renameTag(tag, in: tags)
        })
        let colors = NSMenuItem(title: "色", action: nil, keyEquivalent: "")
        let colorMenu = NSMenu()
        let names = ["赤", "オレンジ", "黄", "緑", "青", "紫", "ピンク", "グレー"]
        for (index, color) in TagStore.palette.enumerated() {
            let colorItem = item(names[index]) { [weak self] in self?.tags.setColor(tag.id, to: color) }
            colorItem.image = FileBrowserViewController.tagDot(color)
            colorItem.state = tag.color == color ? .on : .off
            colorMenu.addItem(colorItem)
        }
        colorMenu.addItem(.separator())
        colorMenu.addItem(item("その他の色…") { SettingsWindowController.shared.show(tab: .tags) })
        colors.submenu = colorMenu
        menu.addItem(colors)
        menu.addItem(item("下の階層にタグを作る…") { [weak self] in
            guard let self else { return }
            SidebarPrompts.createTag(parent: tag, in: tags)
        })
        menu.addItem(parentMenuItem(for: tag))
        menu.addItem(.separator())
        if store.containsFavoriteTag(tag.id) {
            menu.addItem(item("お気に入りから外す") { [weak self] in self?.store.removeFavoriteTag(tag.id) })
        } else {
            menu.addItem(item("お気に入りに追加") { [weak self] in self?.store.addFavoriteTag(tag.id) })
        }
        if store.containsTagSection(tag.id) {
            menu.addItem(item("サイドバーのセクションから外す") { [weak self] in self?.store.removeTagSection(tag.id) })
        } else {
            menu.addItem(item("サイドバーのセクションにする") { [weak self] in self?.store.addTagSection(tag.id) })
        }
        menu.addItem(.separator())
        menu.addItem(item("タグを削除…") { [weak self] in
            guard let self else { return }
            SidebarPrompts.deleteTag(tag, in: tags)
        })
    }

    /// 「親のタグ」: いちばん上か、ほかのタグの下へ移す（自分と自分の子孫は選べない）
    private func parentMenuItem(for tag: Tag) -> NSMenuItem {
        let parentItem = NSMenuItem(title: "親のタグ", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let top = item("なし（いちばん上）") { [weak self] in self?.tags.moveTag(tag.id, under: nil) }
        top.state = tag.parentName == nil ? .on : .off
        top.isEnabled = tag.parentName == nil || tags.canMoveTag(tag.id, under: nil)
        submenu.addItem(top)
        submenu.addItem(.separator())
        for candidate in tags.sortedTags where !candidate.isSelfOrDescendant(of: tag.name) {
            let entry = item(candidate.leafName) { [weak self] in self?.tags.moveTag(tag.id, under: candidate.id) }
            entry.image = FileBrowserViewController.tagDot(candidate.color)
            entry.indentationLevel = candidate.depth
            entry.toolTip = candidate.name
            entry.state = tag.parentName == candidate.name ? .on : .off
            entry.isEnabled = entry.state == .on || tags.canMoveTag(tag.id, under: candidate.id)
            submenu.addItem(entry)
        }
        submenu.autoenablesItems = false
        parentItem.submenu = submenu
        return parentItem
    }

    private func item(_ title: String, _ action: @escaping () -> Void) -> NSMenuItem {
        ClosureMenuItem.make(title: title, handler: action)
    }
}

/// 押したら渡した処理を実行するメニュー項目を作る（処理は representedObject に持たせる）
enum ClosureMenuItem {
    private final class Action: NSObject {
        let handler: () -> Void
        init(_ handler: @escaping () -> Void) { self.handler = handler }
        @objc func run(_ sender: Any?) { handler() }
    }

    static func make(title: String, handler: @escaping () -> Void) -> NSMenuItem {
        let action = Action(handler)
        let item = NSMenuItem(title: title, action: #selector(Action.run(_:)), keyEquivalent: "")
        item.target = action
        item.representedObject = action  // target は弱参照なので、項目に持たせておく
        return item
    }
}

// MARK: - 行の見た目

/// 見出し（お気に入り・タグ・場所・タグのセクション）
final class SidebarHeaderView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("SidebarHeader")

    private let label = NSTextField(labelWithString: "")
    private let dot = NSImageView()
    private let addButton = NSButton()
    private var onAdd: (() -> Void)?

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        label.textColor = .secondaryLabelColor
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "タグを作る")
        addButton.isBordered = false
        addButton.contentTintColor = .secondaryLabelColor
        addButton.toolTip = "タグを作る"
        addButton.target = self
        addButton.action = #selector(add(_:))
        let stack = NSStackView(views: [dot, label, NSView(), addButton])
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        textField = label
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(section: SidebarSection, tags: TagStore, onAdd: @escaping () -> Void) {
        label.stringValue = section.title
        self.onAdd = onAdd
        addButton.isHidden = section != .tags
        if case .tag(let id) = section {
            dot.isHidden = false
            dot.image = FileBrowserViewController.tagDot(tags.tag(id: id)?.color ?? "#8E8E93", size: 8)
        } else {
            dot.isHidden = true
        }
    }

    @objc private func add(_ sender: Any?) { onAdd?() }
}

/// ふつうの行（アイコン・名前・件数・取り出しボタン）
final class SidebarCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("SidebarCell")

    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private let ejectButton = NSButton()
    private var onEject: (() -> Void)?

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        icon.imageScaling = .scaleProportionallyDown
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        countLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        countLabel.textColor = .secondaryLabelColor
        ejectButton.image = NSImage(systemSymbolName: "eject.fill", accessibilityDescription: "取り出す")
        ejectButton.isBordered = false
        ejectButton.contentTintColor = .secondaryLabelColor
        ejectButton.toolTip = "取り出す"
        ejectButton.target = self
        ejectButton.action = #selector(eject(_:))
        let stack = NSStackView(views: [icon, label, NSView(), countLabel, ejectButton])
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        textField = label
        imageView = icon
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        title: String, symbol: String? = nil, image: NSImage? = nil, tint: NSColor? = nil, dotColor: NSColor? = nil,
        count: Int? = nil, dimmed: Bool = false, ejectable: Bool = false, hint: Bool = false, onEject: (() -> Void)? = nil
    ) {
        label.stringValue = title
        label.textColor = hint || dimmed ? .secondaryLabelColor : .labelColor
        label.font = hint ? .systemFont(ofSize: NSFont.smallSystemFontSize) : .systemFont(ofSize: NSFont.systemFontSize)
        icon.isHidden = hint
        if let dotColor {
            icon.image = FileBrowserViewController.tagDot(dotColor.hexString, size: 10)
            icon.contentTintColor = nil
        } else if let image {
            icon.image = image
            icon.contentTintColor = nil
        } else if let symbol {
            icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            icon.contentTintColor = tint ?? Theme.shared.accentColor
        }
        countLabel.isHidden = count == nil
        countLabel.stringValue = count.map(String.init) ?? ""
        ejectButton.isHidden = !ejectable
        self.onEject = onEject
    }

    @objc private func eject(_ sender: Any?) { onEject?() }
}
