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
                snapshot.branch = branchName(fromHeader: String(record.dropFirst(3)))
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

    static func snapshot(root: URL) -> GitSnapshot? {
        guard let output = run(["-C", root.path, "status", "--porcelain=v1", "-z", "--branch", "--ignored"]) else {
            return nil
        }
        return GitSnapshot.parse(output, root: root)
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
