import AppKit

/// DMG の中やダウンロードなど「アプリケーション」フォルダの外から起動したとき、移すかを尋ねる。
/// 移すと「アプリケーション」へコピー（DMG 以外からなら移動）して開き直し、DMG は取り出す。
/// 配布用（Release）のビルドだけで尋ねる。開発用の Debug ビルドは build/ から動かすため尋ねない。
enum AppMover {
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    /// 移す先。開発・確認用に環境変数 MACORN_MOVE_DEST で差し替えられる
    static var destinationFolder: URL {
        if let path = environment["MACORN_MOVE_DEST"] { return URL(fileURLWithPath: path) }
        return URL(fileURLWithPath: "/Applications")
    }

    /// 尋ねるかどうか（Release か、確認用に移す先を差し替えたときだけ）
    private static var isEnabled: Bool {
        #if DEBUG
        return environment["MACORN_MOVE_DEST"] != nil
        #else
        return true
        #endif
    }

    /// 「アプリケーション」（/Applications・~/Applications、または差し替えた移す先）の中にあるか
    static func isInApplicationsFolder(_ bundle: URL, destination: URL = destinationFolder,
                                       home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let path = bundle.resolvingSymlinksInPath().standardizedFileURL.path
        let folders = [destination, URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        return folders.contains { folder in
            let prefix = folder.resolvingSymlinksInPath().standardizedFileURL.path
            return path.hasPrefix(prefix + "/")
        }
    }

    /// 読み取り専用のボリューム（DMG）の上にあれば、そのボリューム
    static func diskImageVolume(of bundle: URL) -> URL? {
        guard let values = try? bundle.resourceValues(forKeys: [.volumeIsReadOnlyKey]), values.volumeIsReadOnly == true,
              let volume = (try? (bundle as NSURL).resourceValues(forKeys: [.volumeURLKey]))?[.volumeURLKey] as? URL,
              volume.path.hasPrefix("/Volumes/") else { return nil }
        return volume
    }

    /// Gatekeeper が別の場所に隔離して開いたか（そのときは元の場所が分からないので、コピーだけする）
    static func isTranslocated(_ bundle: URL) -> Bool {
        bundle.path.contains("/AppTranslocation/")
    }

    // MARK: - 起動時に尋ねる

    /// 必要なら尋ねる。移して開き直すときは true（呼び出し側はほかの起動処理をしない）
    static func offerIfNeeded() -> Bool {
        let bundle = Bundle.main.bundleURL
        guard isEnabled, !Preferences.suppressMoveToApplications, !isInApplicationsFolder(bundle) else { return false }

        let volume = diskImageVolume(of: bundle)
        let answer: Bool
        if let preset = environment["MACORN_MOVE_ANSWER"] {
            // 確認用：尋ねずに答える（move / skip）
            answer = preset == "move"
        } else {
            let alert = makeAlert(onDiskImage: volume != nil, location: bundle.deletingLastPathComponent())
            NSApp.activate()
            let response = alert.runModal()
            if alert.suppressionButton?.state == .on { Preferences.suppressMoveToApplications = true }
            answer = response == .alertFirstButtonReturn
        }
        guard answer else { return false }

        do {
            let installed = try install(bundle, into: destinationFolder, keepOriginal: volume != nil || isTranslocated(bundle))
            relaunch(installed, ejecting: volume)
            return true
        } catch {
            let failure = NSAlert()
            failure.alertStyle = .warning
            failure.messageText = "「アプリケーション」フォルダに移動できませんでした"
            failure.informativeText = "\(error.localizedDescription)\nFinder で Macorn を「アプリケーション」フォルダへドラッグしてください。"
            failure.runModal()
            return false
        }
    }

    static func makeAlert(onDiskImage: Bool, location: URL) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Macorn を「アプリケーション」フォルダに移動しますか？"
        let place = onDiskImage
            ? "今は DMG（ディスクイメージ）の中から開いています。このままだと、DMG を取り出すと使えなくなります。"
            : "今は「\(FileManager.default.displayName(atPath: location.path))」から開いています。"
        alert.informativeText = place + "\n移動すると Macorn を開き直します。設定・タグ・履歴はそのまま使えます。"
        alert.addButton(withTitle: "「アプリケーション」へ移動")
        alert.addButton(withTitle: "移動しない")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "今後確認しない"
        return alert
    }

    // MARK: - 移して開き直す

    /// 移す先に入れる。同じ名前の古いものはゴミ箱へ移す。keepOriginal なら元を残す（DMG など）
    @discardableResult
    static func install(_ source: URL, into folder: URL, keepOriginal: Bool) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(source.lastPathComponent)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.trashItem(at: destination, resultingItemURL: nil)
        }
        if keepOriginal {
            try fileManager.copyItem(at: source, to: destination)
        } else {
            try fileManager.moveItem(at: source, to: destination)
        }
        return destination
    }

    /// 自分が終わるのを待って、移した先の Macorn を開く。DMG から来たときはそのあと取り出す
    static func relaunch(_ app: URL, ejecting volume: URL?) {
        // 確認用の環境変数（MACORN_*）は開き直したほうにも渡す（普段の設定を汚さないため）
        let passthrough = environment.filter { $0.key.hasPrefix("MACORN_") && $0.key != "MACORN_MOVE_ANSWER" }
        let envArguments = passthrough.flatMap { ["--env", "\($0.key)=\($0.value)"] }.map(shellQuote).joined(separator: " ")
        let script = """
        while /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do /bin/sleep 0.2; done
        /usr/bin/open -n \(envArguments) \(shellQuote(app.path))
        \(volume.map { "/bin/sleep 1; /usr/bin/hdiutil detach \(shellQuote($0.path)) -quiet" } ?? "")
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try? process.run()
        NSApp.terminate(nil)
    }

    private static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
