import AppKit
import Observation

/// 画面の並び（入れ子）。保存・復元用。
/// 画面1つ（pane）か、いくつかの並びを左右（vertical = true）または上下に並べたまとまり（group）。
indirect enum PaneTreeLayout: Codable, Equatable {
    case pane(path: String)
    case group(vertical: Bool, children: [PaneTreeLayout], fractions: [Double]?)

    /// 左上から順に並べた、各画面のフォルダ
    var paths: [String] {
        switch self {
        case .pane(let path): [path]
        case .group(_, let children, _): children.flatMap(\.paths)
        }
    }

    /// 条件に合う画面だけを残す。画面が1つも残らなければ nil。1つだけになったまとまりは中身に置き換える
    func pruned(keeping keep: (String) -> Bool) -> PaneTreeLayout? {
        switch self {
        case .pane(let path):
            return keep(path) ? self : nil
        case .group(let vertical, let children, let fractions):
            let kept = children.compactMap { $0.pruned(keeping: keep) }
            if kept.isEmpty { return nil }
            if kept.count == 1 { return kept[0] }
            return .group(vertical: vertical, children: kept, fractions: kept.count == children.count ? fractions : nil)
        }
    }
}

/// 1つのタブの画面構成（保存・復元用）。
struct PaneLayout: Codable, Equatable {
    /// 左上から順に各画面のフォルダ（以前の形式との互換のため。並びは tree が持つ）
    var paths: [String]
    /// 操作対象の画面の番号（paths の順）
    var activeIndex: Int
    /// 2画面の境界線の位置（左の画面の幅の割合）。tree がないとき（以前の形式）に使う
    var dividerFraction: Double?
    /// 画面の並び（入れ子）。ないときは paths を左右に並べる
    var tree: PaneTreeLayout?

    init(paths: [String], activeIndex: Int = 0, dividerFraction: Double? = nil, tree: PaneTreeLayout? = nil) {
        self.paths = tree?.paths ?? paths
        self.activeIndex = activeIndex
        self.dividerFraction = dividerFraction
        self.tree = tree
    }

    /// 画面の並び。tree がなければ paths を左右に並べたもの
    var resolvedTree: PaneTreeLayout {
        if let tree { return tree }
        let leaves = paths.map { PaneTreeLayout.pane(path: $0) }
        if leaves.count <= 1 { return leaves.first ?? .pane(path: FileManager.default.homeDirectoryForCurrentUser.path) }
        let fractions = dividerFraction.map { [$0, 1 - $0] }
        return .group(vertical: true, children: Array(leaves.prefix(2)), fractions: leaves.count == 2 ? fractions : nil)
    }

    /// 消えたフォルダの画面を除いたもの。画面が1つも残らなければ nil
    func pruned(keeping keep: (String) -> Bool) -> PaneLayout? {
        guard let tree = resolvedTree.pruned(keeping: keep) else { return nil }
        let active = tree.paths.count == paths.count ? activeIndex : 0
        return PaneLayout(paths: tree.paths, activeIndex: active, tree: tree)
    }
}

/// サイドバーなどが「今の操作対象の画面」を知るためのもの。
@Observable
final class WindowModel {
    var activePane: PaneState

    init(activePane: PaneState) {
        self.activePane = activePane
    }
}

/// 画面を分ける向き
enum PaneSplitDirection {
    /// 右に分ける（左右に並べる）
    case right
    /// 下に分ける（上下に並べる）
    case down

    var isVertical: Bool { self == .right }
}

/// 複数画面表示（要件 4章）。画面（FileBrowserViewController）を、左右・上下に自由に分けて並べる。
/// 並びは入れ子のまとまり（PaneGroupController）で持つ。いちばん外のまとまり（root）はいつもある。
final class PaneContainerViewController: NSViewController {
    static let narrowWidth: CGFloat = 700
    /// 1つのタブで開ける画面の数の上限
    static let maxPanes = 6

    private var root: PaneGroupController
    private var active: FileBrowserViewController
    /// 直前に操作対象だった画面。「もう一方の画面」（コピー・移動の送り先など）にする
    private weak var previous: FileBrowserViewController?
    let model: WindowModel
    weak var paneDelegate: FileBrowserDelegate?
    /// 操作対象の画面が変わったとき、または操作対象の画面が移動したとき
    var onActivePaneChanged: (() -> Void)?

    /// 幅が狭いために一時的に隠している画面があるか（要件 P-08）
    private var isTemporarilyCollapsed = false

    init(layout: PaneLayout) {
        let tree = layout.resolvedTree
        let placeholder = FileBrowserViewController(url: TagLocation.location(from: tree.paths.first ?? NSHomeDirectory()))
        active = placeholder
        model = WindowModel(activePane: placeholder.state)
        root = PaneGroupController(vertical: true)
        super.init(nibName: nil, bundle: nil)

        // 並びを組み立てる。最初の画面は placeholder を使う
        var created: [FileBrowserViewController] = []
        func make(_ path: String) -> FileBrowserViewController {
            let pane = created.isEmpty ? placeholder : FileBrowserViewController(url: TagLocation.location(from: path))
            created.append(pane)
            configure(pane)
            return pane
        }
        func build(_ node: PaneTreeLayout, into group: PaneGroupController) {
            switch node {
            case .pane(let path):
                group.append(make(path))
            case .group(let vertical, let children, let fractions):
                let child = PaneGroupController(vertical: vertical)
                child.onDoubleClickDivider = { [weak child] in child?.equalize() }
                for node in children { build(node, into: child) }
                child.pendingFractions = fractions ?? Self.equalFractions(children.count)
                group.append(child)
            }
        }
        switch tree {
        case .pane(let path):
            root.append(make(path))
        case .group(let vertical, let children, let fractions):
            root.setVertical(vertical)
            for node in children { build(node, into: root) }
            root.pendingFractions = fractions ?? Self.equalFractions(children.count)
        }
        root.onDoubleClickDivider = { [weak self] in self?.root.equalize() }

        let index = min(max(layout.activeIndex, 0), created.count - 1)
        active = created[index]
        for pane in created { pane.focusesOnFirstAppear = pane === active }
        updatePaneStates()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView()
        addChild(root)
        root.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(root.view)
        NSLayoutConstraint.activate([
            root.view.topAnchor.constraint(equalTo: container.topAnchor),
            root.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            root.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            root.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        view = container
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateNarrowLayout()
    }

    // MARK: - 画面の一覧

    /// 左上から順に並べた画面
    var panes: [FileBrowserViewController] { root.panes }
    var activePane: FileBrowserViewController { active }
    var activeIndex: Int { panes.firstIndex { $0 === active } ?? 0 }
    var isSplit: Bool { panes.count > 1 }
    var canSplit: Bool { panes.count < Self.maxPanes }

    /// もう一方の画面。直前に操作対象だった画面があればそれ、なければ並びで次の画面
    var otherPane: FileBrowserViewController? {
        let all = panes
        guard all.count > 1 else { return nil }
        if let previous, previous !== active, all.contains(where: { $0 === previous }) { return previous }
        let index = all.firstIndex { $0 === active } ?? 0
        return all[(index + 1) % all.count]
    }

    var layout: PaneLayout {
        PaneLayout(paths: [], activeIndex: activeIndex, tree: root.layoutTree)
    }

    private func configure(_ pane: FileBrowserViewController) {
        pane.delegate = paneDelegate
        pane.onActivate = { [weak self, weak pane] in
            guard let self, let pane else { return }
            activate(pane, focus: false)
        }
        pane.onSwitchPane = { [weak self] in self?.switchActivePane() }
        pane.onClosePane = { [weak self, weak pane] in
            // ボタンを押した処理が終わってから閉じる（押したボタンを含む画面ごと外すため）
            DispatchQueue.main.async {
                guard let self, let pane else { return }
                self.close(pane)
            }
        }
    }

    func setPaneDelegate(_ delegate: FileBrowserDelegate) {
        paneDelegate = delegate
        panes.forEach { $0.delegate = delegate }
    }

    private static func equalFractions(_ count: Int) -> [Double] {
        Array(repeating: 1 / Double(max(count, 1)), count: count)
    }

    // MARK: - 分ける・閉じる

    /// ⌘\：1画面なら右に分ける（要件 P-01）。分けているなら、操作対象の画面だけを残して1画面に戻す（要件 P-07）
    func toggleSplit() {
        if isSplit { closeOtherPanes() } else { split(.right) }
    }

    /// 操作対象の画面を、右または下に分ける。新しい画面には同じフォルダ（指定があればそのフォルダ）を開く
    @discardableResult
    func split(_ direction: PaneSplitDirection, at url: URL? = nil, focusNew: Bool = false) -> FileBrowserViewController? {
        guard canSplit, let group = root.group(containing: active) else { NSSound.beep(); return nil }
        let pane = FileBrowserViewController(url: url ?? active.state.currentURL)
        pane.focusesOnFirstAppear = focusNew
        configure(pane)
        let index = group.index(of: active) ?? 0
        if group.count == 1 || group.isVertical == direction.isVertical {
            // 同じ向きに並んでいるなら、すぐ隣に足す
            group.setVertical(direction.isVertical)
            group.insert(pane, at: index + 1)
            group.equalize()
        } else {
            // 向きが違うときは、操作対象の画面を新しいまとまりに入れ替えて、その中で分ける
            let fractions = group.currentFractions
            let child = PaneGroupController(vertical: direction.isVertical)
            child.onDoubleClickDivider = { [weak child] in child?.equalize() }
            group.remove(active)
            child.append(active)
            child.append(pane)
            group.insert(child, at: index)
            group.apply(fractions: fractions)
            child.equalize()
        }
        isTemporarilyCollapsed = false
        updateNarrowLayout(force: true)
        if focusNew {
            activate(pane, focus: true)
        } else {
            updatePaneStates()
            active.focusList()
            onActivePaneChanged?()
        }
        return pane
    }

    /// 2画面にする。新しい画面には指定のフォルダを開く（コマンドパレットなどから）
    func openSplit(at url: URL) {
        guard !isSplit else { return }
        split(.right, at: url)
    }

    /// 操作対象の画面を閉じる。最後の1つは閉じない
    func closeActivePane() {
        close(active)
    }

    func close(_ pane: FileBrowserViewController) {
        guard isSplit, let group = root.group(containing: pane) else { NSSound.beep(); return }
        let all = panes
        let index = all.firstIndex { $0 === pane } ?? 0
        pane.tearDown()
        group.remove(pane)
        normalize(group)
        if pane === active {
            let remaining = panes
            let next = (previous.flatMap { candidate in remaining.first { $0 === candidate } })
                ?? remaining[min(index, remaining.count - 1)]
            active = next
            previous = nil
        }
        isTemporarilyCollapsed = false
        updateNarrowLayout(force: true)
        updatePaneStates()
        active.focusList()
        onActivePaneChanged?()
    }

    /// 操作対象の画面だけを残して1画面に戻す（要件 P-07）
    func closeOtherPanes() {
        guard isSplit else { return }
        for pane in panes where pane !== active { pane.tearDown() }
        root.removeAll()
        root.setVertical(true)
        root.append(active)
        previous = nil
        isTemporarilyCollapsed = false
        updatePaneStates()
        active.focusList()
        onActivePaneChanged?()
    }

    /// 中身が1つだけになったまとまりを、その中身に置き換える
    private func normalize(_ group: PaneGroupController) {
        if group === root {
            // いちばん外のまとまりの中身が1つのまとまりだけなら、その中身を引き上げる
            if root.count == 1, let only = root.members.first as? PaneGroupController {
                let fractions = only.currentFractions
                let children = only.members
                children.forEach(only.remove)
                root.removeAll()
                root.setVertical(only.isVertical)
                children.forEach(root.append)
                root.apply(fractions: fractions)
            }
            return
        }
        guard let parent = group.parentGroup, let index = parent.index(of: group) else { return }
        if group.count == 1, let only = group.members.first {
            let fractions = parent.currentFractions
            group.remove(only)
            parent.remove(group)
            if let onlyGroup = only as? PaneGroupController, onlyGroup.isVertical == parent.isVertical {
                // 同じ向きのまとまりは、外のまとまりに平らに並べる
                let inner = onlyGroup.members
                inner.forEach(onlyGroup.remove)
                for (offset, child) in inner.enumerated() { parent.insert(child, at: index + offset) }
                parent.equalize()
            } else {
                parent.insert(only, at: index)
                parent.apply(fractions: fractions)
            }
            normalize(parent)
        } else if group.count == 0 {
            parent.remove(group)
            normalize(parent)
        }
    }

    // MARK: - 操作対象の画面

    /// Tab：並びで次の画面へ
    func switchActivePane() {
        let all = panes
        guard all.count > 1 else { return }
        let index = all.firstIndex { $0 === active } ?? 0
        activate(all[(index + 1) % all.count], focus: true)
    }

    func setActive(index: Int, focus: Bool) {
        let all = panes
        guard all.indices.contains(index) else { return }
        activate(all[index], focus: focus)
    }

    func activate(_ pane: FileBrowserViewController, focus: Bool) {
        let changed = pane !== active || model.activePane !== pane.state
        if pane !== active { previous = active }
        active = pane
        updatePaneStates()
        if isTemporarilyCollapsed { updateNarrowLayout(force: true) }
        if focus { active.focusList() }
        if changed { onActivePaneChanged?() }
    }

    private func updatePaneStates() {
        let split = isSplit
        for pane in panes {
            pane.state.isActive = pane === active
            pane.state.isInSplit = split
        }
        model.activePane = active.state
    }

    func equalizePanes() {
        root.equalizeAll()
    }

    /// ウィンドウが狭いときは、操作対象でない画面を一時的に隠す（要件 P-08）。
    private func updateNarrowLayout(force: Bool = false) {
        guard isSplit else { return }
        let narrow = view.bounds.width > 0 && view.bounds.width < Self.narrowWidth
        guard narrow != isTemporarilyCollapsed || force else { return }
        isTemporarilyCollapsed = narrow
        root.collapse(keeping: narrow ? active : nil)
    }

    // MARK: - 画面間の操作

    /// もう一方の画面へコピー・移動する（要件 P-10, P-11）。
    func transferSelectionToOtherPane(mode: FileOperationManager.TransferMode) {
        guard let other = otherPane else { return }
        let urls = activePane.selectedURLs
        guard !urls.isEmpty else { return }
        let destination = other.state.currentURL
        let window = view.window
        Task {
            if Preferences.confirmPaneTransfer {
                let confirmed = await FileOperationManager.shared.confirmTransfer(
                    count: urls.count, destination: destination, mode: mode, window: window
                )
                guard confirmed else { return }
            }
            let results = await FileOperationManager.shared.transfer(urls, to: destination, mode: mode, window: window)
            other.refreshAfterChange(selecting: results)
        }
    }

    /// もう一方の画面を、操作対象の画面と同じフォルダにする（要件 P-12）。
    func syncOtherPane() {
        otherPane?.navigate(to: activePane.state.currentURL)
    }

    /// 操作対象の画面と、もう一方の画面のフォルダを入れ替える（要件 P-13）。
    func swapPanes() {
        guard let other = otherPane else { return }
        let mine = active.state.currentURL
        let theirs = other.state.currentURL
        active.navigate(to: theirs)
        other.navigate(to: mine)
    }

    /// 選択中のフォルダを左（いちばん左上）または右（2番目）の画面で開く（要件 P-14）。1画面なら2画面にする。
    func openSelectionInPane(index: Int) {
        let source = activePane
        let selected = source.selectedNodes
        var target = source.state.currentURL
        var selection: URL?
        if selected.count == 1, let node = selected.first {
            if node.entry.isFolder {
                target = node.url
            } else {
                target = node.url.deletingLastPathComponent()
                selection = node.url
            }
        }
        if !isSplit { openSplit(at: source.state.currentURL) }
        let all = panes
        let pane = all[min(index, all.count - 1)]
        pane.navigate(to: target, selecting: selection)
        activate(pane, focus: true)
    }
}

/// 画面またはまとまりを、左右・上下に並べるまとまり。
final class PaneGroupController: NSSplitViewController {
    weak var parentGroup: PaneGroupController?
    var onDoubleClickDivider: (() -> Void)?
    /// 表示されて大きさが決まったら当てる、各要素の大きさの割合
    var pendingFractions: [Double]?
    /// 狭いために畳む前の、各要素の大きさの割合
    private var fractionsBeforeCollapse: [Double]?

    init(vertical: Bool) {
        super.init(nibName: nil, bundle: nil)
        let splitView = PaneSplitView()
        splitView.isVertical = vertical
        splitView.dividerStyle = .thin
        splitView.onDoubleClickDivider = { [weak self] in self?.onDoubleClickDivider?() }
        self.splitView = splitView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isVertical: Bool { splitView.isVertical }
    /// 画面どうしの区切り線を掴みやすくする
    override func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect, forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
        let rect = super.splitView(splitView, effectiveRect: proposedEffectiveRect, forDrawnRect: drawnRect, ofDividerAt: dividerIndex)
        return DividerGrab.rect(rect, vertical: splitView.isVertical)
    }

    var count: Int { splitViewItems.count }
    var members: [NSViewController] { splitViewItems.map(\.viewController) }

    /// このまとまりの中の画面（入れ子も含めて、左上から順）
    var panes: [FileBrowserViewController] {
        members.flatMap { child -> [FileBrowserViewController] in
            if let pane = child as? FileBrowserViewController { return [pane] }
            return (child as? PaneGroupController)?.panes ?? []
        }
    }

    func setVertical(_ vertical: Bool) {
        guard splitView.isVertical != vertical else { return }
        splitView.isVertical = vertical
        splitView.adjustSubviews()
    }

    func index(of controller: NSViewController) -> Int? {
        members.firstIndex { $0 === controller }
    }

    /// 指定の画面をすぐ中に持つまとまり
    func group(containing pane: FileBrowserViewController) -> PaneGroupController? {
        if index(of: pane) != nil { return self }
        for case let child as PaneGroupController in members {
            if let found = child.group(containing: pane) { return found }
        }
        return nil
    }

    func append(_ controller: NSViewController) {
        insert(controller, at: count)
    }

    func insert(_ controller: NSViewController, at index: Int) {
        let item = NSSplitViewItem(viewController: controller)
        item.minimumThickness = isVertical ? 240 : 160
        item.canCollapse = true
        insertSplitViewItem(item, at: min(max(index, 0), count))
        (controller as? PaneGroupController)?.parentGroup = self
    }

    func remove(_ controller: NSViewController) {
        guard let item = splitViewItems.first(where: { $0.viewController === controller }) else { return }
        removeSplitViewItem(item)
        (controller as? PaneGroupController)?.parentGroup = nil
    }

    func removeAll() {
        members.forEach(remove)
    }

    /// 各要素の大きさの割合
    var currentFractions: [Double] {
        let total = isVertical ? splitView.bounds.width : splitView.bounds.height
        guard total > 0 else { return pendingFractions ?? [] }
        return splitView.arrangedSubviews.map { Double((isVertical ? $0.frame.width : $0.frame.height) / total) }
    }

    func apply(fractions: [Double]) {
        guard fractions.count == count, count > 1 else { equalize(); return }
        let total = isVertical ? splitView.bounds.width : splitView.bounds.height
        guard total > 0 else { pendingFractions = fractions; return }
        let thickness = splitView.dividerThickness
        let available = total - thickness * CGFloat(count - 1)
        let sum = fractions.reduce(0, +)
        var position: CGFloat = 0
        for index in 0..<(count - 1) {
            position += available * CGFloat(fractions[index] / max(sum, 0.0001))
            splitView.setPosition(position + thickness * CGFloat(index), ofDividerAt: index)
        }
    }

    /// 要素を同じ大きさにそろえる（要件 P-06）
    func equalize() {
        guard count > 1 else { return }
        view.layoutSubtreeIfNeeded()
        apply(fractions: Array(repeating: 1, count: count))
    }

    /// 入れ子も含めて、すべてのまとまりを同じ大きさにそろえる
    func equalizeAll() {
        equalize()
        for case let child as PaneGroupController in members { child.equalizeAll() }
    }

    /// 指定の画面を含む要素だけを残して、ほかを畳む。nil ならすべて広げる（要件 P-08）
    func collapse(keeping pane: FileBrowserViewController?) {
        let wasCollapsed = splitViewItems.contains(where: \.isCollapsed)
        if pane != nil, !wasCollapsed, count > 1 { fractionsBeforeCollapse = currentFractions }
        defer {
            // 広げ直したら、畳む前の大きさに戻す
            if pane == nil, wasCollapsed, let fractions = fractionsBeforeCollapse {
                fractionsBeforeCollapse = nil
                view.layoutSubtreeIfNeeded()
                apply(fractions: fractions)
            }
        }
        for item in splitViewItems {
            let child = item.viewController
            let containsPane = pane.map { target in
                child === target || ((child as? PaneGroupController)?.panes.contains { $0 === target } ?? false)
            } ?? true
            item.isCollapsed = !containsPane
            (child as? PaneGroupController)?.collapse(keeping: pane)
        }
    }

    /// 保存用の並び
    var layoutTree: PaneTreeLayout {
        let nodes = members.compactMap { child -> PaneTreeLayout? in
            if let pane = child as? FileBrowserViewController {
                return .pane(path: TagLocation.savedString(for: pane.state.currentURL))
            }
            return (child as? PaneGroupController)?.layoutTree
        }
        if nodes.count == 1 { return nodes[0] }
        // 狭いために畳んでいる間の大きさは残さない（同じ大きさで開き直す）
        let fractions = splitViewItems.contains(where: \.isCollapsed) ? nil : currentFractions
        return .group(vertical: isVertical, children: nodes, fractions: fractions?.count == nodes.count ? fractions : nil)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if let fractions = pendingFractions, (isVertical ? splitView.bounds.width : splitView.bounds.height) > 0 {
            pendingFractions = nil
            apply(fractions: fractions)
        }
    }
}

/// 境界線をダブルクリックすると、並んだ画面を同じ大きさに戻す（要件 P-06）。
final class PaneSplitView: NSSplitView {
    var onDoubleClickDivider: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClickDivider?()
            return
        }
        super.mouseDown(with: event)
    }
}
