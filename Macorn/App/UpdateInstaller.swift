import AppKit
import Security

/// 新しい版を自動で入れ替えて開き直す（外部ライブラリなし）。
/// ダウンロード → DMG を開く → 署名を確かめる（同じ開発チームの Developer ID か・同じアプリか・知らされた版か）
/// → 一時フォルダへ写す → Macorn を終えてから、今の場所の Macorn と入れ替えて開き直す。
/// 確かめられない・書き込めないときは入れ替えず、これまでどおりブラウザでのダウンロードに戻す。
enum UpdateInstaller {
    enum Failure: LocalizedError {
        case noSignature, notWritable, download(String), mount, noApp, untrusted(String), mismatch(String), copy(String)

        var errorDescription: String? {
            switch self {
            case .noSignature: "このビルドは配布用の署名がないため、自動では更新できません"
            case .notWritable: "Macorn のある場所に書き込めません（「アプリケーション」以外から開いているかもしれません）"
            case .download(let message): "ダウンロードできませんでした（\(message)）"
            case .mount: "ダウンロードした DMG を開けませんでした"
            case .noApp: "ダウンロードした DMG に Macorn が入っていませんでした"
            case .untrusted(let message): "ダウンロードした Macorn の署名を確かめられませんでした（\(message)）"
            case .mismatch(let message): "ダウンロードしたものが、知らされた版と違います（\(message)）"
            case .copy(let message): "新しい版を用意できませんでした（\(message)）"
            }
        }
    }

    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    /// 今動いている Macorn の署名の開発チーム。簡易署名（開発用ビルド）なら nil
    static var ownTeamIdentifier: String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return devTeamOverride }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return devTeamOverride }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any], let team = dict[kSecCodeInfoTeamIdentifier as String] as? String else {
            return devTeamOverride
        }
        return team
    }

    /// 開発用：簡易署名のビルドで確かめるときに、期待するチームを環境変数で渡す
    private static var devTeamOverride: String? {
        #if DEBUG
        return environment["MACORN_UPDATE_TEAM"]
        #else
        return nil
        #endif
    }

    /// 入れ替える先（今動いている Macorn）
    static var destination: URL { Bundle.main.bundleURL }

    /// 自動で入れ替えられるか（配布用の署名があり、今の場所に書き込める）
    static var canInstall: Bool {
        ownTeamIdentifier != nil && FileManager.default.isWritableFile(atPath: destination.deletingLastPathComponent().path)
    }

    // MARK: - 入れ替え

    /// 「今すぐ更新」：進み具合の窓を出して入れ替え、Macorn を開き直す。失敗したらブラウザでのダウンロードを勧める
    static func start(_ info: ReleaseInfo) {
        let panel = UpdateProgressPanel(version: info.version)
        panel.show()
        let task = Task {
            do {
                let staged = try await prepare(info) { fraction in panel.setProgress(fraction) }
                panel.setStatus("入れ替えて、Macorn を開き直します…")
                try? await Task.sleep(for: .milliseconds(400))
                relaunch(replacing: destination, with: staged)
            } catch is CancellationError {
                panel.close()
            } catch {
                panel.close()
                offerBrowser(info, reason: error.localizedDescription)
            }
        }
        panel.onCancel = { task.cancel() }
    }

    /// ダウンロードして確かめ、一時フォルダに新しい Macorn.app を用意する（まだ入れ替えない）
    static func prepare(_ info: ReleaseInfo, progress: @escaping @MainActor (Double) -> Void) async throws -> URL {
        guard let team = ownTeamIdentifier else { throw Failure.noSignature }
        guard FileManager.default.isWritableFile(atPath: destination.deletingLastPathComponent().path) else { throw Failure.notWritable }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("macorn-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let dmg: URL
        do {
            dmg = try await download(info.download, to: work.appendingPathComponent("Macorn.dmg"), progress: progress)
            try Task.checkCancellation()
        } catch {
            try? FileManager.default.removeItem(at: work)
            throw error
        }

        let mount = work.appendingPathComponent("mount")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        guard (try? await run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noverify", "-mountpoint", mount.path]))?.status == 0 else {
            throw Failure.mount
        }
        // DMG は、うまくいってもいかなくても閉じ終えてから先へ進む（閉じる前に Macorn が終わると開いたまま残るため）
        let staged = work.appendingPathComponent("Macorn.app")
        let result: Swift.Result<Void, Error>
        do {
            guard let app = (try? FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil))?
                .first(where: { $0.pathExtension == "app" }) else { throw Failure.noApp }
            try verify(app, team: team, version: info.version)
            // 入れ替えは Macorn を終えてからなので、一時フォルダへ写しておく
            let copy = try await run("/usr/bin/ditto", [app.path, staged.path])
            guard copy.status == 0 else { throw Failure.copy(copy.output) }
            result = .success(())
        } catch {
            result = .failure(error)
        }
        _ = try? await run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet", "-force"])
        try? FileManager.default.removeItem(at: dmg)
        do {
            try result.get()
        } catch {
            try? FileManager.default.removeItem(at: work)
            throw error
        }
        do {
            try verify(staged, team: team, version: info.version)
        } catch {
            try? FileManager.default.removeItem(at: work)
            throw error
        }
        return staged
    }

    /// 署名（Apple が認めた証明書で、同じ開発チーム）・アプリの ID・版を確かめる
    static func verify(_ app: URL, team: String, version: String) throws {
        let bundle = Bundle(url: app)
        guard bundle?.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw Failure.mismatch("アプリの ID が \(bundle?.bundleIdentifier ?? "不明")")
        }
        let found = bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "不明"
        guard found == version else { throw Failure.mismatch("版が \(found)") }

        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else {
            throw Failure.untrusted("署名を読めません")
        }
        var requirement: SecRequirement?
        let text = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement else {
            throw Failure.untrusted("条件を作れません")
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        let status = SecStaticCodeCheckValidity(code, flags, requirement)
        guard status == errSecSuccess else {
            throw Failure.untrusted(SecCopyErrorMessageString(status, nil) as String? ?? "コード \(status)")
        }
    }

    /// Macorn が終わるのを待って入れ替え、開き直す。入れ替えに失敗したら元に戻す
    static func relaunch(replacing current: URL, with staged: URL) {
        // 確認用の環境変数（MACORN_*）は開き直したほうにも渡す（普段の設定を汚さないため）
        let passthrough = environment.filter { $0.key.hasPrefix("MACORN_") && !$0.key.hasPrefix("MACORN_DEBUG_STEPS") }
        let envArguments = passthrough.flatMap { ["--env", "\($0.key)=\($0.value)"] }.map(shellQuote).joined(separator: " ")
        let backup = staged.deletingLastPathComponent().appendingPathComponent("previous.app")
        let script = """
        while /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do /bin/sleep 0.2; done
        if /bin/mv \(shellQuote(current.path)) \(shellQuote(backup.path)); then
          if /bin/mv \(shellQuote(staged.path)) \(shellQuote(current.path)); then
            /bin/rm -rf \(shellQuote(backup.path))
          else
            /bin/mv \(shellQuote(backup.path)) \(shellQuote(current.path))
          fi
        fi
        /usr/bin/open -n \(envArguments) \(shellQuote(current.path))
        /bin/rm -rf \(shellQuote(staged.deletingLastPathComponent().path))
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try? process.run()
        NSApp.terminate(nil)
    }

    /// 自動でできなかったとき：理由を伝え、ブラウザでのダウンロードを勧める
    static func offerBrowser(_ info: ReleaseInfo, reason: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "自動では更新できませんでした"
        alert.informativeText = "\(reason)\nブラウザから DMG をダウンロードして、Macorn を「アプリケーション」へドラッグして入れ替えてください。"
        alert.addButton(withTitle: "ブラウザでダウンロード")
        alert.addButton(withTitle: "閉じる")
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(info.download) }
    }

    // MARK: - 部品

    private static func download(_ url: URL, to file: URL, progress: @escaping @MainActor (Double) -> Void) async throws -> URL {
        if url.isFileURL {
            // 開発・確認用（MACORN_UPDATE_URL で file:// を渡したとき）
            try FileManager.default.copyItem(at: url, to: file)
            progress(1)
            return file
        }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        let delegate = DownloadProgress(progress)
        let (temp, response) = try await URLSession.shared.download(for: request, delegate: delegate)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.download("サーバーが \(http.statusCode) を返しました")
        }
        try FileManager.default.moveItem(at: temp, to: file)
        return file
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) async throws -> (status: Int32, output: String) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: (process.terminationStatus, String(decoding: data, as: UTF8.self)))
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }

    private static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// ダウンロードの進み具合を知らせる
private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let report: @MainActor (Double) -> Void

    init(_ report: @escaping @MainActor (Double) -> Void) {
        self.report = report
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in report(fraction) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

/// 更新の進み具合の小さな窓
final class UpdateProgressPanel {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()
    var onCancel: (() -> Void)?

    init(version: String) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Macorn をアップデート"
        panel.isReleasedWhenClosed = false
        let content = NSView()
        label.stringValue = "Macorn \(version) をダウンロードしています…"
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 1
        let cancel = NSButton(title: "キャンセル", target: nil, action: nil)
        cancel.bezelStyle = .rounded
        for view in [label, bar, cancel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            bar.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 12),
            bar.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: label.trailingAnchor),
            cancel.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 14),
            cancel.trailingAnchor.constraint(equalTo: label.trailingAnchor),
        ])
        panel.contentView = content
        cancel.target = self
        cancel.action = #selector(cancelTapped)
    }

    func show() {
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    func setProgress(_ fraction: Double) { bar.doubleValue = fraction }

    func setStatus(_ text: String) {
        label.stringValue = text
        bar.isIndeterminate = true
        bar.startAnimation(nil)
    }

    func close() { panel.orderOut(nil) }

    @objc private func cancelTapped() {
        onCancel?()
        close()
    }
}
