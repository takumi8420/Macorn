import Foundation

/// パス入力欄の「~ の展開」「補完」「入力したパスの解決」。
nonisolated enum PathCompletion {
    struct Target: Equatable {
        let url: URL
        let isDirectory: Bool
    }

    static var homePath: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    /// `~` を展開し、相対パスは base からのパスにする。末尾の `/` は残す。
    static func expand(_ input: String, relativeTo base: URL, home: String = homePath) -> String {
        if input == "~" { return home }
        if input.hasPrefix("~/") { return home + input.dropFirst(1) }
        if input.hasPrefix("/") { return input }
        if input.isEmpty { return base.path }
        let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
        return basePath + input
    }

    /// ホームフォルダ以下のパスを `~` から始まる形にする。
    static func abbreviate(_ path: String, home: String = homePath) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    /// 入力されたパスが指す場所。存在しなければ nil。
    static func resolve(
        _ input: String,
        relativeTo base: URL,
        home: String = homePath,
        fileManager: FileManager = .default
    ) -> Target? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let url = URL(fileURLWithPath: expand(trimmed, relativeTo: base, home: home)).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        return Target(url: url, isDirectory: isDirectory.boolValue)
    }

    /// Tab キーでの補完。候補が1つならその名前＋`/`、複数なら共通する部分まで補う。
    /// 候補がなければ入力をそのまま返す。対象はフォルダのみ。
    static func complete(
        _ input: String,
        relativeTo base: URL,
        home: String = homePath,
        fileManager: FileManager = .default
    ) -> String {
        if input == "~" { return "~/" }

        let directoryPart: String
        let partial: String
        if let slash = input.lastIndex(of: "/") {
            directoryPart = String(input[...slash])
            partial = String(input[input.index(after: slash)...])
        } else {
            directoryPart = ""
            partial = input
        }

        let directoryPath = expand(directoryPart, relativeTo: base, home: home)
        let names = (try? fileManager.contentsOfDirectory(atPath: directoryPath)) ?? []
        let lowerPartial = partial.lowercased()
        let candidates = names.filter { name in
            guard !name.hasPrefix(".") || partial.hasPrefix(".") else { return false }
            guard name.lowercased().hasPrefix(lowerPartial) else { return false }
            var isDirectory: ObjCBool = false
            let fullPath = (directoryPath as NSString).appendingPathComponent(name)
            return fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory) && isDirectory.boolValue
        }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        guard let first = candidates.first else { return input }
        if candidates.count == 1 { return directoryPart + first + "/" }

        let common = longestCommonPrefix(candidates)
        return directoryPart + (common.count > partial.count ? common : partial)
    }

    /// 大文字・小文字を区別しない共通部分。表記は最初の候補に合わせる。
    static func longestCommonPrefix(_ strings: [String]) -> String {
        guard let first = strings.first else { return "" }
        var result = ""
        for (offset, character) in first.enumerated() {
            let lower = character.lowercased()
            let allMatch = strings.dropFirst().allSatisfy { other in
                guard offset < other.count else { return false }
                let index = other.index(other.startIndex, offsetBy: offset)
                return other[index].lowercased() == lower
            }
            guard allMatch else { break }
            result.append(character)
        }
        return result
    }

    /// あるフォルダと同じ階層にあるフォルダ（パンくずの右クリックメニュー用）。
    static func siblingFolders(of url: URL, includeHidden: Bool, limit: Int = 300) -> [URL] {
        let parent = url.deletingLastPathComponent()
        guard url.path != "/" else { return [] }
        let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        let children = (try? FileManager.default.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: options
        )) ?? []
        return children
            .filter { child in
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                return values?.isDirectory == true && values?.isPackage != true
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .prefix(limit)
            .map { $0 }
    }
}
