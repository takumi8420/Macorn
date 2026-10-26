import Foundation

/// 「戻る / 進む」の履歴。
struct NavigationHistory: Equatable {
    static let maxCount = 100

    private(set) var current: URL
    private(set) var backStack: [URL] = []
    private(set) var forwardStack: [URL] = []

    init(start: URL) {
        current = start.standardizedFileURL
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    /// 新しいフォルダへ移動する。同じフォルダなら何もしない。
    mutating func visit(_ url: URL) {
        let url = url.standardizedFileURL
        guard url.path != current.path else { return }
        backStack.append(current)
        if backStack.count > Self.maxCount {
            backStack.removeFirst(backStack.count - Self.maxCount)
        }
        current = url
        forwardStack.removeAll()
    }

    @discardableResult
    mutating func goBack() -> URL? {
        guard let previous = backStack.popLast() else { return nil }
        forwardStack.append(current)
        current = previous
        return previous
    }

    @discardableResult
    mutating func goForward() -> URL? {
        guard let next = forwardStack.popLast() else { return nil }
        backStack.append(current)
        current = next
        return next
    }

    /// 履歴を増やさずに今の場所だけ差し替える（表示中のフォルダが消えたときなど）。
    mutating func replaceCurrent(with url: URL) {
        current = url.standardizedFileURL
    }
}
