import Darwin
import Foundation

/// 疑似端末（PTY）の上でシェルを動かし、入出力をやり取りする（内蔵ターミナル、要件 T-30）。
/// 読み込みは裏のキューで行い、届いた中身は onData でメインスレッドへ渡す。
nonisolated final class TerminalProcess: @unchecked Sendable {
    /// シェルからの出力（メインスレッドで呼ぶ）
    var onData: (@MainActor (Data) -> Void)?
    /// シェルが終わった（メインスレッドで呼ぶ）
    var onExit: (@MainActor () -> Void)?

    private(set) var pid: pid_t = 0
    private var master: Int32 = -1
    private var readSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "macorn.terminal.read")

    var isRunning: Bool { pid > 0 }

    /// folder でシェルを起動する。columns × rows は最初の画面の大きさ
    func start(in folder: URL, columns: Int, rows: Int) -> Bool {
        let shell = Self.loginShell()
        // 子プロセスでは文字列を作れない（fork のあとは決まった関数しか呼べない）ので、先に用意する
        let names: [String] = [shell, "-" + (shell as NSString).lastPathComponent]
        let argv: [UnsafeMutablePointer<CChar>?] = names.map { strdup($0) }
        let environment: [UnsafeMutablePointer<CChar>?] = Self.environment().map { strdup($0) }
        let directory = strdup(folder.path)
        defer {
            argv.forEach { free($0) }
            environment.forEach { free($0) }
            free(directory)
        }
        var execArguments: [UnsafeMutablePointer<CChar>?] = [argv[1], nil]
        var execEnvironment: [UnsafeMutablePointer<CChar>?] = environment + [nil]
        let path = argv[0]

        var size = winsize(ws_row: UInt16(clamping: rows), ws_col: UInt16(clamping: columns), ws_xpixel: 0, ws_ypixel: 0)
        var masterFD: Int32 = -1
        let child = forkpty(&masterFD, nil, nil, &size)
        if child < 0 { return false }
        if child == 0 {
            // 子プロセス: フォルダを移ってシェルに置き換わる
            _ = chdir(directory)
            execArguments.withUnsafeMutableBufferPointer { arguments in
                execEnvironment.withUnsafeMutableBufferPointer { environment in
                    _ = execve(path, arguments.baseAddress, environment.baseAddress)
                }
            }
            _exit(127)
        }

        pid = child
        master = masterFD
        _ = fcntl(masterFD, F_SETFL, fcntl(masterFD, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: queue)
        source.setEventHandler { [weak self] in self?.readAvailable() }
        readSource = source
        source.resume()
        return true
    }

    private func readAvailable() {
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        let count = read(master, &buffer, buffer.count)
        if count > 0 {
            let data = Data(buffer[0..<count])
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.onData?(data) }
            }
        } else if count == 0 || (count < 0 && errno != EAGAIN && errno != EINTR) {
            // シェルが終わった
            readSource?.cancel()
            readSource = nil
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.finish() }
            }
        }
    }

    @MainActor private func finish() {
        guard pid > 0 else { return }
        var status: Int32 = 0
        waitpid(pid, &status, WNOHANG)
        pid = 0
        if master >= 0 { close(master) }
        master = -1
        onExit?()
    }

    func write(_ data: Data) {
        guard master >= 0, !data.isEmpty else { return }
        data.withUnsafeBytes { raw in
            guard var pointer = raw.baseAddress else { return }
            var remaining = raw.count
            while remaining > 0 {
                let written = Darwin.write(master, pointer, remaining)
                if written > 0 {
                    remaining -= written
                    pointer += written
                } else if written < 0, errno == EAGAIN || errno == EINTR {
                    usleep(1000)
                } else {
                    return
                }
            }
        }
    }

    func write(_ text: String) { write(Data(text.utf8)) }

    /// 画面の大きさが変わったことをシェルに知らせる
    func resize(columns: Int, rows: Int) {
        guard master >= 0 else { return }
        var size = winsize(ws_row: UInt16(clamping: rows), ws_col: UInt16(clamping: columns), ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(master, TIOCSWINSZ, &size)
    }

    /// 前面で動いているのがシェル自身か（コマンドを実行中でないか）
    var isShellInForeground: Bool {
        guard master >= 0, pid > 0 else { return false }
        return tcgetpgrp(master) == pid
    }

    func terminate() {
        guard pid > 0 else { return }
        kill(pid, SIGHUP)
        readSource?.cancel()
        readSource = nil
        if master >= 0 { close(master) }
        master = -1
        var status: Int32 = 0
        waitpid(pid, &status, WNOHANG)
        pid = 0
    }

    deinit {
        if pid > 0 { kill(pid, SIGHUP) }
        if master >= 0 { close(master) }
    }

    /// 利用者のログインシェル（なければ zsh）
    static func loginShell() -> String {
        if let shell = ProcessInfo.processInfo.environment["SHELL"], FileManager.default.isExecutableFile(atPath: shell) {
            return shell
        }
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return "/bin/zsh"
    }

    /// シェルに渡す環境変数。アプリから起動すると LANG が無いことがあり、日本語が化けるので補う
    static func environment() -> [String] {
        var values = ProcessInfo.processInfo.environment
        values["TERM"] = "xterm-256color"
        values["COLORTERM"] = "truecolor"
        values["TERM_PROGRAM"] = "Macorn"
        if values["LANG"] == nil { values["LANG"] = "ja_JP.UTF-8" }
        // Xcode などから起動したときの変数は持ち込まない
        for key in values.keys where key.hasPrefix("MACORN_") || key.hasPrefix("__XPC") || key == "XPC_SERVICE_NAME" {
            values[key] = nil
        }
        return values.map { "\($0.key)=\($0.value)" }
    }
}
