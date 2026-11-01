import Foundation

/// 差分を見るための、コミットしていない変更の1ファイル分。
nonisolated struct GitChange: Sendable, Equatable, Identifiable {
    /// リポジトリのルートからの相対パス（名前の変更なら新しい名前）
    var path: String
    /// 名前の変更の、元の名前
    var originalPath: String?
    var status: GitFileStatus

    var id: String { path }
    var fileName: String { (path as NSString).lastPathComponent }
    var folder: String { (path as NSString).deletingLastPathComponent }
}

/// 差分の1行。
nonisolated struct DiffLine: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case context, added, removed
        /// 「\ No newline at end of file」
        case note
    }

    var kind: Kind
    var oldNumber: Int?
    var newNumber: Int?
    var text: String
}

/// 差分のまとまり（@@ で始まる部分）。
nonisolated struct DiffHunk: Sendable, Equatable {
    var header: String
    var lines: [DiffLine]
}

/// 1ファイル分の差分。
nonisolated struct FileDiff: Sendable, Equatable {
    var hunks: [DiffHunk] = []
    var isBinary = false
    /// 長すぎて途中で打ち切った
    var isTruncated = false

    var addedCount: Int { hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .added }.count } }
    var removedCount: Int { hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .removed }.count } }

    /// 表示する行の上限（これを超えたら打ち切る）
    static let maxLines = 5000

    /// `git diff` の出力（unified 形式）を読む。
    static func parse(_ output: String) -> FileDiff {
        var diff = FileDiff()
        var current: DiffHunk?
        var oldLine = 0
        var newLine = 0
        var total = 0

        func finishHunk() {
            if let hunk = current { diff.hunks.append(hunk) }
            current = nil
        }

        for raw in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("@@") {
                finishHunk()
                guard let numbers = hunkStart(line) else { continue }
                oldLine = numbers.old
                newLine = numbers.new
                current = DiffHunk(header: line, lines: [])
                continue
            }
            guard current != nil else {
                // ヘッダー部分（diff --git・index・---・+++ など）
                if line.hasPrefix("Binary files ") || line.hasPrefix("GIT binary patch") { diff.isBinary = true }
                continue
            }
            if total >= maxLines {
                diff.isTruncated = true
                break
            }
            if line.hasPrefix("+") {
                current?.lines.append(DiffLine(kind: .added, oldNumber: nil, newNumber: newLine, text: String(line.dropFirst())))
                newLine += 1
            } else if line.hasPrefix("-") {
                current?.lines.append(DiffLine(kind: .removed, oldNumber: oldLine, newNumber: nil, text: String(line.dropFirst())))
                oldLine += 1
            } else if line.hasPrefix(" ") {
                current?.lines.append(DiffLine(kind: .context, oldNumber: oldLine, newNumber: newLine, text: String(line.dropFirst())))
                oldLine += 1
                newLine += 1
            } else if line.hasPrefix("\\") {
                current?.lines.append(DiffLine(kind: .note, oldNumber: nil, newNumber: nil, text: String(line.dropFirst(2))))
            } else if line.hasPrefix("diff --git") {
                // 次のファイル（1ファイルずつ読むので通常は来ない）
                finishHunk()
                continue
            } else {
                // 出力の最後の空行など
                continue
            }
            total += 1
        }
        finishHunk()
        return diff
    }

    /// 「@@ -12,7 +12,8 @@ func a()」→ (12, 12)。行数が省かれた「@@ -1 +1 @@」も読む。
    static func hunkStart(_ header: String) -> (old: Int, new: Int)? {
        let parts = header.split(separator: " ")
        guard parts.count >= 3, parts[1].hasPrefix("-"), parts[2].hasPrefix("+") else { return nil }
        func start(_ part: Substring) -> Int? {
            Int(part.dropFirst().split(separator: ",").first ?? "")
        }
        guard let old = start(parts[1]), let new = start(parts[2]) else { return nil }
        // 「-0,0」のように空のファイルからの追加は 0 から始まるので、1行目を 1 にそろえる
        return (max(old, 1), max(new, 1))
    }
}

nonisolated extension GitRepository {
    /// 中身のない木（まだコミットがないリポジトリで、比べる相手にする）
    static let emptyTree = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

    /// コミットしていない変更の一覧。未追跡のフォルダは中のファイルを1つずつ並べる。
    static func changes(root: URL) -> [GitChange]? {
        guard let output = run(["-C", root.path, "status", "--porcelain=v1", "-z", "--untracked-files=all"]) else {
            return nil
        }
        return parseChanges(output)
    }

    /// `git status --porcelain=v1 -z` の出力から、変更の一覧を作る（パスの順）。
    static func parseChanges(_ output: String) -> [GitChange] {
        var changes: [GitChange] = []
        var records = output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)[...]
        while let record = records.popFirst() {
            guard !record.hasPrefix("## "), record.count > 3 else { continue }
            let code = Array(record.prefix(2))
            let path = String(record.dropFirst(3))
            var original: String?
            if code[0] == "R" || code[0] == "C" { original = records.popFirst() }

            let status: GitFileStatus
            switch (code[0], code[1]) {
            case ("?", "?"): status = .untracked
            case ("!", "!"): continue
            case ("U", _), (_, "U"), ("A", "A"), ("D", "D"): status = .conflicted
            case ("A", _): status = .added
            case ("R", _), ("C", _): status = .renamed
            case ("D", _), (_, "D"): status = .deleted
            default: status = .modified
            }
            changes.append(GitChange(path: path, originalPath: original, status: status))
        }
        return changes.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// 1ファイル分の、最後のコミットから今の中身までの差分（ステージ済みも、まだのものも含む）。
    static func diff(root: URL, change: GitChange) -> FileDiff {
        let output: String?
        if change.status == .untracked {
            // 未追跡のファイルは、空のファイルからの追加として見せる
            output = run(["-C", root.path, "diff", "--no-color", "--no-ext-diff", "--no-index", "--", "/dev/null", change.path],
                         allowedStatuses: [0, 1], lossy: true)
        } else {
            let base = run(["-C", root.path, "rev-parse", "--verify", "--quiet", "HEAD"]) == nil ? emptyTree : "HEAD"
            var paths = [change.path]
            if let original = change.originalPath { paths.insert(original, at: 0) }
            output = run(["-C", root.path, "diff", "--no-color", "--no-ext-diff", "-M", base, "--"] + paths, lossy: true)
        }
        return FileDiff.parse(output ?? "")
    }
}
