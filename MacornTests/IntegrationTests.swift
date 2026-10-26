import Foundation
import Testing
@testable import Macorn

struct GitSnapshotTests {
    private let root = URL(fileURLWithPath: "/repo")

    @Test func parsesBranchAndStatuses() {
        let output = [
            "## main...origin/main [ahead 1]",
            " M src/app.swift",
            "A  src/new.swift",
            "?? notes.txt",
            "?? scratch/",
            "!! build/",
            "R  src/renamed.swift", "src/old.swift",
            "UU conflict.txt",
            " D gone.txt",
        ].joined(separator: "\0") + "\0"
        let snapshot = GitSnapshot.parse(output, root: root)

        #expect(snapshot.branch == "main")
        #expect(snapshot.status(for: root.appendingPathComponent("src/app.swift")) == .modified)
        #expect(snapshot.status(for: root.appendingPathComponent("src/new.swift")) == .added)
        #expect(snapshot.status(for: root.appendingPathComponent("notes.txt")) == .untracked)
        #expect(snapshot.status(for: root.appendingPathComponent("src/renamed.swift")) == .renamed)
        #expect(snapshot.status(for: root.appendingPathComponent("src/old.swift")) == nil)
        #expect(snapshot.status(for: root.appendingPathComponent("conflict.txt")) == .conflicted)
        #expect(snapshot.status(for: root.appendingPathComponent("gone.txt")) == .deleted)
        // フォルダごとの状態
        #expect(snapshot.status(for: root.appendingPathComponent("build/out/app")) == .ignored)
        #expect(snapshot.status(for: root.appendingPathComponent("scratch/a/b.txt")) == .untracked)
        #expect(snapshot.status(for: root.appendingPathComponent("src")) == .modified)
        #expect(snapshot.status(for: root.appendingPathComponent("README.md")) == nil)
        #expect(snapshot.changeCount == 7)
    }

    @Test func branchNames() {
        #expect(GitSnapshot.branchName(fromHeader: "feature/x...origin/feature/x [behind 2]") == "feature/x")
        #expect(GitSnapshot.branchName(fromHeader: "No commits yet on main") == "main")
        #expect(GitSnapshot.branchName(fromHeader: "HEAD (no branch)") == "(detached)")
        #expect(GitSnapshot.branchName(fromHeader: "dev") == "dev")
    }

    @Test func readsRealRepository() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("macorn-git-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("src"), withIntermediateDirectories: true)
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["-C", folder.path, "init", "-q", "-b", "trunk"]
        try git.run()
        git.waitUntilExit()
        try Data("x".utf8).write(to: folder.appendingPathComponent("src/a.txt"))

        #expect(GitRepository.root(containing: folder.appendingPathComponent("src"))?.path == folder.path)
        let snapshot = try #require(GitRepository.snapshot(root: folder))
        #expect(snapshot.branch == "trunk")
        #expect(snapshot.status(for: folder.appendingPathComponent("src/a.txt")) == .untracked)
    }

    @Test func noRepositoryOutsideGit() {
        #expect(GitRepository.root(containing: URL(fileURLWithPath: "/")) == nil)
    }
}

struct PathCopierTests {
    @Test func shellQuoting() {
        #expect(PathCopier.shellQuoted("/usr/local/bin") == "/usr/local/bin")
        #expect(PathCopier.shellQuoted("/tmp/My Files") == "'/tmp/My Files'")
        #expect(PathCopier.shellQuoted("/tmp/it's") == "'/tmp/it'\\''s'")
        #expect(PathCopier.shellQuoted("/tmp/日本語") == "'/tmp/日本語'")
    }

    @Test func joinsMultiplePathsWithNewlines() {
        let text = PathCopier.text(for: [URL(fileURLWithPath: "/a"), URL(fileURLWithPath: "/b")], style: .full)
        #expect(text == "/a\n/b")
    }

    @Test func tildeStyle() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(PathCopier.text(for: [home.appendingPathComponent("repo")], style: .tilde) == "~/repo")
    }

    @Test func relativeStyleNeedsRepository() {
        #expect(PathCopier.text(for: [URL(fileURLWithPath: "/usr/bin")], style: .relativeToRepository) == nil)
    }
}

struct CommandLineToolTests {
    @Test func installsExecutableScript() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("macorn-cli-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let installed = try #require(CommandLineTool.install(to: folder, showResult: false))
        #expect(FileManager.default.isExecutableFile(atPath: installed.path))
        let script = try String(contentsOf: installed, encoding: .utf8)
        #expect(script.hasPrefix("#!/bin/sh"))
        #expect(script.contains("open -b"))
    }
}
