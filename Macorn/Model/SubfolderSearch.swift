import Foundation
import os

/// 表示中のフォルダの下を、サブフォルダまでたどって名前で探す（要件 S-04 の「サブフォルダも」）。
/// 画面を止めないよう、バックグラウンドで呼ぶ。
nonisolated enum SubfolderSearch {
    struct Result: Sendable {
        var entries: [FileEntry]
        /// 見つかった数か、たどった数が上限に達して、途中でやめた
        var isTruncated: Bool
    }

    /// 一覧に出す数の上限（多すぎると一覧が重くなり、探す意味も薄れる）
    static let resultLimit = 1000
    /// たどる項目の数の上限（ホームフォルダなど、とても大きいフォルダで止まらないように）
    static let visitLimit = 300_000

    /// 中まではたどらないフォルダ。名前では見つかるが、中身は探さない（依存関係・ビルドの出力・Git の中身など）
    static let skippedFolderNames: Set<String> = [
        ".git", ".svn", ".hg", "node_modules", ".build", "DerivedData", "Pods",
        ".venv", "venv", "__pycache__", ".next", ".nuxt", ".gradle", ".terraform",
        ".Trash",
    ]
    /// 中まではたどらない場所（ホームの「ライブラリ」は項目がとても多く、ふだん探すものでもない）
    static let skippedFolderPaths: Set<String> = [
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library").standardizedFileURL.path,
    ]

    /// 名前が入力した文字を含むか（大文字・小文字、濁点の有無、全角・半角を区別しない）。表示中のフォルダの絞り込みと同じ基準
    static func matches(_ name: String, query: String) -> Bool {
        name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil
    }

    /// `root` の下（直下も含む）から、名前が `query` を含む項目を探す。
    /// `isCancelled` が true を返したら途中でやめ、それまでに見つかったものを返す。
    static func search(
        in root: URL,
        query: String,
        includeHidden: Bool,
        resultLimit: Int = resultLimit,
        visitLimit: Int = visitLimit,
        isCancelled: () -> Bool = { false }
    ) -> Result {
        guard !query.isEmpty else { return Result(entries: [], isTruncated: false) }
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !includeHidden { options.insert(.skipsHiddenFiles) }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: options,
            errorHandler: { _, _ in true } // 読めないフォルダは飛ばして続ける
        ) else { return Result(entries: [], isTruncated: false) }

        var entries: [FileEntry] = []
        var visited = 0
        while let url = enumerator.nextObject() as? URL {
            visited += 1
            if visited % 500 == 1, isCancelled() { break } // 最初と、500 件ごとに確かめる
            if visited > visitLimit { return Result(entries: entries, isTruncated: true) }
            let name = url.lastPathComponent
            if DirectoryReader.alwaysHiddenNames.contains(name) { continue }
            if skippedFolderNames.contains(name) || skippedFolderPaths.contains(url.standardizedFileURL.path),
               (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                enumerator.skipDescendants()
            }
            guard matches(name, query: query) else { continue }
            if entries.count >= resultLimit { return Result(entries: entries, isTruncated: true) }
            entries.append(DirectoryReader.entry(for: url))
        }
        return Result(entries: entries, isTruncated: false)
    }

    /// 別のスレッドで探す。呼び出し元の Task が取り消されたら、探すのも途中でやめる
    static func searchInBackground(in root: URL, query: String, includeHidden: Bool) async -> Result {
        let cancelled = OSAllocatedUnfairLock(initialState: false)
        return await withTaskCancellationHandler {
            await Task.detached(priority: .userInitiated) {
                search(in: root, query: query, includeHidden: includeHidden, isCancelled: { cancelled.withLock { $0 } })
            }.value
        } onCancel: {
            cancelled.withLock { $0 = true }
        }
    }

    /// フォルダの変更（FSEvents のパス）が、探した結果に関わりうるか。
    /// 探さない場所（ライブラリ・node_modules・隠しフォルダなど）の中の変更では探し直さない
    /// 届くパスは /private/tmp のような実体のパスのことがあるので、root は標準化せずにそのまま比べる（呼び出し側が両方の形で呼ぶ）
    static func isRelevantChange(_ path: String, root: URL, includeHidden: Bool) -> Bool {
        let base = root.path.count > 1 && root.path.hasSuffix("/") ? String(root.path.dropLast()) : root.path
        let path = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        guard path == base || path.hasPrefix(base == "/" ? "/" : base + "/") else { return false }
        if skippedFolderPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return false }
        let components = path.dropFirst(base.count).split(separator: "/")
        for component in components {
            if skippedFolderNames.contains(String(component)) { return false }
            if !includeHidden, component.hasPrefix(".") { return false }
        }
        return true
    }

    /// 項目の場所を、表示中のフォルダからの相対パスで表す（直下なら空文字）
    static func relativeLocation(of url: URL, from root: URL) -> String {
        let base = root.standardizedFileURL.path
        let parent = url.deletingLastPathComponent().standardizedFileURL.path
        let prefix = base.hasSuffix("/") ? base : base + "/"
        if parent == base { return "" }
        if parent.hasPrefix(prefix) { return String(parent.dropFirst(prefix.count)) }
        return PathCompletion.abbreviate(parent)
    }
}
