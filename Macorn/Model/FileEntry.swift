import Foundation

/// 1つのファイル・フォルダの情報。バックグラウンドで読み込むため値型にしている。
nonisolated struct FileEntry: Sendable, Hashable {
    let url: URL
    let name: String
    /// 中に入れるフォルダかどうか（.app などのパッケージは含まない）
    let isFolder: Bool
    let isPackage: Bool
    let isHidden: Bool
    let isSymbolicLink: Bool
    /// ファイルの大きさ。フォルダは計算が終わるまで nil（要件 V-09）
    var size: Int64?
    let dateModified: Date?
    let kind: String
    /// タグ別に並べるときの基準（付いているタグのうち名前の順で最初のもの）。タグが無ければ nil
    var tagSortKey: String? = nil
    /// Git リポジトリのフォルダ（中に .git がある）なら、今のブランチ名。読めなければ空文字
    var gitBranch: String? = nil
    /// Git リポジトリのフォルダで、リモートがあれば、それを Web で開く URL（GitHub など）
    var gitRemoteWebURL: URL? = nil

    var path: String { url.path }
}

/// フォルダの中身を読み込む。
nonisolated enum DirectoryReader {
    static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey,
        .isPackageKey,
        .isHiddenKey,
        .isSymbolicLinkKey,
        .fileSizeKey,
        .totalFileSizeKey,
        .contentModificationDateKey,
        .localizedTypeDescriptionKey,
    ]

    /// Finder でも常に非表示のファイル
    static let alwaysHiddenNames: Set<String> = [".DS_Store", ".localized"]

    static func read(_ url: URL, includeHidden: Bool) throws -> [FileEntry] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: includeHidden ? [] : [.skipsHiddenFiles]
        )
        return urls.compactMap { child in
            alwaysHiddenNames.contains(child.lastPathComponent) ? nil : entry(for: child)
        }
    }

    /// 呼び出し元のスレッドを止めないよう、別スレッドで読み込む。
    static func readInBackground(_ url: URL, includeHidden: Bool) async -> Result<[FileEntry], any Error> {
        await Task.detached(priority: .userInitiated) {
            Result { try read(url, includeHidden: includeHidden) }
        }.value
    }

    static func entry(for url: URL) -> FileEntry {
        let values = try? url.resourceValues(forKeys: Set(resourceKeys))
        let isSymbolicLink = values?.isSymbolicLink ?? false
        var isDirectory = values?.isDirectory ?? false
        if isSymbolicLink {
            // リンク先がフォルダなら、フォルダとして扱う
            var target: ObjCBool = false
            isDirectory = FileManager.default.fileExists(atPath: url.path, isDirectory: &target) && target.boolValue
        }
        let isPackage = values?.isPackage ?? false
        let size: Int64? = isDirectory ? nil : (values?.totalFileSize ?? values?.fileSize).map(Int64.init)
        let name = url.path == "/" ? "/" : url.lastPathComponent
        let gitBranch = isDirectory && !isPackage ? GitRepository.headBranch(ofRepositoryAt: url) : nil

        return FileEntry(
            url: url,
            name: name,
            isFolder: isDirectory && !isPackage,
            isPackage: isPackage,
            isHidden: values?.isHidden ?? name.hasPrefix("."),
            isSymbolicLink: isSymbolicLink,
            size: size,
            dateModified: values?.contentModificationDate,
            kind: values?.localizedTypeDescription ?? "",
            gitBranch: gitBranch,
            gitRemoteWebURL: gitBranch != nil ? GitRepository.remoteWebURL(ofRepositoryAt: url) : nil
        )
    }

    static func availableCapacity(for url: URL) async -> Int64? {
        await Task.detached(priority: .utility) {
            let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values?.volumeAvailableCapacityForImportantUsage
        }.value
    }
}
