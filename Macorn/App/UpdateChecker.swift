import AppKit

/// LP に置いた最新版の情報（https://macorn.app/version.json。LP のリポジトリの site/version.json を scripts/release.sh --publish が書く）
struct ReleaseInfo: Decodable, Equatable {
    var version: String
    var build: Int?
    /// DMG の URL
    var download: URL
    /// 入れ方の載っているページ
    var page: URL?
}

/// 新しい版が出ていないかを確かめて知らせる（外部ライブラリなし）。
/// 「今すぐ更新」で UpdateInstaller が入れ替えて開き直す。自動でできないときはブラウザでのダウンロードに戻す。
/// 起動時（設定でオフにできる）と、メニューの「アップデートを確認…」で確かめる。
enum UpdateChecker {
    enum Result: Equatable {
        case available(ReleaseInfo)
        case upToDate
        case failed(String)
    }

    /// 確かめる先。開発用に環境変数 MACORN_UPDATE_URL で差し替えられる（file:// も可）
    static var feedURL: URL {
        if let value = ProcessInfo.processInfo.environment["MACORN_UPDATE_URL"], let url = URL(string: value) {
            return url
        }
        return URL(string: "https://macorn.app/version.json")!
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// バージョンを数字ごとに比べる（0.10.0 は 0.9.0 より新しい）
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ version: String) -> [Int] {
            version.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// 情報を取ってきて、今の版と比べる
    static func fetch(from url: URL = feedURL, current: String = currentVersion) async -> Result {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return .failed("サーバーが \(http.statusCode) を返しました")
            }
            let info = try JSONDecoder().decode(ReleaseInfo.self, from: data)
            return isNewer(info.version, than: current) ? .available(info) : .upToDate
        } catch is DecodingError {
            return .failed("最新版の情報を読めませんでした")
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - 確かめて知らせる

    /// 起動時：新しい版があるときだけ知らせる（スキップした版と、失敗は黙っておく）
    static func checkOnLaunch() {
        guard Preferences.checkForUpdates else { return }
        Task {
            let result = await fetch()
            guard case .available(let info) = result, info.version != Preferences.skippedUpdateVersion else { return }
            present(result, manual: false, in: NSApp.keyWindow ?? NSApp.mainWindow)
        }
    }

    /// メニューの「アップデートを確認…」：結果をいつも知らせる（スキップした版も出す）
    static func checkManually() {
        Task {
            let result = await fetch()
            present(result, manual: true, in: NSApp.keyWindow ?? NSApp.mainWindow)
        }
    }

    /// 結果をアラートで出す。ウィンドウがあればシートにする
    static func present(_ result: Result, manual: Bool, in window: NSWindow?) {
        let alert = makeAlert(for: result, manual: manual)
        let handle: (NSApplication.ModalResponse) -> Void = { response in
            guard case .available(let info) = result else { return }
            switch response {
            case .alertFirstButtonReturn:
                if UpdateInstaller.canInstall {
                    UpdateInstaller.start(info)
                } else {
                    NSWorkspace.shared.open(info.download)
                }
            case .alertThirdButtonReturn:
                Preferences.skippedUpdateVersion = info.version
            default:
                break
            }
        }
        if let window, window.isVisible, window.attachedSheet == nil {
            alert.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }

    static func makeAlert(for result: Result, manual: Bool) -> NSAlert {
        let alert = NSAlert()
        switch result {
        case .available(let info):
            alert.messageText = "新しいバージョンの Macorn があります"
            if UpdateInstaller.canInstall {
                alert.informativeText = """
                Macorn \(info.version) を公開しました（お使いの版は \(currentVersion)）。
                「今すぐ更新」で新しい版をダウンロードして入れ替え、Macorn を開き直します。設定・タグ・履歴はそのまま残ります。
                """
                alert.addButton(withTitle: "今すぐ更新")
            } else {
                alert.informativeText = """
                Macorn \(info.version) を公開しました（お使いの版は \(currentVersion)）。
                ダウンロードした DMG を開き、Macorn を「アプリケーション」へドラッグして入れ替えてください。設定・タグ・履歴はそのまま残ります。
                """
                alert.addButton(withTitle: "ダウンロード")
            }
            alert.addButton(withTitle: "あとで")
            if !manual { alert.addButton(withTitle: "このバージョンをスキップ") }
        case .upToDate:
            alert.messageText = "Macorn は最新です"
            alert.informativeText = "お使いの \(currentVersion) が最新の版です。"
            alert.addButton(withTitle: "OK")
        case .failed(let message):
            alert.alertStyle = .warning
            alert.messageText = "アップデートを確認できませんでした"
            alert.informativeText = "\(message)。ネットにつながっているか確かめて、あとでもう一度お試しください。"
            alert.addButton(withTitle: "OK")
        }
        return alert
    }
}
