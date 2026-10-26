import Foundation
import Observation

/// 表示中フォルダが開けなかったときの内容。
struct PaneError: Equatable {
    var message: String
    var needsPermission: Bool
}

/// 1つの画面（ペイン）の状態。SwiftUI のパスバー・ステータスバー・サイドバーがこれを見て表示を変える。
@Observable
final class PaneState {
    var history: NavigationHistory
    var itemCount = 0
    var selectedCount = 0
    var availableCapacity: Int64?
    var isLoading = false
    var isEditingPath = false
    var error: PaneError?
    /// 2画面表示のとき、操作対象の画面かどうか（要件 P-03）
    var isActive = true
    var isInSplit = false
    /// Git リポジトリの中ならブランチ名（要件 T-20）
    var gitBranch: String?
    var gitChangeCount = 0
    /// 絞り込み（要件 S-04）
    var isFiltering = false
    var filterText = ""
    var visibleCount = 0

    var currentURL: URL { history.current }

    init(url: URL) {
        history = NavigationHistory(start: url)
    }
}
