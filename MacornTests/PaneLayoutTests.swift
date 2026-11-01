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
}
