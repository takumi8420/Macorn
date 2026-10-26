import Foundation
import Testing
@testable import Noxy

/// 一時フォルダに次の構成を作ってテストする。
///   alpha/  alphabet/  Beta/  .hidden/  alpine.txt
final class PathCompletionTests {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("noxy-tests-\(UUID().uuidString)")
        let fm = FileManager.default
        for name in ["alpha", "alphabet", "Beta", ".hidden"] {
            try fm.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try Data().write(to: root.appendingPathComponent("alpine.txt"))
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    @Test func completesToCommonPrefix() {
        #expect(PathCompletion.complete("al", relativeTo: root) == "alpha")
    }

    @Test func completesSingleCandidateWithSlash() {
        #expect(PathCompletion.complete("alphab", relativeTo: root) == "alphabet/")
    }

    @Test func ignoresCase() {
        #expect(PathCompletion.complete("b", relativeTo: root) == "Beta/")
    }

    @Test func hiddenFoldersOnlyWhenTypingDot() {
        #expect(PathCompletion.complete(".h", relativeTo: root) == ".hidden/")
        #expect(PathCompletion.complete("", relativeTo: root) == "")
    }

    @Test func filesAreNotCandidates() {
        #expect(PathCompletion.complete("alpi", relativeTo: root) == "alpi")
    }

    @Test func returnsInputWhenNoMatch() {
        #expect(PathCompletion.complete("zz", relativeTo: root) == "zz")
    }

    @Test func completesAbsolutePath() {
        #expect(PathCompletion.complete(root.path + "/Be", relativeTo: URL(fileURLWithPath: "/")) == root.path + "/Beta/")
    }

    @Test func completesTildePath() {
        #expect(PathCompletion.complete("~/Be", relativeTo: URL(fileURLWithPath: "/"), home: root.path) == "~/Beta/")
        #expect(PathCompletion.complete("~", relativeTo: URL(fileURLWithPath: "/"), home: root.path) == "~/")
    }

    @Test func resolvesFoldersAndFiles() {
        let folder = PathCompletion.resolve("alpha", relativeTo: root)
        #expect(folder?.isDirectory == true)
        #expect(folder?.url.lastPathComponent == "alpha")

        let file = PathCompletion.resolve("alpine.txt", relativeTo: root)
        #expect(file?.isDirectory == false)

        #expect(PathCompletion.resolve("missing", relativeTo: root) == nil)
        #expect(PathCompletion.resolve("   ", relativeTo: root) == nil)
    }

    @Test func resolvesTildeAndParent() {
        let home = PathCompletion.resolve("~", relativeTo: URL(fileURLWithPath: "/"), home: root.path)
        #expect(home?.url.path == root.standardizedFileURL.path)

        let parent = PathCompletion.resolve("alpha/..", relativeTo: root)
        #expect(parent?.url.path == root.standardizedFileURL.path)
    }

    @Test func abbreviatesHome() {
        #expect(PathCompletion.abbreviate("/Users/me", home: "/Users/me") == "~")
        #expect(PathCompletion.abbreviate("/Users/me/repo", home: "/Users/me") == "~/repo")
        #expect(PathCompletion.abbreviate("/Users/meow", home: "/Users/me") == "/Users/meow")
    }
}
