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
    /// 表示中のフォルダを含む Git リポジトリのルート
    var gitRepositoryRoot: URL?
    /// リポジトリの名前（「持ち主/リポジトリ」）と、リモートを Web で開く URL・サービスの名前
    var gitRepositoryName: String?
    var gitRemoteWebURL: URL?
    var gitRemoteServiceName: String?
    /// ウィンドウの下に内蔵ターミナルを出しているか（ステータスバーのボタンの見た目用）
    var isTerminalVisible = false
    var gitChangeCount = 0
    /// 絞り込み（要件 S-04）
    var isFiltering = false
    /// 絞り込みの欄をいつも出している（設定）
    var isFilterBarAlwaysShown = Preferences.alwaysShowFilterBar
    var filterText = ""
    var visibleCount = 0
    /// 絞り込みで、サブフォルダの中も探す
    var filterIncludesSubfolders = Preferences.filterIncludesSubfolders
    /// サブフォルダを探している最中
    var isSearchingSubfolders = false
    /// 見つかった数などが上限に達し、途中で探すのをやめた
    var isSubfolderSearchTruncated = false
    /// 今の絞り込みが、サブフォルダまで探した結果を出している
    var isShowingSubfolderResults = false

    var currentURL: URL { history.current }

    init(url: URL) {
        history = NavigationHistory(start: url)
    }
}
