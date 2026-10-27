import Foundation

/// ほかのアプリの「Finder に表示」の行き先を Macorn にする設定。
/// macOS 側の設定なので、Macorn の中には保存せず、毎回 macOS から読み出す。
/// フォルダの既定のアプリは macOS が変更を受け付けない（public.folder への LSSetDefaultRoleHandlerForContentType も
/// NSWorkspace.setDefaultApplication も paramErr になる。macOS 26.7 で確認）ため、ここでは扱わない。
/// ファイルの種類（.md など）の既定のアプリも対象外（Macorn は編集できないため）。
enum SystemFileViewer {
    private static var macornIdentifier: String { Bundle.main.bundleIdentifier ?? "dev.macorn.Macorn" }

    // MARK: 「Finder に表示」の行き先

    private static let fileViewerKey = "NSFileViewer" as CFString

    /// ほかのアプリの「Finder に表示」が Macorn に届くか（macOS 全体の設定 NSFileViewer）
    static var revealsFiles: Bool {
        let value = CFPreferencesCopyValue(fileViewerKey, kCFPreferencesAnyApplication,
                                           kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? String
        return value == macornIdentifier
    }

    /// 「Finder に表示」の行き先を Macorn にする。オフにすると設定を消して Finder に戻す。
    /// ほかのアプリは起動したときに読むので、反映されるのはそのアプリを開き直してから。
    /// 届くのはふつうの「開く」要求（application(_:open:)）。ファイルはそのフォルダで選び、フォルダはその中を開く。
    static func setRevealsFiles(_ enabled: Bool) {
        let value: CFString? = enabled ? macornIdentifier as CFString : nil
        CFPreferencesSetValue(fileViewerKey, value, kCFPreferencesAnyApplication,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
}
