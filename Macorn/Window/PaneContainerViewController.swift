import AppKit
import Observation

/// 画面の並び（入れ子）。保存・復元用。
/// 画面1つ（pane。タブが1つ）・タブがいくつかある画面（tabs）か、いくつかの並びを左右（vertical = true）または上下に並べたまとまり（group）。
indirect enum PaneTreeLayout: Codable, Equatable {
    case pane(path: String)
    /// タブがいくつかある画面。selected は選んでいるタブの番号
    case tabs(paths: [String], selected: Int)
    case group(vertical: Bool, children: [PaneTreeLayout], fractions: [Double]?)

    /// 左上から順に並べた、各画面で選んでいるタブのフォルダ
    var paths: [String] {
        switch self {
        case .pane(let path): [path]
        case .tabs(let paths, let selected): paths.isEmpty ? [] : [paths[min(max(selected, 0), paths.count - 1)]]
        case .group(_, let children, _): children.flatMap(\.paths)
        }
    }

    /// すべてのタブのフォルダ（左上の画面から順、画面の中ではタブの順）
    var allPaths: [String] {
        switch self {
        case .pane(let path): [path]
        case .tabs(let paths, _): paths
        case .group(_, let children, _): children.flatMap(\.allPaths)
        }
    }

    /// 条件に合うタブだけを残す。何も残らなければ nil。1つだけになったまとまりは中身に置き換える
    func pruned(keeping keep: (String) -> Bool) -> PaneTreeLayout? {
        switch self {
        case .pane(let path):
            return keep(path) ? self : nil
        case .tabs(let paths, let selected):
            let kept = paths.indices.filter { keep(paths[$0]) }
            if kept.isEmpty { return nil }
            if kept.count == 1 { return .pane(path: paths[kept[0]]) }
            return .tabs(paths: kept.map { paths[$0] }, selected: kept.firstIndex(of: selected) ?? 0)
        case .group(let vertical, let children, let fractions):
            let kept = children.compactMap { $0.pruned(keeping: keep) }
            if kept.isEmpty { return nil }
            if kept.count == 1 { return kept[0] }
            return .group(vertical: vertical, children: kept, fractions: kept.count == children.count ? fractions : nil)
        }
    }
}

/// 1つのウィンドウの画面構成（保存・復元用）。
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

    /// 消えたフォルダのタブを除いたもの。何も残らなければ nil
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

/// タブを置く先
enum PaneTabDrop {
    /// その画面のタブの列の、index の位置へ
    case insert(PaneTabsController, Int)
    /// その画面の上下左右に、新しい画面を作って置く
    case split(PaneTabsController, PaneDropZone)
}

/// 複数画面表示（要件 4章）。画面（PaneTabsController。タブを持つ）を、左右・上下に自由に分けて並べる。
/// 並びは入れ子のまとまり（PaneGroupController）で持つ。いちばん外のまとまり（root）はいつもある。
/// VS Code のように、タブをドラッグして、ほかの画面のタブの列や、画面の上下左右へ動かせる。
final class PaneContainerViewController: NSViewController {
    static let narrowWidth: CGFloat = 700
    /// 1つのウィンドウで開ける画面の数の上限（タブの数ではない）
    static let maxPanes = 6

    private var root: PaneGroupController
    /// 操作対象のタブ（操作対象の画面で選んでいるタブ）
    private var active: FileBrowserViewController
    /// 直前に操作対象だった画面。「もう一方の画面」（コピー・移動の送り先など）にする
    private weak var previous: FileBrowserViewController?
    let model: WindowModel
    weak var paneDelegate: FileBrowserDelegate?
    /// 操作対象の画面が変わったとき、または操作対象の画面が移動したとき
    var onActivePaneChanged: (() -> Void)?
    /// タブを閉じたとき（「閉じたタブを開く」のため）
    var onTabClosed: ((URL) -> Void)?

    /// 幅が狭いために一時的に隠している画面があるか（要件 P-08）
    private var isTemporarilyCollapsed = false
    /// プレビューを最大化している画面（ほかの画面は畳んでいる）
    private weak var maximizedPane: FileBrowserViewController?
    /// プレビューの最大化を始めた・やめたとき（サイドバーを畳む・戻すため）
    var onPreviewMaximizeChanged: ((Bool) -> Void)?
    /// ドラッグ中に、画面の上に重ねて置き場所を示すもの
    private var dropOverlay: PaneDropOverlay?

    init(layout: PaneLayout) {
        let tree = layout.resolvedTree
        let placeholder = FileBrowserViewController(url: TagLocation.location(from: tree.allPaths.first ?? NSHomeDirectory()))
        active = placeholder
        model = WindowModel(activePane: placeholder.state)
        root = PaneGroupController(vertical: true)
        super.init(nibName: nil, bundle: nil)

        // 並びを組み立てる。最初のタブは placeholder を使う
        var created: [FileBrowserViewController] = []
        var groups: [PaneTabsController] = []
        func makeBrowser(_ path: String) -> FileBrowserViewController {
            let browser = created.isEmpty ? placeholder : FileBrowserViewController(url: TagLocation.location(from: path))
            created.append(browser)
            configure(browser)
            return browser
        }
        func makeTabs(_ paths: [String], selected: Int) -> PaneTabsController {
            let paths = paths.isEmpty ? [NSHomeDirectory()] : paths
            let group = PaneTabsController(tabs: paths.map(makeBrowser), selected: selected)
            configureGroup(group)
            groups.append(group)
            return group
        }
        func build(_ node: PaneTreeLayout, into parent: PaneGroupController) {
            switch node {
            case .pane(let path):
                parent.append(makeTabs([path], selected: 0))
            case .tabs(let paths, let selected):
                parent.append(makeTabs(paths, selected: selected))
            case .group(let vertical, let children, let fractions):
                let child = makeGroup(vertical: vertical)
                for node in children { build(node, into: child) }
                child.pendingFractions = fractions ?? Self.equalFractions(children.count)
                parent.append(child)
            }
        }
        if case .group(let vertical, let children, let fractions) = tree {
            root.setVertical(vertical)
            for node in children { build(node, into: root) }
            root.pendingFractions = fractions ?? Self.equalFractions(children.count)
        } else {
            build(tree, into: root)
        }
        root.onDoubleClickDivider = { [weak self] in self?.root.equalize() }

        let index = min(max(layout.activeIndex, 0), groups.count - 1)
        active = groups[index].selected ?? placeholder
        for browser in created { browser.focusesOnFirstAppear = browser === active }
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

    // MARK: - 画面とタブの一覧

    /// 左上から順に並べた画面
    var tabGroups: [PaneTabsController] { root.tabGroups }
    /// 左上から順に並べた、各画面で選んでいるタブ
    var panes: [FileBrowserViewController] { root.panes }
    /// すべてのタブ（選んでいないタブも）
    var allBrowsers: [FileBrowserViewController] { tabGroups.flatMap(\.tabs) }
    var activePane: FileBrowserViewController { active }
    var activeIndex: Int { panes.firstIndex { $0 === active } ?? 0 }
    var isSplit: Bool { tabGroups.count > 1 }
    var canSplit: Bool { tabGroups.count < Self.maxPanes }

    /// そのタブを持つ画面
    func tabGroup(of browser: FileBrowserViewController) -> PaneTabsController? {
        tabGroups.first { $0.contains(browser) }
    }

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
        pane.onPreviewMaximizeChanged = { [weak self, weak pane] maximized in
            guard let self, let pane else { return }
            setMaximizedPane(maximized ? pane : nil)
        }
        pane.onClosePane = { [weak self, weak pane] in
            // ボタンを押した処理が終わってから閉じる（押したボタンを含む画面ごと外すため）
            DispatchQueue.main.async {
                guard let self, let pane, let group = self.tabGroup(of: pane) else { return }
                self.close(group)
            }
        }
    }

    private func configureGroup(_ group: PaneTabsController) {
        group.onSelectTab = { [weak self] browser in self?.activate(browser, focus: true) }
        group.onCloseTab = { [weak self] browser in
            guard let self else { return }
            // ウィンドウの最後のタブなら、ウィンドウごと閉じる
            if !closeTab(browser) { view.window?.performClose(nil) }
        }
        group.onBeginTabDrag = { [weak self] browser, event, view in
            self?.beginTabDrag(of: browser, event: event, from: view)
        }
        group.onNewTab = { [weak self, weak group] in
            guard let self, let group, let selected = group.selected else { return }
            openTab(at: selected.state.currentURL, in: group)
        }
    }

    func setPaneDelegate(_ delegate: FileBrowserDelegate) {
        paneDelegate = delegate
        allBrowsers.forEach { $0.delegate = delegate }
    }

    private static func equalFractions(_ count: Int) -> [Double] {
        Array(repeating: 1 / Double(max(count, 1)), count: count)
    }

    private func makeGroup(vertical: Bool) -> PaneGroupController {
        let group = PaneGroupController(vertical: vertical)
        group.onDoubleClickDivider = { [weak group] in group?.equalize() }
        return group
    }

    // MARK: - タブ

    /// 新しいタブを開いて選ぶ（⌘T・「新しいタブで開く」など）。group を省くと操作対象の画面に、選んでいるタブのすぐ右へ足す
    @discardableResult
    func openTab(at url: URL, in group: PaneTabsController? = nil, select: Bool = true) -> FileBrowserViewController {
        endPreviewMaximize()
        let group = group ?? tabGroup(of: active) ?? tabGroups[0]
        let browser = FileBrowserViewController(url: url)
        browser.focusesOnFirstAppear = select
        configure(browser)
        let index = (group.selected.flatMap { group.index(of: $0) } ?? group.tabs.count - 1) + 1
        group.insert(browser, at: index, select: select)
        if select {
            activate(browser, focus: true)
        } else {
            updatePaneStates()
        }
        return browser
    }

    /// タブを閉じる。ウィンドウの最後の1つは閉じずに false を返す（呼び出し側がウィンドウを閉じる）
    @discardableResult
    func closeTab(_ browser: FileBrowserViewController) -> Bool {
        guard let group = tabGroup(of: browser) else { return false }
        if group.tabs.count == 1 {
            // 画面の最後のタブなら、画面ごと閉じる
            guard isSplit else { return false }
            onTabClosed?(browser.state.currentURL)
            close(group)
            return true
        }
        endPreviewMaximize()
        onTabClosed?(browser.state.currentURL)
        let wasActive = browser === active
        browser.tearDown()
        group.remove(browser)
        if wasActive, let next = group.selected {
            active = next
            previous = nil
        }
        updatePaneStates()
        if wasActive {
            active.focusList()
            onActivePaneChanged?()
        }
        return true
    }

    /// ⌘W：操作対象のタブを閉じる。ウィンドウの最後のタブなら false
    func closeActiveTab() -> Bool {
        closeTab(active)
    }

    /// 操作対象の画面で、隣のタブへ（offset が 1 なら右、-1 なら左。端からは反対の端へ）
    func selectAdjacentTab(_ offset: Int) {
        guard let group = tabGroup(of: active), group.tabs.count > 1, let index = group.index(of: active) else { return }
        let count = group.tabs.count
        activate(group.tabs[((index + offset) % count + count) % count], focus: true)
    }

    /// 操作対象の画面のタブの数
    var activeTabCount: Int { tabGroup(of: active)?.tabs.count ?? 1 }

    // MARK: - 分ける・閉じる

    /// プレビューを最大化した画面だけを残して、ほかの画面を畳む。nil で元に戻す
    private func setMaximizedPane(_ pane: FileBrowserViewController?) {
        if let current = maximizedPane, current !== pane {
            maximizedPane = nil
            current.setPreviewMaximized(false)
        }
        maximizedPane = pane
        if isSplit {
            if let pane {
                root.collapse(keeping: pane)
            } else {
                root.collapse(keeping: nil)
                isTemporarilyCollapsed = false
                updateNarrowLayout()
            }
        }
        onPreviewMaximizeChanged?(pane != nil)
    }

    /// 画面を分ける・閉じる前に、プレビューの最大化をやめる
    private func endPreviewMaximize() {
        maximizedPane?.setPreviewMaximized(false)
    }

    /// ⌘\：1画面なら右に分ける（要件 P-01）。分けているなら、操作対象の画面だけを残して1画面に戻す（要件 P-07）
    func toggleSplit() {
        if isSplit { closeOtherPanes() } else { split(.right) }
    }

    /// 操作対象の画面を、右または下に分ける。新しい画面には同じフォルダ（指定があればそのフォルダ）を開く
    @discardableResult
    func split(_ direction: PaneSplitDirection, at url: URL? = nil, focusNew: Bool = false) -> FileBrowserViewController? {
        guard canSplit, let target = tabGroup(of: active) else { NSSound.beep(); return nil }
        endPreviewMaximize()
        let pane = FileBrowserViewController(url: url ?? active.state.currentURL)
        pane.focusesOnFirstAppear = focusNew
        configure(pane)
        let group = PaneTabsController(tabs: [pane])
        configureGroup(group)
        place(group, beside: target, vertical: direction.isVertical, after: true)
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

    /// 新しい画面を、target の画面の左右（vertical）または上下に置く。after なら右・下
    private func place(_ group: PaneTabsController, beside target: PaneTabsController, vertical: Bool, after: Bool) {
        guard let parent = root.group(containing: target), let index = parent.index(of: target) else { return }
        if parent.count == 1 || parent.isVertical == vertical {
            // 同じ向きに並んでいるなら、すぐ隣に足す
            parent.setVertical(vertical)
            parent.insert(group, at: index + (after ? 1 : 0))
            parent.equalize()
        } else {
            // 向きが違うときは、target を新しいまとまりに入れ替えて、その中で並べる
            let fractions = parent.currentFractions
            let child = makeGroup(vertical: vertical)
            parent.remove(target)
            child.append(after ? target : group)
            child.append(after ? group : target)
            parent.insert(child, at: index)
            parent.apply(fractions: fractions)
            child.equalize()
        }
    }

    /// 2画面にする。新しい画面には指定のフォルダを開く（コマンドパレットなどから）
    func openSplit(at url: URL) {
        guard !isSplit else { return }
        split(.right, at: url)
    }

    /// 操作対象の画面を閉じる（その画面のタブもすべて閉じる）。最後の1つは閉じない
    func closeActivePane() {
        guard let group = tabGroup(of: active) else { return }
        close(group)
    }

    func close(_ pane: FileBrowserViewController) {
        guard let group = tabGroup(of: pane) else { return }
        close(group)
    }

    private func close(_ group: PaneTabsController) {
        guard isSplit, let parent = root.group(containing: group) else { NSSound.beep(); return }
        endPreviewMaximize()
        let index = tabGroups.firstIndex { $0 === group } ?? 0
        let containedActive = group.contains(active)
        group.tabs.forEach { $0.tearDown() }
        parent.remove(group)
        normalize(parent)
        if containedActive {
            let remaining = panes
            active = (previous.flatMap { candidate in remaining.first { $0 === candidate } })
                ?? remaining[min(index, remaining.count - 1)]
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
        guard isSplit, let keep = tabGroup(of: active) else { return }
        endPreviewMaximize()
        for group in tabGroups where group !== keep {
            group.tabs.forEach { $0.tearDown() }
        }
        root.removeAll()
        root.setVertical(true)
        root.append(keep)
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

    // MARK: - タブを動かす（VS Code のように、ドラッグで並びを組み替える）

    /// タブを、ほかの画面のタブの列（insert）か、画面の上下左右（split）へ動かす。動かしたら true
    @discardableResult
    func moveTab(_ browser: FileBrowserViewController, to drop: PaneTabDrop) -> Bool {
        guard let source = tabGroup(of: browser) else { return false }
        switch drop {
        case .insert(let target, let index):
            guard tabGroups.contains(where: { $0 === target }) else { return false }
            endPreviewMaximize()
            if target === source {
                source.move(browser, to: index)
                if let moved = source.index(of: browser) { source.select(moved) }
            } else {
                source.remove(browser)
                removeIfEmpty(source)
                target.insert(browser, at: index, select: true)
            }
        case .split(let target, let zone):
            if zone == .center { return moveTab(browser, to: .insert(target, target.tabs.count)) }
            guard tabGroups.contains(where: { $0 === target }) else { return false }
            // 1つしかないタブを、自分の画面の端へ置いても変わらない
            if target === source && source.tabs.count == 1 { return false }
            // 画面が増えるときは、上限を超えない
            guard source.tabs.count == 1 || canSplit else { NSSound.beep(); return false }
            endPreviewMaximize()
            source.remove(browser)
            removeIfEmpty(source)
            let group = PaneTabsController(tabs: [])
            configureGroup(group)
            group.insert(browser, at: 0, select: true)
            place(group, beside: target, vertical: zone == .left || zone == .right, after: zone == .right || zone == .bottom)
        }
        if browser !== active { previous = active }
        active = browser
        isTemporarilyCollapsed = false
        updateNarrowLayout(force: true)
        updatePaneStates()
        active.focusList()
        onActivePaneChanged?()
        return true
    }

    /// タブがなくなった画面を外す
    private func removeIfEmpty(_ group: PaneTabsController) {
        guard group.tabs.isEmpty, let parent = root.group(containing: group) else { return }
        parent.remove(group)
        normalize(parent)
    }

    /// 操作対象の画面を含む並びの向きを、左右 ⇄ 上下に切り替える（2画面なら、横並びと縦並びの切り替え）
    func rotateActiveGroup() {
        guard isSplit, let tabs = tabGroup(of: active), let group = root.group(containing: tabs), group.count > 1 else {
            NSSound.beep()
            return
        }
        endPreviewMaximize()
        let fractions = group.currentFractions
        group.setVertical(!group.isVertical)
        group.view.layoutSubtreeIfNeeded()
        group.apply(fractions: fractions)
        isTemporarilyCollapsed = false
        updateNarrowLayout(force: true)
        active.focusList()
        onActivePaneChanged?()
    }

    /// タブのドラッグを始める
    private func beginTabDrag(of browser: FileBrowserViewController, event: NSEvent, from handle: NSView) {
        guard dropOverlay == nil else { return }
        endPreviewMaximize()
        let overlay = PaneDropOverlay(frame: view.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.resolve = { [weak self, weak browser, weak overlay] point in
            guard let self, let browser, let overlay,
                  let found = tabDropTarget(at: point, in: overlay, dragging: browser) else { return nil }
            return (found.rect, { [weak self] in
                // ドラッグを終える処理が済んでから動かす（つまんだタブごと付け替えるため）
                DispatchQueue.main.async { self?.moveTab(browser, to: found.drop) }
            })
        }
        view.addSubview(overlay)
        dropOverlay = overlay

        let item = NSPasteboardItem()
        item.setString("tab", forType: PaneDropOverlay.pasteboardType)
        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        let image = Self.snapshot(of: handle)
        // ドラッグはタブの列から始める（タブの列はタブを出し直しても残るので、ドラッグの途中で外れない）。
        // 画面の切り替えはタブを押したときに済んでいるので、ここでは並びを触らない
        let source = handle.superview ?? handle
        let point = source.convert(event.locationInWindow, from: nil)
        draggingItem.setDraggingFrame(
            NSRect(x: point.x - image.size.width / 2, y: point.y - image.size.height / 2, width: image.size.width, height: image.size.height),
            contents: image
        )
        let session = source.beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    /// 指したところに置いたときの行き先と、色を付ける範囲。
    /// タブの列なら並びの間（細い線）、画面の中なら上下左右の半分（新しい画面）か、真ん中（その画面のタブにする）
    private func tabDropTarget(at point: NSPoint, in overlay: NSView, dragging browser: FileBrowserViewController)
        -> (rect: NSRect, drop: PaneTabDrop)? {
        guard let source = tabGroup(of: browser) else { return nil }
        for group in tabGroups where group.view.window != nil && !group.view.isHiddenOrHasHiddenAncestor {
            let bar = group.tabBar
            let barRect = overlay.convert(bar.bounds, from: bar)
            if barRect.width > 1, barRect.contains(point) {
                let index = bar.insertionIndex(atX: bar.convert(point, from: overlay).x)
                if group === source, let from = source.index(of: browser), index == from || index == from + 1 { return nil }
                let x = bar.insertionX(for: index)
                let marker = overlay.convert(NSRect(x: x - 1.5, y: 0, width: 3, height: bar.bounds.height), from: bar)
                return (marker, .insert(group, index))
            }
            let rect = overlay.convert(group.contentView.bounds, from: group.contentView)
            guard rect.width > 1, rect.height > 1, rect.contains(point) else { continue }
            let zone = PaneDropZone.zone(x: (point.x - rect.minX) / rect.width, yFromTop: (rect.maxY - point.y) / rect.height)
            if zone == .center {
                guard group !== source else { return nil }
                return (rect, .insert(group, group.tabs.count))
            }
            if group === source && source.tabs.count == 1 { return nil }
            if source.tabs.count > 1 && !canSplit { return nil }
            return (zone.highlight(in: rect), .split(group, zone))
        }
        return nil
    }

    #if DEBUG
    /// 開発用：place は left・right・top・bottom・center か、タブの列の位置の番号
    private func debugDrop(group index: Int, place: String) -> PaneTabDrop? {
        let groups = tabGroups
        guard groups.indices.contains(index) else { return nil }
        if let position = Int(place) { return .insert(groups[index], position) }
        let zones: [String: PaneDropZone] = ["left": .left, "right": .right, "top": .top, "bottom": .bottom, "center": .center]
        return zones[place].map { .split(groups[index], $0) }
    }

    /// 開発用：group 番目の画面の tab 番目のタブを、ドラッグして置いたのと同じように動かす
    func debugMoveTab(group: Int, tab: Int, to target: Int, place: String) -> Bool {
        let groups = tabGroups
        guard groups.indices.contains(group), groups[group].tabs.indices.contains(tab),
              let drop = debugDrop(group: target, place: place) else { return false }
        return moveTab(groups[group].tabs[tab], to: drop)
    }

    /// 開発用：ドラッグせずに、置くときの色付けを出す（group が nil なら消す）
    func debugShowDropHighlight(group index: Int?, place: String) {
        dropOverlay?.removeFromSuperview()
        dropOverlay = nil
        guard let index, tabGroups.indices.contains(index) else { return }
        let group = tabGroups[index]
        let overlay = PaneDropOverlay(frame: view.bounds)
        overlay.autoresizingMask = [.width, .height]
        view.addSubview(overlay)
        // 画面の位置は、ウィンドウに置いてから測る
        if let position = Int(place) {
            let x = group.tabBar.insertionX(for: position)
            overlay.highlight = overlay.convert(NSRect(x: x - 1.5, y: 0, width: 3, height: group.tabBar.bounds.height), from: group.tabBar)
        } else {
            let zones: [String: PaneDropZone] = ["left": .left, "right": .right, "top": .top, "bottom": .bottom, "center": .center]
            let rect = overlay.convert(group.contentView.bounds, from: group.contentView)
            overlay.highlight = (zones[place] ?? .center).highlight(in: rect)
        }
        dropOverlay = overlay
    }
    #endif

    /// ドラッグ中にカーソルについてくる画像
    private static func snapshot(of view: NSView) -> NSImage {
        let bounds = view.bounds
        let scale = min(1, 240 / max(bounds.width, 1))
        let size = NSSize(width: max(bounds.width * scale, 40), height: max(bounds.height * scale, 20))
        let image = NSImage(size: size)
        if let rep = view.bitmapImageRepForCachingDisplay(in: bounds) {
            view.cacheDisplay(in: bounds, to: rep)
            image.lockFocus()
            NSColor.controlBackgroundColor.setFill()
            NSRect(origin: .zero, size: size).fill()
            rep.draw(in: NSRect(origin: .zero, size: size))
            Theme.shared.accentColor.setStroke()
            NSBezierPath(rect: NSRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)).stroke()
            image.unlockFocus()
        }
        return image
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

    /// そのタブを操作対象にする。選んでいないタブなら、その画面で選ぶ
    func activate(_ pane: FileBrowserViewController, focus: Bool) {
        if let group = tabGroup(of: pane), group.selected !== pane, let index = group.index(of: pane) {
            group.select(index)
        }
        // 最大化していない画面へ移ったら（Tab など）、最大化をやめる
        if let maximizedPane, maximizedPane !== pane { maximizedPane.setPreviewMaximized(false) }
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
        for pane in allBrowsers {
            pane.state.isActive = pane === active
            pane.state.isInSplit = split
        }
        for group in tabGroups { group.isActiveGroup = group.contains(active) }
        model.activePane = active.state
    }

    func equalizePanes() {
        root.equalizeAll()
    }

    /// ウィンドウが狭いときは、操作対象でない画面を一時的に隠す（要件 P-08）。
    private func updateNarrowLayout(force: Bool = false) {
        guard isSplit, maximizedPane == nil else { return }
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

extension PaneContainerViewController: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dropOverlay?.removeFromSuperview()
        dropOverlay = nil
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
    var tabGroups: [PaneTabsController] {
        members.flatMap { child -> [PaneTabsController] in
            if let tabs = child as? PaneTabsController { return [tabs] }
            return (child as? PaneGroupController)?.tabGroups ?? []
        }
    }

    /// このまとまりの中の、各画面で選んでいるタブ（左上から順）
    var panes: [FileBrowserViewController] {
        tabGroups.compactMap(\.selected)
    }

    func setVertical(_ vertical: Bool) {
        guard splitView.isVertical != vertical else { return }
        splitView.isVertical = vertical
        for item in splitViewItems { item.minimumThickness = vertical ? 240 : 160 }
        splitView.adjustSubviews()
    }

    func index(of controller: NSViewController) -> Int? {
        members.firstIndex { $0 === controller }
    }

    /// 指定の画面をすぐ中に持つまとまり
    func group(containing tabs: PaneTabsController) -> PaneGroupController? {
        if index(of: tabs) != nil { return self }
        for case let child as PaneGroupController in members {
            if let found = child.group(containing: tabs) { return found }
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

    /// 指定のタブを含む要素だけを残して、ほかを畳む。nil ならすべて広げる（要件 P-08）。
    /// 畳むのは左右に並べたまとまりだけ。上下に並べたまとまりは、幅が狭くても困らないので畳まず、中だけを見る
    func collapse(keeping pane: FileBrowserViewController?) {
        if !isVertical {
            for item in splitViewItems {
                if item.isCollapsed { item.isCollapsed = false }
                (item.viewController as? PaneGroupController)?.collapse(keeping: pane)
            }
            return
        }
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
                (child as? PaneTabsController)?.contains(target)
                    ?? ((child as? PaneGroupController)?.tabGroups.contains { $0.contains(target) } ?? false)
            } ?? true
            item.isCollapsed = !containsPane
            (child as? PaneGroupController)?.collapse(keeping: pane)
        }
    }

    /// 保存用の並び
    var layoutTree: PaneTreeLayout {
        let nodes = members.compactMap { child -> PaneTreeLayout? in
            if let tabs = child as? PaneTabsController {
                let paths = tabs.tabs.map { TagLocation.savedString(for: $0.state.currentURL) }
                if paths.count == 1 { return .pane(path: paths[0]) }
                return paths.isEmpty ? nil : .tabs(paths: paths, selected: tabs.selectedIndex)
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
