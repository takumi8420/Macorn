import AppKit

/// 連携する外部アプリ（ターミナル・エディタ）の候補。
struct ExternalApp: Identifiable, Hashable {
    var id: String { bundleIdentifier }
    var name: String
    var bundleIdentifier: String

    var url: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) }
    var isInstalled: Bool { url != nil }

    static let terminals = [
        ExternalApp(name: "ターミナル", bundleIdentifier: "com.apple.Terminal"),
        ExternalApp(name: "iTerm2", bundleIdentifier: "com.googlecode.iterm2"),
        ExternalApp(name: "Ghostty", bundleIdentifier: "com.mitchellh.ghostty"),
        ExternalApp(name: "WezTerm", bundleIdentifier: "com.github.wez.wezterm"),
        ExternalApp(name: "Warp", bundleIdentifier: "dev.warp.Warp-Stable"),
    ]

    static let editors = [
        ExternalApp(name: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode"),
        ExternalApp(name: "Cursor", bundleIdentifier: "com.todesktop.230313mzl4w4u92"),
        ExternalApp(name: "Zed", bundleIdentifier: "dev.zed.Zed"),
        ExternalApp(name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode"),
    ]

    /// 選んだアプリ。未設定またはアンインストール済みなら、入っている候補の先頭。
    static func preferred(from candidates: [ExternalApp], identifier: String?) -> ExternalApp? {
        if let identifier, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
            let known = candidates.first { $0.bundleIdentifier == identifier }
            return known ?? ExternalApp(name: FileManager.default.displayName(atPath: url.path), bundleIdentifier: identifier)
        }
        return candidates.first(where: \.isInstalled)
    }
}

/// ターミナルで開く（要件 T-01〜T-03）。
enum TerminalLauncher {
    static var selected: ExternalApp? {
        ExternalApp.preferred(from: ExternalApp.terminals, identifier: Preferences.terminalBundleIdentifier)
    }

    static func open(_ folder: URL) {
        guard let app = selected, let appURL = app.url else {
            NSSound.beep()
            return
        }
        #if DEBUG
        if let log = ProcessInfo.processInfo.environment["NOXY_DEBUG_LAUNCH_LOG"] {
            DebugLaunchLog.append("terminal \(app.bundleIdentifier) \(folder.path) tab=\(Preferences.openTerminalInNewTab)", to: log)
            return
        }
        #endif
        if Preferences.openTerminalInNewTab, openInNewTab(folder, app: app, appURL: appURL) { return }

        switch app.bundleIdentifier {
        case "com.github.wez.wezterm":
            // WezTerm はフォルダを渡しても開けないため、付属のコマンドで作業フォルダを指定する
            run(appURL.appendingPathComponent("Contents/MacOS/wezterm"), ["start", "--cwd", folder.path])
        case "com.mitchellh.ghostty":
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = ["--working-directory=\(folder.path)"]
            configuration.createsNewApplicationInstance = !isRunning(app)
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        default:
            // ターミナル・iTerm2・Warp はフォルダを渡すと、そこを作業フォルダにした新しいウィンドウを開く
            NSWorkspace.shared.open([folder], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// 新しいタブで開く。対応しているのは iTerm2（AppleScript）と WezTerm（付属コマンド）。
    private static func openInNewTab(_ folder: URL, app: ExternalApp, appURL: URL) -> Bool {
        guard isRunning(app) else { return false }
        switch app.bundleIdentifier {
        case "com.googlecode.iterm2":
            let script = """
                tell application id "com.googlecode.iterm2"
                    activate
                    if (count of windows) = 0 then
                        create window with default profile
                    else
                        tell current window to create tab with default profile
                    end if
                    tell current session of current window to write text "cd " & quoted form of "\(appleScriptEscaped(folder.path))"
                end tell
                """
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
            return error == nil
        case "com.github.wez.wezterm":
            run(appURL.appendingPathComponent("Contents/MacOS/wezterm"), ["cli", "spawn", "--cwd", folder.path])
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
            return true
        default:
            return false
        }
    }

    static var supportsNewTab: Bool {
        ["com.googlecode.iterm2", "com.github.wez.wezterm"].contains(selected?.bundleIdentifier)
    }

    private static func isRunning(_ app: ExternalApp) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).isEmpty
    }

    private static func appleScriptEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func run(_ executable: URL, _ arguments: [String]) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        try? process.run()
    }
}

/// エディタで開く（要件 T-04〜T-06）。
enum EditorLauncher {
    static var selected: ExternalApp? {
        ExternalApp.preferred(from: ExternalApp.editors, identifier: Preferences.editorBundleIdentifier)
    }

    static func open(_ urls: [URL]) {
        guard !urls.isEmpty, let app = selected, let appURL = app.url else {
            NSSound.beep()
            return
        }
        #if DEBUG
        if let log = ProcessInfo.processInfo.environment["NOXY_DEBUG_LAUNCH_LOG"] {
            DebugLaunchLog.append("editor \(app.bundleIdentifier) \(urls.map(\.path).joined(separator: ","))", to: log)
            return
        }
        #endif
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// パスのコピー（要件 T-10〜T-13）。
enum PathCopier {
    enum Style {
        case full, tilde, relativeToRepository, shellQuoted
    }

    static func text(for urls: [URL], style: Style) -> String? {
        let lines: [String] = urls.compactMap { url in
            let path = url.standardizedFileURL.path
            switch style {
            case .full:
                return path
            case .tilde:
                return PathCompletion.abbreviate(path)
            case .relativeToRepository:
                guard let root = GitRepository.root(containing: url) else { return nil }
                if path == root.path { return "." }
                return String(path.dropFirst(root.path.count + 1))
            case .shellQuoted:
                return shellQuoted(path)
            }
        }
        guard lines.count == urls.count, !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }

    /// シェルにそのまま貼れる形（シングルクォートで囲み、中の ' は '\'' にする）。
    static func shellQuoted(_ path: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/._-+@%~"))
        if path.unicodeScalars.allSatisfy({ safe.contains($0) && $0.isASCII }) { return path }
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    @discardableResult
    static func copy(_ urls: [URL], style: Style) -> Bool {
        guard let text = text(for: urls, style: style) else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return true
    }
}

#if DEBUG
/// 自動テスト用: 外部アプリを実際には起動せず、起動しようとした内容をファイルに書く。
enum DebugLaunchLog {
    static func append(_ line: String, to path: String) {
        let data = Data((line + "\n").utf8)
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }
}
#endif
