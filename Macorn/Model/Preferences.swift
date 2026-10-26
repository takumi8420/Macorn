import Foundation

extension Notification.Name {
    /// 隠しファイル表示・並び順が変わったとき。全ウィンドウに反映する。
    static let macornDisplayPreferencesChanged = Notification.Name("macornDisplayPreferencesChanged")
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
        static let colorFolders = "colorFoldersByTag"
        static let filePreview = "markdownPreview"
        static let filePreviewFraction = "markdownPreviewFraction"
        static let previewZoom = "previewZoom"
    }

    private static var defaults: UserDefaults { AppDefaults.store }

    static var showHiddenFiles: Bool {
        get { defaults.bool(forKey: Key.showHiddenFiles) }
        set {
            defaults.set(newValue, forKey: Key.showHiddenFiles)
            NotificationCenter.default.post(name: .macornDisplayPreferencesChanged, object: nil)
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

    /// フォルダのアイコンを、付いているタグの色で塗る
    static var colorFoldersByTag: Bool {
        get { defaults.object(forKey: Key.colorFolders) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.colorFolders) }
    }

    /// .md を選んだときに、一覧の右にプレビューを出す
    static var filePreview: Bool {
        get { defaults.object(forKey: Key.filePreview) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.filePreview) }
    }

    /// プレビューが画面の幅に占める割合
    static var filePreviewFraction: Double {
        get { defaults.object(forKey: Key.filePreviewFraction) as? Double ?? 0.5 }
        set { defaults.set(newValue, forKey: Key.filePreviewFraction) }
    }

    /// Markdown・HTML のプレビューの倍率（1.0 が実際のサイズ）
    static var previewZoom: Double {
        get { defaults.object(forKey: Key.previewZoom) as? Double ?? 1.0 }
        set { defaults.set(min(max(newValue, 0.25), 5.0), forKey: Key.previewZoom) }
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
            NotificationCenter.default.post(name: .macornDisplayPreferencesChanged, object: nil)
        }
    }
}
