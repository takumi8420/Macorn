import Foundation

extension Notification.Name {
    /// Macorn の中でブランチの切り替え・コミット・プル などをしたとき。開いている画面の Git の状態を読み直す
    static let macornGitRepositoryChanged = Notification.Name("macornGitRepositoryChanged")
}

/// git の実行結果
nonisolated struct GitCommandResult: Sendable {
    var status: Int32
    var output: String
    var errorOutput: String

    var succeeded: Bool { status == 0 }

    /// 利用者に見せる失敗の説明（git のメッセージをそのまま、長すぎれば切る）
    var message: String {
        let text = (errorOutput.isEmpty ? output : errorOutput).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "git が終了コード \(status) で終わりました" }
        return text.count > 1200 ? String(text.prefix(1200)) + "…" : text
    }
}

/// リポジトリのブランチの一覧と、リモートとの差
nonisolated struct GitBranches: Sendable, Equatable {
    /// 今のブランチ（ブランチの外にいるときは nil）
    var current: String?
    var local: [String] = []
    /// リモートのブランチ（「origin/feature」の形。HEAD と、同じ名前のローカルのブランチがあるものは除く）
    var remote: [String] = []
    /// 追いかけているリモートのブランチ（「origin/main」）。まだなければ nil
    var upstream: String?
    /// リモートより進んでいる・遅れているコミットの数
    var ahead = 0
    var behind = 0
    /// プッシュ先にするリモート（origin、なければ最初のもの。リモートがなければ nil）
    var defaultRemote: String?
}

/// GitHub Desktop の基本の操作（ブランチの作成・切り替え、コミット、プッシュ・プル・フェッチ）。
/// 表示のための読み取り（GitRepository）と違い、リポジトリを書き換える。すべて裏のスレッドで呼ぶ
nonisolated enum GitActions {
    /// git を実行する。パスワードなどを尋ねる画面は出さず、認証が要るときは失敗として返す
    static func run(_ arguments: [String], in root: URL) -> GitCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", root.path] + arguments
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_SSH_COMMAND"] = environment["GIT_SSH_COMMAND"] ?? "ssh -o BatchMode=yes"
        environment["LC_ALL"] = "C"
        process.environment = environment
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return GitCommandResult(status: -1, output: "", errorOutput: "git を起動できませんでした（\(error.localizedDescription)）")
        }
        // 出力が多いと管が詰まるので、終わりを待つ前に両方を読み切る
        let errorData = ReadAll(error.fileHandleForReading)
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return GitCommandResult(status: process.terminationStatus,
                                output: String(decoding: outputData, as: UTF8.self),
                                errorOutput: String(decoding: errorData.wait(), as: UTF8.self))
    }

    /// 標準エラーを別のスレッドで読む（標準出力と同時に読まないと、片方が詰まって止まることがある）
    private final class ReadAll: @unchecked Sendable {
        private var data = Data()
        private let semaphore = DispatchSemaphore(value: 0)

        init(_ handle: FileHandle) {
            DispatchQueue.global().async {
                self.data = handle.readDataToEndOfFile()
                self.semaphore.signal()
            }
        }

        func wait() -> Data {
            semaphore.wait()
            return data
        }
    }

    // MARK: ブランチ

    static func branches(root: URL) -> GitBranches {
        var result = GitBranches()
        let current = run(["symbolic-ref", "--quiet", "--short", "HEAD"], in: root)
        if current.succeeded { result.current = current.output.trimmingCharacters(in: .whitespacesAndNewlines) }
        result.local = lines(run(["for-each-ref", "--format=%(refname:short)", "--sort=refname", "refs/heads"], in: root).output)
        let remotes = lines(run(["remote"], in: root).output)
        result.defaultRemote = remotes.contains("origin") ? "origin" : remotes.first
        let localSet = Set(result.local)
        result.remote = lines(run(["for-each-ref", "--format=%(refname:short)", "--sort=refname", "refs/remotes"], in: root).output)
            .filter { name in
                guard let slash = name.firstIndex(of: "/") else { return false }
                let branch = String(name[name.index(after: slash)...])
                return branch != "HEAD" && !localSet.contains(branch)
            }
        let upstream = run(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"], in: root)
        if upstream.succeeded {
            result.upstream = upstream.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let counts = run(["rev-list", "--left-right", "--count", "HEAD...@{upstream}"], in: root)
            let numbers = counts.output.split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
            if counts.succeeded, numbers.count == 2 {
                result.ahead = numbers[0]
                result.behind = numbers[1]
            }
        }
        return result
    }

    /// ブランチの名前として使えるか（git の決まりに沿っているか）
    static func isValidBranchName(_ name: String, root: URL) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("-") else { return false }
        return run(["check-ref-format", "--branch", trimmed], in: root).succeeded
    }

    /// 切り替えの前に、コミットしていない変更をどうするか
    enum PendingChanges: Sendable {
        /// 切り替え先へそのまま持っていく（git の既定。ぶつかるときは git が止める）
        case bring
        /// 今のブランチに退避（stash）してから切り替える
        case stash
    }

    /// ブランチを切り替える。branch は「feature」（ローカル）か「origin/feature」（リモート。同じ名前のローカルのブランチを作って追いかける）
    static func switchBranch(_ branch: String, root: URL, changes: PendingChanges) -> GitCommandResult {
        if case .stash = changes {
            let from = branches(root: root).current ?? "HEAD"
            let stash = run(["stash", "push", "--include-untracked", "-m", "Macorn: \(from) から切り替える前の変更"], in: root)
            guard stash.succeeded else { return stash }
        }
        let local = Set(lines(run(["for-each-ref", "--format=%(refname:short)", "refs/heads"], in: root).output))
        if local.contains(branch) {
            return run(["switch", branch], in: root)
        }
        return run(["switch", "--track", branch], in: root)
    }

    /// 今のコミットから新しいブランチを作って切り替える（コミットしていない変更は持っていく）
    static func createBranch(_ name: String, root: URL) -> GitCommandResult {
        run(["switch", "-c", name.trimmingCharacters(in: .whitespaces)], in: root)
    }

    // MARK: コミット

    /// 選んだファイルだけをコミットする（ほかにステージしてあるものは含めない）。
    /// paths はリポジトリのルートからの相対パス。名前の変更は、元の名前も渡す
    static func commit(paths: [String], summary: String, description: String, root: URL) -> GitCommandResult {
        guard !paths.isEmpty else { return GitCommandResult(status: 1, output: "", errorOutput: "コミットするファイルを選んでください") }
        let add = run(["add", "--all", "--"] + paths, in: root)
        guard add.succeeded else { return add }
        var arguments = ["commit", "--only", "-m", summary]
        let body = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty { arguments += ["-m", body] }
        return run(arguments + ["--"] + paths, in: root)
    }

    // MARK: リモートとの同期

    static func fetch(root: URL) -> GitCommandResult {
        run(["fetch", "--all", "--prune"], in: root)
    }

    /// リモートの変更を取り込む。手元にもリモートにもないコミットが両方にあるとき（分かれているとき）は、混ぜずに失敗させる
    static func pull(root: URL) -> GitCommandResult {
        run(["pull", "--ff-only"], in: root)
    }

    /// プッシュする。まだリモートにないブランチは、リモートに作って追いかけるようにする（GitHub Desktop の「公開」）
    static func push(root: URL, branches: GitBranches) -> GitCommandResult {
        if branches.upstream != nil { return run(["push"], in: root) }
        guard let remote = branches.defaultRemote else {
            return GitCommandResult(status: 1, output: "", errorOutput: "リモートが登録されていません")
        }
        return run(["push", "--set-upstream", remote, "HEAD"], in: root)
    }

    private static func lines(_ text: String) -> [String] {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
