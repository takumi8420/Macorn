import Foundation

/// 設定の保存先。ふだんは標準の場所。
/// 自動操作で MACORN_DEFAULTS_SUITE を指定したときは、そのスイートを使い、利用者の設定を読み書きしない
/// （宣伝用の撮影などで、毎回同じ見た目から始め、普段の設定を汚さないため）
enum AppDefaults {
    static let store: UserDefaults = {
        if let suite = ProcessInfo.processInfo.environment["MACORN_DEFAULTS_SUITE"], let defaults = UserDefaults(suiteName: suite) {
            return defaults
        }
        return .standard
    }()
}
