import Foundation

extension Notification.Name {
    /// 隠しファイル表示・並び順が変わったとき。全ウィンドウに反映する。
    static let noxyDisplayPreferencesChanged = Notification.Name("noxyDisplayPreferencesChanged")
}

/// アプリ全体の設定（要件 V-05, V-08: フォルダをまたいでも勝手に変わらない）。
enum Preferences {
    private enum Key {
        static let showHiddenFiles = "showHiddenFiles"
        static let sortKey = "sortKey"
        static let sortAscending = "sortAscending"
        static let confirmPaneTransfer = "confirmPaneTransfer"
        static let terminal = "terminalBundleIdentifier"
        static let editor = "editorBundleIdentifier"
        static let terminalNewTab = "openTerminalInNewTab"
        static let folderSizes = "calculateFolderSizes"
        static let vim = "vimKeyBindings"
    }

    private static var defaults: UserDefaults { .standard }

    static var showHiddenFiles: Bool {
        get { defaults.bool(forKey: Key.showHiddenFiles) }
        set {
            defaults.set(newValue, forKey: Key.showHiddenFiles)
            NotificationCenter.default.post(name: .noxyDisplayPreferencesChanged, object: nil)
        }
    }

    /// F5 / F6 で反対側へコピー・移動する前に確認するか（要件 4.2）
    static var confirmPaneTransfer: Bool {
        get { defaults.object(forKey: Key.confirmPaneTransfer) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.confirmPaneTransfer) }
    }

    /// ターミナル・エディタ（要件 T-02, T-05）。nil なら入っている候補の先頭
    static var terminalBundleIdentifier: String? {
        get { defaults.string(forKey: Key.terminal) }
        set { defaults.set(newValue, forKey: Key.terminal) }
    }

    static var editorBundleIdentifier: String? {
        get { defaults.string(forKey: Key.editor) }
        set { defaults.set(newValue, forKey: Key.editor) }
    }

    /// ターミナルを新しいタブで開く（要件 T-03。対応しているアプリのみ）
    static var openTerminalInNewTab: Bool {
        get { defaults.bool(forKey: Key.terminalNewTab) }
        set { defaults.set(newValue, forKey: Key.terminalNewTab) }
    }

    /// フォルダの合計サイズを計算して表示する（要件 V-09）
    static var calculateFolderSizes: Bool {
        get { defaults.object(forKey: Key.folderSizes) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.folderSizes) }
    }

    /// Vim 風のキー操作（要件 K-02）
    static var vimKeyBindings: Bool {
        get { defaults.bool(forKey: Key.vim) }
        set { defaults.set(newValue, forKey: Key.vim) }
    }

    static var sort: FileSort {
        get {
            let key = defaults.string(forKey: Key.sortKey).flatMap(FileSortKey.init(rawValue:)) ?? .name
            let ascending = defaults.object(forKey: Key.sortAscending) as? Bool ?? true
            return FileSort(key: key, ascending: ascending)
        }
        set {
            guard newValue != sort else { return }
            defaults.set(newValue.key.rawValue, forKey: Key.sortKey)
            defaults.set(newValue.ascending, forKey: Key.sortAscending)
            NotificationCenter.default.post(name: .noxyDisplayPreferencesChanged, object: nil)
        }
    }
}
