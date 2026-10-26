import Foundation

/// 旧名 noxy のときに保存した設定と履歴を、Macorn に引き継ぐ。
/// アプリ名の変更でバンドル ID（設定の保存先）と履歴のフォルダが変わったため。初回の起動で1回だけ行う。
enum LegacyMigration {
    static let legacyBundleIdentifier = "dev.noxy.Noxy"
    private static let doneKey = "migratedFromNoxy"

    static func runIfNeeded(
        defaults: UserDefaults = .standard,
        supportDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    ) {
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }

        // 設定: 新しい側にまだ無いものだけ写す。一覧の列の保存名は「noxy.〜」から「macorn.〜」に変わった
        if let legacy = defaults.persistentDomain(forName: legacyBundleIdentifier) {
            for (key, value) in legacy {
                let newKey = key.replacingOccurrences(of: "noxy.", with: "macorn.")
                // 前回の画面構成は、消えたフォルダを開かないよう復元処理側で確かめるのでそのまま写してよい
                if defaults.object(forKey: newKey) == nil {
                    defaults.set(value, forKey: newKey)
                }
            }
        }

        // フォルダの履歴: ~/Library/Application Support/noxy → Macorn
        let fileManager = FileManager.default
        let legacyFolder = supportDirectory.appendingPathComponent("noxy")
        let newFolder = supportDirectory.appendingPathComponent("Macorn")
        if fileManager.fileExists(atPath: legacyFolder.path), !fileManager.fileExists(atPath: newFolder.path) {
            try? fileManager.moveItem(at: legacyFolder, to: newFolder)
        }
    }
}
