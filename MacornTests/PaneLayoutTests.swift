import AppKit
import Foundation
import Testing
@testable import Macorn

/// 複数画面の並び（入れ子）の保存・復元
struct PaneLayoutTests {
    private let twoByTwo = PaneTreeLayout.group(vertical: true, children: [
        .group(vertical: false, children: [.pane(path: "/a"), .pane(path: "/b")], fractions: [0.5, 0.5]),
        .group(vertical: false, children: [.pane(path: "/c"), .pane(path: "/d")], fractions: [0.3, 0.7]),
    ], fractions: [0.4, 0.6])

    @Test func pathsAreInReadingOrder() {
        #expect(twoByTwo.paths == ["/a", "/b", "/c", "/d"])
        #expect(PaneLayout(paths: [], tree: twoByTwo).paths == ["/a", "/b", "/c", "/d"])
    }

    @Test func roundTripsThroughJSON() throws {
        let layout = PaneLayout(paths: [], activeIndex: 2, tree: twoByTwo)
        let decoded = try JSONDecoder().decode(PaneLayout.self, from: JSONEncoder().encode(layout))
        #expect(decoded == layout)
        #expect(decoded.resolvedTree == twoByTwo)
    }

    /// 以前の形式（左右2画面だけ）を読み込んでも、左右に並べて開く
    @Test func readsOldTwoPaneFormat() throws {
        let json = #"{"paths":["/a","/b"],"activeIndex":1,"dividerFraction":0.3}"#
        let layout = try JSONDecoder().decode(PaneLayout.self, from: Data(json.utf8))
        #expect(layout.tree == nil)
        #expect(layout.resolvedTree == .group(vertical: true, children: [.pane(path: "/a"), .pane(path: "/b")], fractions: [0.3, 0.7]))
        #expect(PaneLayout(paths: ["/a"]).resolvedTree == .pane(path: "/a"))
    }

    /// 消えたフォルダの画面は除き、1つになったまとまりは中身に置き換える
    @Test func pruningRemovesMissingFolders() {
        let layout = PaneLayout(paths: [], activeIndex: 3, tree: twoByTwo)
        let pruned = layout.pruned { $0 != "/b" }
        #expect(pruned?.tree == .group(vertical: true, children: [
            .pane(path: "/a"),
            .group(vertical: false, children: [.pane(path: "/c"), .pane(path: "/d")], fractions: [0.3, 0.7]),
        ], fractions: [0.4, 0.6]))
        // 画面が減ったら、操作対象は最初の画面にする
        #expect(pruned?.activeIndex == 0)
        #expect(layout.pruned { _ in false } == nil)
        #expect(layout.pruned { _ in true }?.activeIndex == 3)
    }

    /// 保存した入れ子の並びから画面を組み立て直すと、同じ並びになる
    @MainActor @Test func rebuildsPanesFromTree() {
        let tree = PaneTreeLayout.group(vertical: true, children: [
            .pane(path: "/"),
            .group(vertical: false, children: [.pane(path: "/tmp"), .pane(path: "/usr")], fractions: nil),
        ], fractions: nil)
        let container = PaneContainerViewController(layout: PaneLayout(paths: [], activeIndex: 2, tree: tree))
        _ = container.view
        #expect(container.panes.map(\.state.currentURL.path) == ["/", "/tmp", "/usr"])
        #expect(container.activeIndex == 2)
        #expect(container.isSplit)
        // 大きさの割合を除けば、並びは同じ
        guard case .group(let vertical, let children, _) = container.layout.tree else {
            Issue.record("まとまりになっていない")
            return
        }
        #expect(vertical)
        #expect(children.count == 2)
        guard case .group(let innerVertical, let inner, _) = children[1] else {
            Issue.record("入れ子のまとまりがない")
            return
        }
        #expect(!innerVertical)
        #expect(inner.map(\.paths) == [["/tmp"], ["/usr"]])

        // 操作対象の画面を閉じると、1つになったまとまりは中身に置き換わる
        container.closeActivePane()
        #expect(container.panes.map(\.state.currentURL.path) == ["/", "/tmp"])
        guard case .group(let afterVertical, let after, _) = container.layout.tree else {
            Issue.record("まとまりになっていない")
            return
        }
        #expect(afterVertical)
        #expect(after.map(\.paths) == [["/"], ["/tmp"]])
        container.panes.forEach { $0.tearDown() }
    }

    /// ドラッグの置き場所：真ん中の四角は入れ替え、それ以外はいちばん近い辺
    @Test func dropZoneIsNearestEdgeOrCenter() {
        #expect(PaneDropZone.zone(x: 0.1, yFromTop: 0.5) == .left)
        #expect(PaneDropZone.zone(x: 0.9, yFromTop: 0.4) == .right)
        #expect(PaneDropZone.zone(x: 0.5, yFromTop: 0.05) == .top)
        #expect(PaneDropZone.zone(x: 0.6, yFromTop: 0.95) == .bottom)
        #expect(PaneDropZone.zone(x: 0.5, yFromTop: 0.5) == .center)
        #expect(PaneDropZone.zone(x: 0.35, yFromTop: 0.65) == .center)
        // 色を付ける範囲は、置いたあとにその画面が来る半分（左下が原点）
        let rect = NSRect(x: 0, y: 0, width: 200, height: 100)
        #expect(PaneDropZone.top.highlight(in: rect) == NSRect(x: 0, y: 50, width: 200, height: 50))
        #expect(PaneDropZone.right.highlight(in: rect) == NSRect(x: 100, y: 0, width: 100, height: 100))
    }

    /// 並びから、大きさの割合を除いた形（"|" は左右、"-" は上下、"[a *b]" はタブ。* は選んでいるタブ）
    private func shape(_ tree: PaneTreeLayout?) -> String {
        switch tree {
        case .pane(let path)?: String(path.dropFirst())
        case .tabs(let paths, let selected)?:
            "[" + paths.enumerated().map { ($0.offset == selected ? "*" : "") + String($0.element.dropFirst()) }.joined(separator: " ") + "]"
        case .group(let vertical, let children, _)?:
            "(" + children.map { shape($0) }.joined(separator: vertical ? "|" : "-") + ")"
        case nil: "nil"
        }
    }

    /// タブのある画面の保存・消えたフォルダの除き方
    @Test func tabsLayoutPrunesAndRoundTrips() throws {
        let tree = PaneTreeLayout.group(vertical: true, children: [
            .tabs(paths: ["/a", "/b", "/c"], selected: 2),
            .pane(path: "/d"),
        ], fractions: nil)
        #expect(tree.paths == ["/c", "/d"])
        #expect(tree.allPaths == ["/a", "/b", "/c", "/d"])
        let layout = PaneLayout(paths: [], activeIndex: 1, tree: tree)
        #expect(try JSONDecoder().decode(PaneLayout.self, from: JSONEncoder().encode(layout)) == layout)
        // 選んでいたタブが消えたら、最初のタブを選ぶ。1つになったら、ふつうの画面に戻す
        #expect(shape(tree.pruned { $0 != "/c" }) == "([*a b]|d)")
        #expect(shape(tree.pruned { $0 != "/a" }) == "([b *c]|d)")
        #expect(shape(tree.pruned { $0 == "/b" || $0 == "/d" }) == "(b|d)")
    }

    /// VS Code のように、タブをほかの画面のタブの列や、画面の上下左右へ動かす
    @MainActor @Test func movesTabsLikeVSCode() {
        let tree = PaneTreeLayout.tabs(paths: ["/a", "/b"], selected: 0)
        let container = PaneContainerViewController(layout: PaneLayout(paths: [], activeIndex: 0, tree: tree))
        _ = container.view
        defer { container.allBrowsers.forEach { $0.tearDown() } }
        func tab(_ path: String) -> FileBrowserViewController {
            container.allBrowsers.first { $0.state.currentURL.path == path }!
        }
        #expect(shape(container.layout.tree) == "[*a b]")
        #expect(!container.isSplit)

        // タブ b を、画面の下へ → 上下2画面になる
        #expect(container.moveTab(tab("/b"), to: .split(container.tabGroups[0], .bottom)))
        #expect(shape(container.layout.tree) == "(a-b)")
        #expect(container.activePane === tab("/b"))

        // 1つしかないタブを自分の画面の端へ置いても変わらない
        #expect(!container.moveTab(tab("/b"), to: .split(container.tabGroups[1], .left)))

        // 新しいタブを下の画面に足して、上の画面のタブの列の先頭へ動かす
        let c = container.openTab(at: URL(fileURLWithPath: "/usr"))
        #expect(container.tabGroups[1].tabs.count == 2)
        #expect(container.moveTab(c, to: .insert(container.tabGroups[0], 0)))
        #expect(shape(container.layout.tree) == "([*usr a]-b)")

        // 下の画面の最後のタブを、上の画面の真ん中へ → 下の画面はなくなり、上の画面のタブになる
        #expect(container.moveTab(tab("/b"), to: .insert(container.tabGroups[0], 2)))
        #expect(shape(container.layout.tree) == "[usr a *b]")
        #expect(!container.isSplit)

        // 同じ画面の中で並べ替える
        #expect(container.moveTab(tab("/b"), to: .insert(container.tabGroups[0], 0)))
        #expect(shape(container.layout.tree) == "[*b usr a]")

        // タブを閉じると隣のタブを選び、最後の1つは閉じない
        #expect(container.closeTab(tab("/b")))
        #expect(shape(container.layout.tree) == "[*usr a]")
        #expect(container.closeTab(tab("/a")))
        #expect(!container.closeTab(tab("/usr")))
    }

    /// タブを押して選び直しても、タブの部品は作り直さない（作り直すと、押したタブからドラッグを始められない）
    @MainActor @Test func tabBarKeepsItemViewsWhenReloaded() {
        let tree = PaneTreeLayout.tabs(paths: ["/a", "/b"], selected: 0)
        let container = PaneContainerViewController(layout: PaneLayout(paths: [], activeIndex: 0, tree: tree))
        _ = container.view
        defer { container.allBrowsers.forEach { $0.tearDown() } }
        let bar = container.tabGroups[0].tabBar
        let before = bar.subviews.compactMap { $0 as? PaneTabItemView }
        #expect(before.count == 2)
        container.activate(container.allBrowsers[1], focus: false)
        container.tabGroups[0].reloadTabBar()
        let after = bar.subviews.compactMap { $0 as? PaneTabItemView }
        #expect(after.count == 2)
        #expect(zip(before, after).allSatisfy { $0 === $1 })
    }

    /// 隣のタブへの切り替えと、選んでいないタブを操作対象にしたとき
    @MainActor @Test func selectsAdjacentTabs() {
        let tree = PaneTreeLayout.tabs(paths: ["/a", "/b", "/c"], selected: 0)
        let container = PaneContainerViewController(layout: PaneLayout(paths: [], activeIndex: 0, tree: tree))
        _ = container.view
        defer { container.allBrowsers.forEach { $0.tearDown() } }
        container.selectAdjacentTab(-1)
        #expect(container.activePane.state.currentURL.path == "/c")
        container.selectAdjacentTab(1)
        #expect(container.activePane.state.currentURL.path == "/a")
        container.activate(container.allBrowsers[1], focus: false)
        #expect(shape(container.layout.tree) == "[a *b c]")
    }

    /// 縦・横の切り替え：2画面なら左右 ⇄ 上下
    @MainActor @Test func rotatesActiveGroup() {
        let tree = PaneTreeLayout.group(vertical: true, children: [.pane(path: "/a"), .pane(path: "/b")], fractions: nil)
        let container = PaneContainerViewController(layout: PaneLayout(paths: [], activeIndex: 1, tree: tree))
        _ = container.view
        defer { container.panes.forEach { $0.tearDown() } }
        container.rotateActiveGroup()
        #expect(shape(container.layout.tree) == "(a-b)")
        container.rotateActiveGroup()
        #expect(shape(container.layout.tree) == "(a|b)")
    }
}
