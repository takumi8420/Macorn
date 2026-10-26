import Foundation
import Testing
@testable import Noxy

struct NavigationHistoryTests {
    private let a = URL(fileURLWithPath: "/a")
    private let b = URL(fileURLWithPath: "/b")
    private let c = URL(fileURLWithPath: "/c")

    @Test func startsWithoutHistory() {
        let history = NavigationHistory(start: a)
        #expect(history.current.path == "/a")
        #expect(!history.canGoBack)
        #expect(!history.canGoForward)
    }

    @Test func backAndForward() {
        var history = NavigationHistory(start: a)
        history.visit(b)
        history.visit(c)

        #expect(history.goBack()?.path == "/b")
        #expect(history.goBack()?.path == "/a")
        #expect(history.goBack() == nil)
        #expect(history.goForward()?.path == "/b")
        #expect(history.current.path == "/b")
        #expect(history.canGoBack)
        #expect(history.canGoForward)
    }

    @Test func visitingClearsForwardHistory() {
        var history = NavigationHistory(start: a)
        history.visit(b)
        history.goBack()
        history.visit(c)
        #expect(!history.canGoForward)
        #expect(history.backStack.map(\.path) == ["/a"])
    }

    @Test func visitingSameFolderDoesNothing() {
        var history = NavigationHistory(start: a)
        history.visit(URL(fileURLWithPath: "/a/"))
        #expect(!history.canGoBack)
    }

    @Test func historyIsCapped() {
        var history = NavigationHistory(start: a)
        for index in 0..<(NavigationHistory.maxCount + 20) {
            history.visit(URL(fileURLWithPath: "/folder\(index)"))
        }
        #expect(history.backStack.count == NavigationHistory.maxCount)
    }
}
