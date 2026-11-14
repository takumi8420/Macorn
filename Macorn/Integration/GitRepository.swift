import Foundation

nonisolated enum GitFileStatus: Sendable, Equatable {
    case modified, added, untracked, deleted, renamed, conflicted, ignored

    /// 一覧に出す1文字の印
    var badge: String {
        switch self {
        case .modified: "M"
        case .added: "A"
        case .untracked: "U"
        case .deleted: "D"
        case .renamed: "R"
        case .conflicted: "C"
        case .ignored: ""
        }
    }
}

/// ある時点の Git リポジトリの状態（ブランチ名と、変更のあるファイル）。
nonisolated struct GitSnapshot: Sendable, Equatable {
    var root: URL
    var branch: String
    /// リポジトリのルートからの相対パス → 状態
    var statuses: [String: GitFileStatus] = [:]
    /// 中身ごと未追跡・無視のフォルダ（相対パス）
    var untrackedFolders: [String] = []
    var ignoredFolders: [String] = []
    /// 中に変更のあるファイルを含むフォルダ（相対パス）
    var changedFolders: Set<String> = []
    /// リモート（origin）を Web で開く URL。GitHub なら https://github.com/持ち主/リポジトリ
    var remoteWebURL: URL?
    /// 追いかけているリモートのブランチより進んでいる・遅れているコミットの数（最後にフェッチした時点）
    var ahead = 0
    var behind = 0

    /// 「持ち主/リポジトリ」（リモートがあればその名前、なければフォルダ名）
    var repositoryName: String {
        if let remoteWebURL, let name = GitRepository.repositoryName(of: remoteWebURL) { return name }
        return root.lastPathComponent
    }

    /// リモートのサービスの名前（ボタンの文字に使う）
    var remoteServiceName: String? {
        guard let host = remoteWebURL?.host?.lowercased() else { return nil }
        if host == "github.com" || host.hasSuffix(".github.com") || host.contains("github") { return "GitHub" }
        if host.contains("gitlab") { return "GitLab" }
        if host.contains("bitbucket") { return "Bitbucket" }
        return host
    }

    var changeCount: Int { statuses.values.filter { $0 != .ignored }.count }

    func status(for url: URL) -> GitFileStatus? {
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(root.path + "/") else { return nil }
        let relative = String(path.dropFirst(root.path.count + 1))
        if let status = statuses[relative] { return status }
        if ignoredFolders.contains(where: { relative.hasPrefix($0 + "/") }) { return .ignored }
        if untrackedFolders.contains(where: { relative.hasPrefix($0 + "/") }) { return .untracked }
        if changedFolders.contains(relative) { return .modified }
        return nil
    }

    /// `git status --porcelain=v1 -z --branch --ignored` の出力を読む。
    static func parse(_ output: String, root: URL) -> GitSnapshot {
        var snapshot = GitSnapshot(root: root, branch: "")
        var records = output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)[...]
        while let record = records.popFirst() {
            if record.hasPrefix("## ") {
                let header = String(record.dropFirst(3))
                snapshot.branch = branchName(fromHeader: header)
                (snapshot.ahead, snapshot.behind) = aheadBehind(fromHeader: header)
                continue
            }
            guard record.count > 3 else { continue }
            let code = Array(record.prefix(2))
            var path = String(record.dropFirst(3))
            // 名前の変更は「新しい名前\0元の名前」の順で来る
            if code[0] == "R" || code[0] == "C" { _ = records.popFirst() }

            let status: GitFileStatus
            switch (code[0], code[1]) {
            case ("?", "?"): status = .untracked
            case ("!", "!"): status = .ignored
            case ("U", _), (_, "U"), ("A", "A"), ("D", "D"): status = .conflicted
            case ("A", _): status = .added
            case ("R", _): status = .renamed
            case ("D", _), (_, "D"): status = .deleted
            default: status = .modified
            }

            let isFolder = path.hasSuffix("/")
            if isFolder { path.removeLast() }
            snapshot.statuses[path] = status
            if isFolder, status == .ignored { snapshot.ignoredFolders.append(path) }
            if isFolder, status == .untracked { snapshot.untrackedFolders.append(path) }

            if status != .ignored {
                var parent = (path as NSString).deletingLastPathComponent
                while !parent.isEmpty {
                    snapshot.changedFolders.insert(parent)
                    parent = (parent as NSString).deletingLastPathComponent
                }
            }
        }
        return snapshot
    }

    /// 「main...origin/main [ahead 1, behind 2]」→ (1, 2)
    static func aheadBehind(fromHeader header: String) -> (ahead: Int, behind: Int) {
        guard let open = header.lastIndex(of: "["), let close = header.lastIndex(of: "]"), open < close else { return (0, 0) }
        var ahead = 0
        var behind = 0
        for part in header[header.index(after: open)..<close].split(separator: ",") {
            let words = part.split(separator: " ")
            guard words.count == 2, let count = Int(words[1]) else { continue }
            if words[0] == "ahead" { ahead = count }
            if words[0] == "behind" { behind = count }
        }
        return (ahead, behind)
    }

    /// 「main...origin/main [ahead 1]」→「main」、「No commits yet on main」→「main」
    static func branchName(fromHeader header: String) -> String {
        var name = header
        if name.hasPrefix("No commits yet on ") { name = String(name.dropFirst("No commits yet on ".count)) }
        if name.hasPrefix("HEAD (no branch)") { return "(detached)" }
        if let range = name.range(of: "...") { name = String(name[..<range.lowerBound]) }
        if let space = name.firstIndex(of: " ") { name = String(name[..<space]) }
        return name
    }
}

nonisolated enum GitRepository {
    /// url を含む Git リポジトリのルート。.git はフォルダ（通常）でもファイル（worktree・submodule）でもよい。
    static func root(containing url: URL) -> URL? {
        var current = url.standardizedFileURL
        if !FileTransfer.isDirectory(current) { current = current.deletingLastPathComponent() }
        while true {
            if FileManager.default.fileExists(atPath: current.appendingPathComponent(".git").path) {
                return current
            }
            guard current.path != "/" else { return nil }
            current = current.deletingLastPathComponent()
        }
    }

    /// folder がリポジトリのルート（中に .git がある）なら、今のブランチ名。git を起動せず HEAD を直接読む（一覧の各フォルダに使うため）。
    /// ブランチにいないときは「(1a2b3c4)」のようにコミットの先頭 7 文字
    static func headBranch(ofRepositoryAt folder: URL) -> String? {
        guard let gitDir = gitDirectory(ofRepositoryAt: folder) else { return nil }
        guard let gitDir, let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8) else { return "" }
        return branchName(fromHEAD: head)
    }

    /// フォルダの直下の .git が指す Git の管理フォルダ。.git がなければ nil、読めなければ .some(nil)
    private static func gitDirectory(ofRepositoryAt folder: URL) -> URL?? {
        let dotGit = folder.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue { return .some(dotGit) }
        // worktree・submodule は「gitdir: <場所>」と書かれたファイル
        guard let text = try? String(contentsOf: dotGit, encoding: .utf8),
              let line = text.split(separator: "\n").first, line.hasPrefix("gitdir:") else { return .some(nil) }
        let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        return .some(path.hasPrefix("/") ? URL(fileURLWithPath: path) : folder.appendingPathComponent(path))
    }

    /// フォルダの直下の .git の設定から、リモート（origin。なければ最初のもの）を Web で開く URL を読む。
    /// 一覧の行ごとに呼ぶので、git コマンドは使わずに設定ファイルを直に読む
    static func remoteWebURL(ofRepositoryAt folder: URL) -> URL? {
        guard let found = gitDirectory(ofRepositoryAt: folder), let gitDir = found else { return nil }
        var configDir = gitDir
        // worktree は、共通の管理フォルダ（commondir）に設定がある
        if let common = try? String(contentsOf: gitDir.appendingPathComponent("commondir"), encoding: .utf8) {
            let path = common.trimmingCharacters(in: .whitespacesAndNewlines)
            configDir = path.hasPrefix("/") ? URL(fileURLWithPath: path) : gitDir.appendingPathComponent(path)
        }
        guard let config = try? String(contentsOf: configDir.appendingPathComponent("config"), encoding: .utf8) else { return nil }
        return remoteURL(fromConfig: config).flatMap(webURL(fromRemote:))
    }

    /// .git/config の中身から、origin（なければ最初のリモート）の url を取り出す
    static func remoteURL(fromConfig config: String) -> String? {
        var current: String?
        var urls: [(name: String, url: String)] = []
        for raw in config.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                // [remote "origin"]
                if line.hasPrefix("[remote"), let open = line.firstIndex(of: "\""), let close = line.lastIndex(of: "\""), open < close {
                    current = String(line[line.index(after: open)..<close])
                } else {
                    current = nil
                }
            } else if let name = current, let equal = line.firstIndex(of: "=") {
                let key = line[..<equal].trimmingCharacters(in: .whitespaces).lowercased()
                if key == "url", !urls.contains(where: { $0.name == name }) {
                    urls.append((name, line[line.index(after: equal)...].trimmingCharacters(in: .whitespaces)))
                }
            }
        }
        return (urls.first { $0.name == "origin" } ?? urls.first)?.url
    }

    /// Web の URL から「持ち主/リポジトリ」
    static func repositoryName(of webURL: URL) -> String? {
        let parts = webURL.path.split(separator: "/")
        return parts.count >= 2 ? parts.suffix(2).joined(separator: "/") : nil
    }

    /// HEAD の中身「ref: refs/heads/main」→「main」、コミットの番号だけなら「(1a2b3c4)」
    static func branchName(fromHEAD head: String) -> String {
        let text = head.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("ref:") {
            let ref = text.dropFirst(4).trimmingCharacters(in: .whitespaces)
            return ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
        }
        return text.isEmpty ? "" : "(\(text.prefix(7)))"
    }

    /// リモートの URL を、ブラウザで開ける URL にする。
    /// 「git@github.com:持ち主/リポジトリ.git」「ssh://git@github.com/持ち主/リポジトリ.git」「https://ユーザー:トークン@github.com/持ち主/リポジトリ.git」
    /// → 「https://github.com/持ち主/リポジトリ」。ローカルのフォルダなどは nil
    static func webURL(fromRemote remote: String) -> URL? {
        var text = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        var host: String
        var path: String
        if let components = URLComponents(string: text), let scheme = components.scheme?.lowercased(),
           ["https", "http", "ssh", "git", "git+ssh", "ssh+git"].contains(scheme), let componentsHost = components.host {
            host = componentsHost
            path = components.path
        } else if !text.contains("://"), let colon = text.firstIndex(of: ":"), !text.hasPrefix("/") {
            // scp 形式: [ユーザー@]ホスト:パス
            var hostPart = String(text[..<colon])
            if let at = hostPart.lastIndex(of: "@") { hostPart = String(hostPart[hostPart.index(after: at)...]) }
            host = hostPart
            path = String(text[text.index(after: colon)...])
            text = ""
        } else {
            return nil
        }
        guard !host.isEmpty, !path.isEmpty else { return nil }
        if path.hasSuffix(".git") { path.removeLast(4) }
        if path.hasSuffix("/") { path.removeLast() }
        if !path.hasPrefix("/") { path = "/" + path }
        guard path.count > 1 else { return nil }
        return URL(string: "https://\(host)\(path)")
    }

    static func snapshot(root: URL) -> GitSnapshot? {
        guard let output = run(["-C", root.path, "status", "--porcelain=v1", "-z", "--branch", "--ignored"]) else {
            return nil
        }
        var snapshot = GitSnapshot.parse(output, root: root)
        // origin がなければ、最初に登録されたリモートを使う
        var remote = run(["-C", root.path, "remote", "get-url", "origin"])
        if remote == nil, let first = run(["-C", root.path, "remote"])?.split(separator: "\n").first {
            remote = run(["-C", root.path, "remote", "get-url", String(first)])
        }
        snapshot.remoteWebURL = remote.flatMap { webURL(fromRemote: $0) }
        return snapshot
    }

    /// git を実行して標準出力を返す。終了コードが allowedStatuses にないときは nil。
    /// lossy のときは UTF-8 でない部分を置き換えて読む（差分の中身用）
    static func run(_ arguments: [String], allowedStatuses: Set<Int32> = [0], lossy: Bool = false) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        // 表示のためだけに読むので、ほかの git 操作とロックを取り合わないようにする
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard allowedStatuses.contains(process.terminationStatus) else { return nil }
        if lossy { return String(decoding: data, as: UTF8.self) }
        return String(data: data, encoding: .utf8)
    }
}
