import AppKit
import Observation

/// サイドバーの1行。セクションの見出し・置いた項目（お気に入り・自分で作ったセクション）・タグ・場所・タグのセクションの項目。
/// NSOutlineView は行をオブジェクトの同一性で覚えるため、作り直しても同じ ID なら同じオブジェクトを使う。
final class SidebarNode {
    enum Kind {
        case section(SidebarSection)
        /// お気に入り・自分で作ったセクションに置いた項目（フォルダ・ファイル・タグ）
        case placed(SidebarItem, in: SidebarSection)
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
    /// 「タグ」の一覧のタグ
    case tag(UUID)
    /// お気に入り・自分で作ったセクションに置いた項目
    case placed(SidebarSection, String)

    var string: String {
        switch self {
        case .section(let section): "section:" + section.id
        case .tag(let id): "tag:" + id.uuidString
        case .placed(let section, let id): "placed:" + section.id + "|" + id
        }
    }

    init?(_ string: String) {
        if string.hasPrefix("section:"), let section = SidebarSection(id: String(string.dropFirst(8))) {
            self = .section(section)
        } else if string.hasPrefix("tag:"), let id = UUID(uuidString: String(string.dropFirst(4))) {
            self = .tag(id)
        } else if string.hasPrefix("placed:"), let bar = string.firstIndex(of: "|"),
                  let section = SidebarSection(id: String(string[string.index(string.startIndex, offsetBy: 7)..<bar])) {
            self = .placed(section, String(string[string.index(after: bar)...]))
        } else {
            return nil
        }
    }
}

/// サイドバー（Finder や メール と同じ NSOutlineView のソースリスト）。
/// 見出し・タグ・置いた項目はドラッグで並べ替え・移動でき、ドラッグ中は行が動いて置き場所が空く。
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
    private var collapsedTagIDs = Set(AppDefaults.store.stringArray(forKey: "sidebarCollapsedTags") ?? []) {
        didSet { AppDefaults.store.set(Array(collapsedTagIDs).sorted(), forKey: "sidebarCollapsedTags") }
    }
    private var lastRetarget: (node: SidebarNode?, index: Int) = (nil, -1)
    private let contextMenu = NSMenu()
    private let addSectionButton = NSButton()

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
        // ふつうは「移動」なので「＋」は出ない。⌥ を押すと「コピー」（元の場所にも残す）
        outlineView.setDraggingSourceOperationMask([.move, .copy, .link, .generic], forLocal: true)
        outlineView.setDraggingSourceOperationMask([.copy, .link, .generic], forLocal: false)

        contextMenu.delegate = self
        contextMenu.autoenablesItems = false
        outlineView.menu = contextMenu

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        // いちばん下の「＋ セクションを作る」ボタン
        addSectionButton.title = "セクションを作る"
        addSectionButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        addSectionButton.imagePosition = .imageLeading
        addSectionButton.isBordered = false
        addSectionButton.contentTintColor = .secondaryLabelColor
        addSectionButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        addSectionButton.toolTip = "サイドバーに新しいセクションを作る"
        addSectionButton.setAccessibilityLabel("セクションを作る")
        addSectionButton.target = self
        addSectionButton.action = #selector(createSection(_:))
        let separator = NSBox()
        separator.boxType = .separator

        let container = NSView()
        for subview in [scrollView, separator, addSectionButton] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            separator.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            addSectionButton.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 6),
            addSectionButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            addSectionButton.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -10),
            addSectionButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])
        view = container
    }

    /// 「＋ セクションを作る」: 名前を聞いて、いちばん下に作る
    @objc func createSection(_ sender: Any?) {
        SidebarPrompts.createSection(in: store)
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
            _ = store.customSections
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

    private static func placedID(_ item: SidebarItem, in section: SidebarSection) -> String {
        "placed:" + section.id + "|" + item.id
    }

    private func buildTree() -> [SidebarNode] {
        store.visibleSections.map { section in
            var children: [SidebarNode]
            switch section {
            case .favorites, .custom:
                children = store.items(in: section).map { node(Self.placedID($0, in: section), .placed($0, in: section)) }
                if children.isEmpty { children = [node("hint:" + section.id, .hint("タグやフォルダをここへドラッグ"))] }
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
        let wanted = TagLocation.tagID(from: url)
        var match: SidebarNode?
        func visit(_ nodes: [SidebarNode]) {
            for node in nodes where match == nil {
                switch node.kind {
                case .placed(let item, _):
                    if let wanted, item.tagID == wanted { match = node }
                    if wanted == nil, item.tagID == nil, item.url.path == url.path { match = node }
                case .tag(let tag):
                    if wanted == tag.id { match = node }
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
        case .placed(let item, _): onSelect(item.url)
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
        case .placed(let item, let section): drag = .placed(section, item.id)
        case .taggedItem(let url): return url as NSURL
        default: return nil
        }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(drag.string, forType: SidebarDrag.type)
        // フォルダ・ファイルは、一覧やほかのアプリへも落とせるようにパスも載せる
        if case .placed(let item, _) = node.kind, item.tagID == nil {
            pasteboardItem.setString(item.url.absoluteString, forType: .fileURL)
        }
        return pasteboardItem
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: any NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        let point = outlineView.convert(info.draggingLocation, from: nil)
        let (target, childIndex) = proposal(at: point, proposedItem: item as? SidebarNode, index: index)
        return validateDrop(info.draggingPasteboard, target: target, index: childIndex, copy: Self.isCopy(info))
    }

    /// 置き先の候補を、カーソルの位置で決め直す。
    /// 行の間に隙間を空ける表示（.gap）では、AppKit は「行の間」ばかりを候補にして「行の上」をほとんど出さない。
    /// そこで、タグを受け取れる行（タグ・置いたタグ・タグのセクションの見出し）の真ん中あたりにカーソルがあれば、その行の上に置くものとする
    private func proposal(at point: NSPoint, proposedItem: SidebarNode?, index: Int) -> (SidebarNode?, Int) {
        let row = outlineView.row(at: point)
        guard row >= 0, let node = outlineView.item(atRow: row) as? SidebarNode, acceptsDropOn(node) else { return (proposedItem, index) }
        let rect = outlineView.rect(ofRow: row)
        // 上下の端（それぞれ 25%）は「行の間」のまま
        guard abs(point.y - rect.midY) < rect.height * 0.25 else { return (proposedItem, index) }
        return (node, NSOutlineViewDropOnItemIndex)
    }

    /// 行の上に置けるか（タグを付ける・タグの下へ入れる先になる行）
    private func acceptsDropOn(_ node: SidebarNode) -> Bool {
        switch node.kind {
        case .tag, .section(.tag): true
        case .placed(let item, _): item.tagID != nil
        default: false
        }
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: any NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        acceptDrop(info.draggingPasteboard, target: item as? SidebarNode, index: index, copy: Self.isCopy(info))
    }

    /// ⌥ を押しながらのドロップ（元の場所にも残す）
    private static func isCopy(_ info: any NSDraggingInfo) -> Bool {
        let mask = info.draggingSourceOperationMask
        return mask.contains(.copy) && !mask.contains(.move)
    }

    /// 置き先を変える（行の上・行の間）。デバッグ用に最後の置き先も覚えておく
    private func retarget(_ node: SidebarNode?, dropChildIndex index: Int) {
        lastRetarget = (node, index)
        outlineView.setDropItem(node, dropChildIndex: index)
    }

    private func validateDrop(_ pasteboard: NSPasteboard, target: SidebarNode?, index: Int, copy: Bool) -> NSDragOperation {
        lastRetarget = (target, index)
        if let string = pasteboard.string(forType: SidebarDrag.type), let drag = SidebarDrag(string) {
            return validateInternalDrop(drag, target: target, index: index, copy: copy)
        }
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty, let target else { return [] }
        // タグの上へ置くとそのタグを付け、お気に入り・自分で作ったセクションへ置くとその位置に入れる
        if let assign = assignTarget(target: target, index: index) {
            retarget(assign.node, dropChildIndex: NSOutlineViewDropOnItemIndex)
            return .link
        }
        if let place = placementTarget(target: target, index: index) {
            retarget(place.node, dropChildIndex: place.index)
            return .link
        }
        return []
    }

    private func validateInternalDrop(_ drag: SidebarDrag, target: SidebarNode?, index: Int, copy: Bool) -> NSDragOperation {
        switch drag {
        case .section:
            // 見出しどうしの間にだけ置ける
            return retargetBetweenSections(target: target, index: index) ? .move : []
        case .tag(let id):
            if let place = placementTarget(target: target, index: index) {
                retarget(place.node, dropChildIndex: place.index)
                return .move
            }
            // 「タグ」の中: 行の上ならそのタグの下の階層へ、行の間ならその位置へ（並べ替え・親の変更）
            if let move = tagMoveTarget(target: target, index: index) {
                guard canPlaceTag(id, under: move.parentID, nesting: move.index == NSOutlineViewDropOnItemIndex) else { return [] }
                retarget(move.node, dropChildIndex: move.index)
                return .move
            }
            // 見出しの間に置くと、そのタグのセクションになる（自分のセクションの中は除く）
            if let target, let section = sectionNode(containing: target), section.section == .tag(id) { return [] }
            return retargetBetweenSections(target: target, index: index) ? .move : []
        case .placed(let from, let id):
            guard let item = store.items(in: from).first(where: { $0.id == id }) else { return [] }
            // フォルダ・ファイルをタグの上へ置くと、そのタグへ移す（⌥ なら元の場所にも残す）
            if item.tagID == nil, let target, let assign = assignTarget(target: target, index: index) {
                retarget(assign.node, dropChildIndex: NSOutlineViewDropOnItemIndex)
                return copy ? .copy : .move
            }
            guard let place = placementTarget(target: target, index: index) else { return [] }
            retarget(place.node, dropChildIndex: place.index)
            // タグは1か所にしか置けないので、いつも移動
            return copy && item.tagID == nil && place.node.section != from ? .copy : .move
        }
    }

    /// お気に入り・自分で作ったセクションの中に置くときの、置き先（見出しと何番目か）。
    /// 行の上に置いたら、その行の前に入れる
    private func placementTarget(target: SidebarNode?, index: Int) -> (node: SidebarNode, index: Int)? {
        guard let target, let section = sectionNode(containing: target), let kind = section.section, kind.holdsItems else { return nil }
        let count = store.items(in: kind).count
        if target === section {
            return (section, index == NSOutlineViewDropOnItemIndex ? count : min(index, count))
        }
        let position = section.children.firstIndex { $0 === target } ?? count
        return (section, min(position, count))
    }

    /// タグを付ける置き先: 「タグ」のタグの行、タグのセクション（見出しと中の項目）、
    /// お気に入り・自分で作ったセクションに置いたタグの行の上
    private func assignTarget(target: SidebarNode, index: Int) -> (node: SidebarNode, tagID: UUID)? {
        guard let section = sectionNode(containing: target), let kind = section.section else { return nil }
        switch kind {
        case .favorites, .custom:
            guard index == NSOutlineViewDropOnItemIndex, case .placed(let item, _) = target.kind, let tagID = item.tagID else { return nil }
            return (target, tagID)
        case .tags:
            guard case .tag(let tag) = target.kind else { return nil }
            return (target, tag.id)
        case .tag(let id):
            return (section, id)
        case .locations:
            return nil
        }
    }

    /// 「タグ」のセクションの中に置くときの、置き先と新しい親。
    /// タグの行の上ならそのタグの下（最後）へ、行の間ならその親の index 番目へ。見出しの上ならいちばん上の階層の最後へ
    private func tagMoveTarget(target: SidebarNode?, index: Int) -> (node: SidebarNode, index: Int, parentID: UUID?)? {
        guard let target, let section = sectionNode(containing: target), section.section == .tags else { return nil }
        switch target.kind {
        case .tag(let tag):
            return (target, index, tag.id)
        case .section:
            return index == NSOutlineViewDropOnItemIndex ? (section, tags.rootTags.count, nil) : (section, index, nil)
        default:
            // 空のときの案内の行など
            return (section, tags.rootTags.count, nil)
        }
    }

    /// タグをその親の下へ置けるか。nesting は行の上（その下の階層へ入れる）か
    private func canPlaceTag(_ id: UUID, under parentID: UUID?, nesting: Bool) -> Bool {
        guard let tag = tags.tag(id: id) else { return false }
        let parentName = parentID.flatMap { tags.tag(id: $0)?.name }
        // 自分や自分の子孫の中へは入れない
        if let parentName, parentName == tag.name || parentName.hasPrefix(tag.name + "/") { return false }
        // 同じ親の中での並べ替えはいつでもできる。行の上（すでにその下にいる）は何も変わらないので不可
        if tag.parentName == parentName { return !nesting }
        return tags.canMoveTag(id, under: parentID)
    }

    /// 見出しの間（ルート）に置き先を合わせる。セクションの中に入ったら、そのセクションの前にする
    private func retargetBetweenSections(target: SidebarNode?, index: Int) -> Bool {
        guard let target else { return index != NSOutlineViewDropOnItemIndex }
        guard let section = sectionNode(containing: target), let position = roots.firstIndex(where: { $0 === section }) else { return false }
        retarget(nil, dropChildIndex: position)
        return true
    }

    /// 置き先（ドロップ確定時の行）が指すタグ。タグを付けるドロップかどうかの判定に使う
    private func tagID(for node: SidebarNode) -> UUID? {
        switch node.kind {
        case .tag(let tag): return tag.id
        case .placed(let item, _): return item.tagID
        case .section(.tag(let id)): return id
        default: return nil
        }
    }

    private func acceptDrop(_ pasteboard: NSPasteboard, target: SidebarNode?, index: Int, copy: Bool) -> Bool {
        if let string = pasteboard.string(forType: SidebarDrag.type), let drag = SidebarDrag(string) {
            return acceptInternalDrop(drag, target: target, index: index, copy: copy)
        }
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard let target, !urls.isEmpty else { return false }
        if index == NSOutlineViewDropOnItemIndex, let tagID = tagID(for: target) {
            tags.assign(tagID, to: urls)
            return true
        }
        if let section = target.section, section.holdsItems {
            for (offset, url) in urls.enumerated() {
                store.placeURL(url, in: section, at: index + offset)
            }
            return true
        }
        return false
    }

    private func acceptInternalDrop(_ drag: SidebarDrag, target: SidebarNode?, index: Int, copy: Bool) -> Bool {
        // ルートの index 番目の見出しの前（最後なら nil）
        let sectionBefore: SidebarSection? = target == nil && index < roots.count ? roots[index].section : nil
        switch drag {
        case .section(let section):
            guard target == nil else { return false }
            if let sectionBefore { store.moveSection(section, before: sectionBefore) } else { store.moveSectionToEnd(section) }
        case .tag(let id):
            if let section = target?.section, section.holdsItems {
                store.placeTag(id, in: section, at: index)
            } else if let target, let section = sectionNode(containing: target), section.section == .tags {
                var parentID: UUID?
                if case .tag(let parent) = target.kind {
                    parentID = parent.id
                    collapsedTagIDs.remove(target.id)
                }
                return tags.moveTag(id, under: parentID, at: index == NSOutlineViewDropOnItemIndex ? nil : index)
            } else if target == nil {
                store.placeTagSection(id, before: sectionBefore)
            } else {
                return false
            }
        case .placed(let from, let id):
            guard let item = store.items(in: from).first(where: { $0.id == id }), let target else { return false }
            if index == NSOutlineViewDropOnItemIndex, item.tagID == nil, let tagID = tagID(for: target) {
                // タグへ移す。お気に入りからなら「お気に入り」のタグは外れる
                tags.assign(tagID, to: [item.url])
                if !copy, !(from == .favorites && tagID == TagStore.favoritesID) { store.removeItem(id: id, from: from) }
                return true
            }
            guard let section = target.section, section.holdsItems else { return false }
            if section == from {
                store.moveItem(id: id, in: section, to: index)
            } else if let tagID = item.tagID {
                store.placeTag(tagID, in: section, at: index)
            } else {
                store.placeURL(item.url, in: section, at: index)
                if !copy { store.removeItem(id: id, from: from) }
            }
        }
        return true
    }
}

#if DEBUG
extension SidebarViewController {
    /// デバッグ用: 表示中の行（字下げ＝階層）
    func debugRows() -> String {
        (0..<outlineView.numberOfRows).compactMap { row in
            guard let node = outlineView.item(atRow: row) as? SidebarNode else { return nil }
            let indent = String(repeating: "  ", count: outlineView.level(forRow: row))
            let title: String
            switch node.kind {
            case .section(let section): title = "[" + section.title + "]"
            case .placed(let item, _): title = (item.tagID != nil ? "#" : "") + item.name
            case .tag(let tag): title = "#" + tag.leafName
            case .volume(let item): title = item.name
            case .taggedItem(let url): title = url.lastPathComponent
            case .hint(let text): title = "(" + text + ")"
            }
            return indent + title + (outlineView.selectedRow == row ? " *" : "")
        }.joined(separator: " / ")
    }

    /// デバッグ用: カーソルが行 onto の上から fraction（0 が上端、1 が下端）の位置にあるときのドロップ。
    /// AppKit が出す候補（その行の前の隙間）から始めて、カーソルの位置での決め直しも含めて確かめる
    func debugHoverDrop(drag: String, onto: String, fraction: CGFloat, copy: Bool = false) -> String {
        guard let node = nodeCache[debugResolve(onto)], case let row = outlineView.row(forItem: node), row >= 0 else { return "no-target" }
        let rect = outlineView.rect(ofRow: row)
        let point = NSPoint(x: rect.midX, y: rect.minY + rect.height * fraction)
        // .gap のときの AppKit の候補: 親の中の、この行の位置（行の前）
        let parent = outlineView.parent(forItem: node) as? SidebarNode
        let position = outlineView.childIndex(forItem: node)
        let (target, index) = proposal(at: point, proposedItem: parent, index: position)
        return debugPerform(drag: drag, target: target, index: index, copy: copy)
    }

    private func debugResolve(_ text: String) -> String {
        var text = text
        for section in store.customSections {
            text = text.replacingOccurrences(of: "custom:" + section.name, with: "custom:" + section.id.uuidString)
        }
        if let range = text.range(of: "tag:"), UUID(uuidString: String(text[range.upperBound...])) == nil,
           let tag = tags.tag(named: String(text[range.upperBound...])) {
            text = String(text[..<range.upperBound]) + tag.id.uuidString
        }
        return text
    }

    private func debugPerform(drag: String, target: SidebarNode?, index: Int, copy: Bool) -> String {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("dev.macorn.debug-drop"))
        pasteboard.clearContents()
        pasteboard.setString(debugResolve(drag), forType: SidebarDrag.type)
        let operation = validateDrop(pasteboard, target: target, index: index, copy: copy)
        guard !operation.isEmpty else { return "refused" }
        let (node, retargetIndex) = lastRetarget
        let done = acceptDrop(pasteboard, target: node, index: retargetIndex, copy: copy)
        return done ? "\(operation == .copy ? "copied" : "moved")→\(node?.id ?? "root")@\(retargetIndex)" : "failed"
    }

    /// デバッグ用: ドラッグ＆ドロップを、本物と同じ確認・処理の流れで行う。
    /// drag は "section:tags" "tag:<名前>" "placed:favorites|<パス>"、onto は行の ID か "root"。
    /// 名前で書いたタグ（tag:仕事）とセクション（custom:<名前>）は ID に直す
    func debugDrop(drag: String, onto: String, index: Int, copy: Bool = false) -> String {
        func resolve(_ text: String) -> String {
            var text = text
            for section in store.customSections {
                text = text.replacingOccurrences(of: "custom:" + section.name, with: "custom:" + section.id.uuidString)
            }
            if let range = text.range(of: "tag:"), UUID(uuidString: String(text[range.upperBound...])) == nil,
               let tag = tags.tag(named: String(text[range.upperBound...])) {
                text = String(text[..<range.upperBound]) + tag.id.uuidString
            }
            return text
        }
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("dev.macorn.debug-drop"))
        pasteboard.clearContents()
        pasteboard.setString(resolve(drag), forType: SidebarDrag.type)
        let target: SidebarNode? = onto == "root" ? nil : nodeCache[resolve(onto)]
        if onto != "root", target == nil { return "no-target \(resolve(onto))" }
        let operation = validateDrop(pasteboard, target: target, index: index, copy: copy)
        guard !operation.isEmpty else { return "refused" }
        let (node, retargetIndex) = lastRetarget
        let done = acceptDrop(pasteboard, target: node, index: retargetIndex, copy: copy)
        return done ? "\(operation == .copy ? "copied" : "moved")→\(node?.id ?? "root")@\(retargetIndex)" : "failed"
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
        case .placed(let item, _):
            if let tagID = item.tagID {
                let tag = tags.tag(id: tagID)
                // 階層は見出しや「タグ」の一覧で分かるので、名前は一番下の階層だけを出す（「会社A/案件A」→「案件A」）
                cell.configure(
                    title: item.customName ?? tag?.leafName ?? "（削除されたタグ）",
                    symbol: "tag.fill", tint: NSColor(hex: tag?.color ?? "#8E8E93"),
                    count: tag.map { tags.count(for: $0.id) }, dimmed: tag == nil
                )
            } else if !item.isMissing, !FileTransfer.isDirectory(item.url) {
                cell.configure(title: item.name, image: NSWorkspace.shared.icon(forFile: item.url.path))
            } else {
                let color = tags.folderColor(for: item.url)
                cell.configure(
                    title: item.name,
                    symbol: item.isMissing ? "exclamationmark.triangle" : (color != nil && item.symbol == "folder" ? "folder.fill" : item.symbol),
                    tint: color.map(NSColor.init(hex:)), dimmed: item.isMissing
                )
            }
            cell.toolTip = item.url.isFileURL ? item.url.path : item.tagID.flatMap { tags.tag(id: $0)?.name }
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
            menu.addItem(item("セクションを作る…") { [weak self] in
                guard let self else { return }
                SidebarPrompts.createSection(in: store)
            })
            menu.addItem(item("サイドバーをカスタマイズ…") { SettingsWindowController.shared.show(tab: .sidebar) })
            return
        }
        switch node.kind {
        case .section(let section): sectionMenu(menu, section)
        case .placed(let placed, let section): placedMenu(menu, placed, in: section)
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
        switch section {
        case .tag(let id):
            menu.addItem(item("サイドバーから外す") { [weak self] in self?.store.removeTagSection(id) })
        case .custom(let id):
            menu.addItem(item("名前を変更…") { [weak self] in
                guard let self else { return }
                SidebarPrompts.renameSection(id, in: store)
            })
            menu.addItem(item("セクションを削除…") { [weak self] in
                guard let self else { return }
                SidebarPrompts.deleteSection(id, in: store)
            })
        default:
            menu.addItem(item("「\(section.title)」を隠す") { [weak self] in self?.store.setSection(section, hidden: true) })
        }
        if section == .tags {
            menu.addItem(item("タグを作る…") { [weak self] in
                guard let self else { return }
                SidebarPrompts.createTag(parent: nil, in: tags)
            })
        }
        menu.addItem(.separator())
        menu.addItem(item("この上にセクションを作る…") { [weak self] in
            guard let self else { return }
            SidebarPrompts.createSection(before: section, in: store)
        })
        menu.addItem(item("サイドバーをカスタマイズ…") { SettingsWindowController.shared.show(tab: .sidebar) })
    }

    private func placedMenu(_ menu: NSMenu, _ placed: SidebarItem, in section: SidebarSection) {
        menu.addItem(item("表示名を変更…") { [weak self] in
            guard let self else { return }
            SidebarPrompts.renameItem(placed, in: section, store: store)
        })
        if placed.customName != nil {
            menu.addItem(item(placed.tagID == nil ? "元の名前に戻す" : "タグの名前に戻す") { [weak self] in
                self?.store.renameItem(id: placed.id, in: section, to: "")
            })
        }
        if placed.tagID == nil {
            let reveal = item("Finder で表示") { NSWorkspace.shared.activateFileViewerSelecting([placed.url]) }
            reveal.isEnabled = !placed.isMissing
            menu.addItem(reveal)
        }
        menu.addItem(.separator())
        menu.addItem(item(section == .favorites ? "お気に入りから外す" : "「\(section.title)」から外す") { [weak self] in
            self?.store.removeItem(id: placed.id, from: section)
        })
    }

    private func tagMenu(_ menu: NSMenu, _ tag: Tag) {
        let builtIn = TagStore.isBuiltIn(tag.id)
        let rename = item("名前を変更…") { [weak self] in
            guard let self else { return }
            SidebarPrompts.renameTag(tag, in: tags)
        }
        rename.isEnabled = !builtIn
        menu.addItem(rename)
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
        if !builtIn { menu.addItem(parentMenuItem(for: tag)) }
        menu.addItem(.separator())
        if !builtIn {
            if store.containsFavoriteTag(tag.id) {
                menu.addItem(item("お気に入りから外す") { [weak self] in self?.store.removeFavoriteTag(tag.id) })
            } else {
                menu.addItem(item("お気に入りに置く") { [weak self] in self?.store.addFavoriteTag(tag.id) })
            }
        }
        if !store.customSections.isEmpty {
            menu.addItem(placeMenuItem(for: tag))
        }
        if store.containsTagSection(tag.id) {
            menu.addItem(item("サイドバーのセクションから外す") { [weak self] in self?.store.removeTagSection(tag.id) })
        } else {
            menu.addItem(item("サイドバーのセクションにする") { [weak self] in self?.store.addTagSection(tag.id) })
        }
        menu.addItem(.separator())
        let delete = item("タグを削除…") { [weak self] in
            guard let self else { return }
            SidebarPrompts.deleteTag(tag, in: tags)
        }
        delete.isEnabled = !builtIn
        menu.addItem(delete)
    }

    /// 「セクションに置く」: 自分で作ったセクションへタグを置く（1か所だけなので、ほかに置いてあれば移る）
    private func placeMenuItem(for tag: Tag) -> NSMenuItem {
        let placeItem = NSMenuItem(title: "セクションに置く", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let current = store.placement(ofTag: tag.id)
        for section in store.customSections {
            let entry = item(section.name) { [weak self] in self?.store.placeTag(tag.id, in: .custom(section.id)) }
            entry.state = current == .custom(section.id) ? .on : .off
            submenu.addItem(entry)
        }
        if let current, case .custom = current {
            submenu.addItem(.separator())
            submenu.addItem(item("セクションから外す") { [weak self] in self?.store.removeItem(id: "tag:" + tag.id.uuidString, from: current) })
        }
        placeItem.submenu = submenu
        return placeItem
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
