import Foundation
import Testing
@testable import Macorn

/// 一時フォルダに次の構成を作り、サブフォルダも探す絞り込み（要件 S-04）を確かめる。
///   README.md
///   docs/Readme-ja.md
///   docs/guide/reading-list.txt
///   src/main.swift
///   .hidden/readme-secret.md
///   node_modules/readme-pkg/README.md
///   .git/README
///   Tool.app/Contents/README.txt
final class SubfolderSearchTests {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("macorn-tests-\(UUID().uuidString)")
        let files = [
            "README.md", "docs/Readme-ja.md", "docs/guide/reading-list.txt", "src/main.swift",
            ".hidden/readme-secret.md", "node_modules/readme-pkg/README.md", ".git/README",
            "Tool.app/Contents/README.txt",
        ]
        for file in files {
            let url = root.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func names(_ query: String, includeHidden: Bool = false, resultLimit: Int = 100) -> [String] {
        SubfolderSearch.search(in: root, query: query, includeHidden: includeHidden, resultLimit: resultLimit)
            .entries.map { SubfolderSearch.relativeLocation(of: $0.url, from: root) + "/" + $0.name }.sorted()
    }

    @Test func findsMatchesInSubfoldersIgnoringCase() {
        #expect(names("readme") == ["/README.md", "docs/Readme-ja.md"])
    }

    @Test func findsFoldersByName() {
        #expect(names("guide") == ["docs/guide"])
    }

    @Test func skipsHiddenItemsUnlessShown() {
        #expect(!names("secret").contains(".hidden/readme-secret.md"))
        #expect(names("secret", includeHidden: true) == [".hidden/readme-secret.md"])
    }

    @Test func doesNotLookInsideDependencyFoldersOrPackages() {
        // node_modules そのものは名前で見つかるが、中は探さない。.app の中も探さない
        #expect(names("node") == ["/node_modules"])
        #expect(names("readme-pkg").isEmpty)
        #expect(names(".txt") == ["docs/guide/reading-list.txt"])
        #expect(names("README", includeHidden: true).contains(".hidden/readme-secret.md"))
        #expect(!names("README", includeHidden: true).contains(".git/README"))
    }

    @Test func stopsAtResultLimit() {
        let result = SubfolderSearch.search(in: root, query: "e", includeHidden: false, resultLimit: 2)
        #expect(result.entries.count == 2)
        #expect(result.isTruncated)
    }

    @Test func stopsWhenCancelled() {
        let result = SubfolderSearch.search(in: root, query: "e", includeHidden: false, isCancelled: { true })
        #expect(result.entries.isEmpty)
        #expect(!result.isTruncated)
    }

    @Test func emptyQueryFindsNothing() {
        #expect(names("").isEmpty)
    }

    @Test func relativeLocation() {
        #expect(SubfolderSearch.relativeLocation(of: root.appendingPathComponent("a.txt"), from: root) == "")
        #expect(SubfolderSearch.relativeLocation(of: root.appendingPathComponent("docs/guide/a.txt"), from: root) == "docs/guide")
    }

    @Test func ignoresChangesInFoldersItDoesNotSearch() {
        let base = root.path
        #expect(SubfolderSearch.isRelevantChange(base, root: root, includeHidden: false))
        // /private/tmp の下を開いているとき、届くパスも /private/tmp で始まる
        let privateTmp = URL(fileURLWithPath: "/private/tmp/macorn-x")
        #expect(SubfolderSearch.isRelevantChange("/private/tmp/macorn-x/docs/", root: privateTmp, includeHidden: false))
        #expect(SubfolderSearch.isRelevantChange(base + "/docs/guide/", root: root, includeHidden: false))
        #expect(!SubfolderSearch.isRelevantChange(base + "/node_modules/x", root: root, includeHidden: false))
        #expect(!SubfolderSearch.isRelevantChange(base + "/.git/objects", root: root, includeHidden: true))
        #expect(!SubfolderSearch.isRelevantChange(base + "/.hidden", root: root, includeHidden: false))
        #expect(SubfolderSearch.isRelevantChange(base + "/.hidden", root: root, includeHidden: true))
        #expect(!SubfolderSearch.isRelevantChange("/somewhere/else", root: root, includeHidden: false))
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(!SubfolderSearch.isRelevantChange(home.path + "/Library/Caches", root: home, includeHidden: false))
    }

    @Test func backgroundSearchReturnsSameResult() async {
        let result = await SubfolderSearch.searchInBackground(in: root, query: "main", includeHidden: false)
        #expect(result.entries.map(\.name) == ["main.swift"])
    }
}
