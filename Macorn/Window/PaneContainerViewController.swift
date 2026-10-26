import AppKit
import Observation

/// 1つのタブの画面構成（保存・復元用）。
struct PaneLayout: Codable, Equatable {
    /// 左から順に各画面のフォルダ。1つなら1画面、2つなら2画面
    var paths: [String]
    var activeIndex: Int
    /// 2画面の境界線の位置（左の画面の幅の割合）
    var dividerFraction: Double?

    init(paths: [String], activeIndex: Int = 0, dividerFraction: Double? = nil) {
        self.paths = paths
        self.activeIndex = activeIndex
        self.dividerFraction = dividerFraction
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

/// 2画面表示（要件 4章）。1つまたは2つの画面（FileBrowserViewController）を左右に並べる。
final class PaneContainerViewController: NSSplitViewController {
    static let narrowWidth: CGFloat = 700

    private(set) var panes: [FileBrowserViewController] = []
    private(set) var activeIndex = 0
    let model: WindowModel
    weak var paneDelegate: FileBrowserDelegate?
    /// 操作対象の画面が変わったとき、または操作対象の画面が移動したとき
    var onActivePaneChanged: (() -> Void)?

    private var pendingDividerFraction: Double?
    /// 幅が狭いために一時的に隠している画面（要件 P-08）
    private var isTemporarilyCollapsed = false

    init(layout: PaneLayout) {
        let urls = layout.paths.prefix(2).map(TagLocation.location(from:))
        let first = FileBrowserViewController(url: urls.first ?? FileManager.default.homeDirectoryForCurrentUser)
        model = WindowModel(activePane: first.state)
        super.init(nibName: nil, bundle: nil)
        splitView = PaneSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        (splitView as? PaneSplitView)?.onDoubleClickDivider = { [weak self] in self?.equalizePanes() }

        addPane(first)
        if urls.count > 1 {
            let second = FileBrowserViewController(url: urls[1])
            second.focusesOnFirstAppear = layout.activeIndex == 1
            first.focusesOnFirstAppear = layout.activeIndex != 1
            addPane(second)
            pendingDividerFraction = layout.dividerFraction ?? 0.5
        }
        setActive(index: min(max(layout.activeIndex, 0), panes.count - 1), focus: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var activePane: FileBrowserViewController { panes[activeIndex] }
    var otherPane: FileBrowserViewController? { isSplit ? panes[1 - activeIndex] : nil }
    var isSplit: Bool { panes.count == 2 }

    var layout: PaneLayout {
        var fraction: Double?
        if isSplit, splitView.bounds.width > 0, let first = splitView.subviews.first {
            fraction = Double(first.frame.width / splitView.bounds.width)
        }
        return PaneLayout(paths: panes.map { TagLocation.savedString(for: $0.state.currentURL) }, activeIndex: activeIndex, dividerFraction: fraction)
    }

    private func addPane(_ pane: FileBrowserViewController) {
        pane.delegate = paneDelegate
        pane.onActivate = { [weak self, weak pane] in
            guard let self, let pane, let index = panes.firstIndex(where: { $0 === pane }) else { return }
            setActive(index: index, focus: false)
        }
        pane.onSwitchPane = { [weak self] in self?.switchActivePane() }
        let item = NSSplitViewItem(viewController: pane)
        item.minimumThickness = 280
        item.canCollapse = true
        addSplitViewItem(item)
        panes.append(pane)
        updatePaneStates()
    }

    func setPaneDelegate(_ delegate: FileBrowserDelegate) {
        paneDelegate = delegate
        panes.forEach { $0.delegate = delegate }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if let fraction = pendingDividerFraction, splitView.bounds.width > 0 {
            pendingDividerFraction = nil
            splitView.setPosition(splitView.bounds.width * fraction, ofDividerAt: 0)
        }
        updateNarrowLayout()
    }

    // MARK: - 2画面の切り替え

    func toggleSplit() {
        isSplit ? closeSplit() : openSplit(at: activePane.state.currentURL)
    }

    /// 2画面にする。右の画面には指定のフォルダを開く（要件 P-01）。
    func openSplit(at url: URL) {
        guard !isSplit else { return }
        let pane = FileBrowserViewController(url: url)
        pane.focusesOnFirstAppear = false
        addPane(pane)
        equalizePanes()
        onActivePaneChanged?()
    }

    /// 1画面に戻す。操作対象だった画面を残す（要件 P-07）。
    func closeSplit() {
        guard isSplit else { return }
        let removedIndex = 1 - activeIndex
        let removed = panes[removedIndex]
        removed.tearDown()
        removeSplitViewItem(splitViewItems[removedIndex])
        panes.remove(at: removedIndex)
        activeIndex = 0
        isTemporarilyCollapsed = false
        updatePaneStates()
        activePane.focusList()
        onActivePaneChanged?()
    }

    func switchActivePane() {
        guard isSplit else { return }
        setActive(index: 1 - activeIndex, focus: true)
    }

    func setActive(index: Int, focus: Bool) {
        guard panes.indices.contains(index) else { return }
        let changed = index != activeIndex || model.activePane !== panes[index].state
        activeIndex = index
        updatePaneStates()
        if isTemporarilyCollapsed { updateNarrowLayout(force: true) }
        if focus { activePane.focusList() }
        if changed { onActivePaneChanged?() }
    }

    private func updatePaneStates() {
        for (index, pane) in panes.enumerated() {
            pane.state.isActive = index == activeIndex
            pane.state.isInSplit = isSplit
        }
        model.activePane = activePane.state
    }

    func equalizePanes() {
        guard isSplit else { return }
        view.layoutSubtreeIfNeeded()
        let width = splitView.bounds.width
        if width > 0 {
            splitView.setPosition(width / 2, ofDividerAt: 0)
        } else {
            pendingDividerFraction = 0.5
        }
    }

    /// ウィンドウが狭いときは、操作対象でない画面を一時的に隠す（要件 P-08）。
    private func updateNarrowLayout(force: Bool = false) {
        guard isSplit else { return }
        let narrow = view.bounds.width > 0 && view.bounds.width < Self.narrowWidth
        guard narrow != isTemporarilyCollapsed || force else { return }
        isTemporarilyCollapsed = narrow
        for (index, item) in splitViewItems.enumerated() {
            item.isCollapsed = narrow && index != activeIndex
        }
    }

    // MARK: - 画面間の操作

    /// 反対側の画面へコピー・移動する（要件 P-10, P-11）。
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

    /// 反対側の画面を、操作対象の画面と同じフォルダにする（要件 P-12）。
    func syncOtherPane() {
        otherPane?.navigate(to: activePane.state.currentURL)
    }

    /// 左右のフォルダを入れ替える（要件 P-13）。
    func swapPanes() {
        guard isSplit else { return }
        let left = panes[0].state.currentURL
        let right = panes[1].state.currentURL
        panes[0].navigate(to: right)
        panes[1].navigate(to: left)
    }

    /// 選択中のフォルダを左または右の画面で開く（要件 P-14）。1画面なら2画面にする。
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
        let pane = panes[min(index, panes.count - 1)]
        pane.navigate(to: target, selecting: selection)
        setActive(index: panes.firstIndex { $0 === pane } ?? 0, focus: true)
    }
}

/// 境界線をダブルクリックすると左右を同じ幅に戻す（要件 P-06）。
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
