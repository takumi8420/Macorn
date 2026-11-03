import Foundation
import Testing
@testable import Macorn

struct GitDiffTests {
    @Test func parsesHunksWithLineNumbers() {
        let output = """
        diff --git a/src/app.swift b/src/app.swift
        index 1111111..2222222 100644
        --- a/src/app.swift
        +++ b/src/app.swift
        @@ -3,4 +3,5 @@ import Foundation
         func greet() {
        -    print("a")
        +    print("b")
        +    print("c")
         }
        \\ No newline at end of file

        """
        let diff = FileDiff.parse(output)
        #expect(diff.hunks.count == 1)
        #expect(diff.addedCount == 2)
        #expect(diff.removedCount == 1)
        let lines = diff.hunks[0].lines
        #expect(lines.map(\.kind) == [.context, .removed, .added, .added, .context, .note])
        #expect(lines[0].oldNumber == 3 && lines[0].newNumber == 3)
        #expect(lines[1].oldNumber == 4 && lines[1].newNumber == nil)
        #expect(lines[2].newNumber == 4 && lines[3].newNumber == 5)
        #expect(lines[4].oldNumber == 5 && lines[4].newNumber == 6)
        #expect(lines[2].text == "    print(\"b\")")
    }

    @Test func readsHunkStarts() {
        #expect(FileDiff.hunkStart("@@ -12,7 +14,8 @@ func a()")! == (12, 14))
        #expect(FileDiff.hunkStart("@@ -1 +1 @@")! == (1, 1))
        // 空のファイルからの追加
        #expect(FileDiff.hunkStart("@@ -0,0 +1,3 @@")! == (1, 1))
        #expect(FileDiff.hunkStart("not a hunk") == nil)
    }

    @Test func detectsBinary() {
        let diff = FileDiff.parse("diff --git a/i.png b/i.png\nindex 1..2 100644\nBinary files a/i.png and b/i.png differ\n")
        #expect(diff.isBinary)
        #expect(diff.hunks.isEmpty)
    }

    @Test func truncatesLongDiffs() {
        let body = (0..<(FileDiff.maxLines + 10)).map { "+line \($0)" }.joined(separator: "\n")
        let diff = FileDiff.parse("@@ -0,0 +1,\(FileDiff.maxLines + 10) @@\n" + body)
        #expect(diff.isTruncated)
        #expect(diff.addedCount == FileDiff.maxLines)
    }

    @Test func parsesChangesWithRenames() {
        let output = [
            " M src/b.swift",
            "R  new.txt", "old.txt",
            "?? docs/readme.txt",
            "!! build/",
            " D a.txt",
        ].joined(separator: "\0") + "\0"
        let changes = GitRepository.parseChanges(output)
        #expect(changes.map(\.path) == ["a.txt", "docs/readme.txt", "new.txt", "src/b.swift"])
        #expect(changes.map(\.status) == [.deleted, .untracked, .renamed, .modified])
        #expect(changes[2].originalPath == "old.txt")
        #expect(changes[1].fileName == "readme.txt" && changes[1].folder == "docs")
    }

    @Test func readsRealRepositoryDiff() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("macorn-diff-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func git(_ arguments: String...) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", folder.path, "-c", "user.name=t", "-c", "user.email=t@example.com"] + arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
        }
        try git("init", "-q", "-b", "main")
        // コミットがまだないときも、未追跡・追加のファイルの差分を出せる
        try Data("one\ntwo\n".utf8).write(to: folder.appendingPathComponent("a.txt"))
        var changes = try #require(GitRepository.changes(root: folder))
        #expect(changes.map(\.path) == ["a.txt"])
        #expect(GitRepository.diff(root: folder, change: changes[0]).addedCount == 2)
        try git("add", "a.txt")
        changes = try #require(GitRepository.changes(root: folder))
        #expect(changes.first?.status == .added)
        #expect(GitRepository.diff(root: folder, change: changes[0]).addedCount == 2)

        try git("commit", "-q", "-m", "init")
        try Data("one\nTWO\nthree\n".utf8).write(to: folder.appendingPathComponent("a.txt"))
        changes = try #require(GitRepository.changes(root: folder))
        let diff = GitRepository.diff(root: folder, change: changes[0])
        #expect(changes[0].status == .modified)
        #expect(diff.addedCount == 2)
        #expect(diff.removedCount == 1)
    }
}

struct GitHeadTests {
    @Test func readsBranchFromHEAD() {
        #expect(GitRepository.branchName(fromHEAD: "ref: refs/heads/main\n") == "main")
        #expect(GitRepository.branchName(fromHEAD: "ref: refs/heads/feature/login\n") == "feature/login")
        #expect(GitRepository.branchName(fromHEAD: "1a2b3c4d5e6f7a8b9c0d\n") == "(1a2b3c4)")
    }

    @Test func detectsRepositoryFolders() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("macorn-head-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let repo = folder.appendingPathComponent("repo")
        let plain = folder.appendingPathComponent("plain")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        try Data("ref: refs/heads/dev\n".utf8).write(to: repo.appendingPathComponent(".git/HEAD"))
        // worktree のように .git がファイルのとき
        let worktree = folder.appendingPathComponent("wt")
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try Data("gitdir: ../repo/.git\n".utf8).write(to: worktree.appendingPathComponent(".git"))

        #expect(GitRepository.headBranch(ofRepositoryAt: repo) == "dev")
        #expect(GitRepository.headBranch(ofRepositoryAt: plain) == nil)
        #expect(GitRepository.headBranch(ofRepositoryAt: worktree) == "dev")
        #expect(DirectoryReader.entry(for: repo).gitBranch == "dev")
        #expect(DirectoryReader.entry(for: plain).gitBranch == nil)
    }
}

struct GitRemoteTests {
    @Test func convertsRemotesToWebURLs() {
        #expect(GitRepository.webURL(fromRemote: "git@github.com:takumi8420/Macorn.git")?.absoluteString == "https://github.com/takumi8420/Macorn")
        #expect(GitRepository.webURL(fromRemote: "https://github.com/takumi8420/Macorn.git\n")?.absoluteString == "https://github.com/takumi8420/Macorn")
        #expect(GitRepository.webURL(fromRemote: "https://user:token@github.com/a/b")?.absoluteString == "https://github.com/a/b")
        #expect(GitRepository.webURL(fromRemote: "ssh://git@github.com/a/b.git")?.absoluteString == "https://github.com/a/b")
        #expect(GitRepository.webURL(fromRemote: "git@gitlab.com:group/sub/project.git")?.absoluteString == "https://gitlab.com/group/sub/project")
        #expect(GitRepository.webURL(fromRemote: "/Users/me/repos/local.git") == nil)
        #expect(GitRepository.webURL(fromRemote: "") == nil)
    }

    @Test func namesRepositoryFromRemote() {
        var snapshot = GitSnapshot(root: URL(fileURLWithPath: "/work/macorn-local"), branch: "main")
        #expect(snapshot.repositoryName == "macorn-local")
        #expect(snapshot.remoteServiceName == nil)
        snapshot.remoteWebURL = URL(string: "https://github.com/takumi8420/Macorn")
        #expect(snapshot.repositoryName == "takumi8420/Macorn")
        #expect(snapshot.remoteServiceName == "GitHub")
        snapshot.remoteWebURL = URL(string: "https://gitlab.com/group/sub/project")
        #expect(snapshot.repositoryName == "sub/project")
        #expect(snapshot.remoteServiceName == "GitLab")
    }
}

struct GitConfigTests {
    @Test func readsOriginFromConfig() {
        let config = """
        [core]
        \trepositoryformatversion = 0
        [remote "upstream"]
        \turl = https://github.com/other/upstream.git
        [remote "origin"]
        \turl = git@github.com:takumi8420/Macorn.git
        \tfetch = +refs/heads/*:refs/remotes/origin/*
        [branch "main"]
        \tremote = origin
        """
        #expect(GitRepository.remoteURL(fromConfig: config) == "git@github.com:takumi8420/Macorn.git")
        #expect(GitRepository.remoteURL(fromConfig: "[remote \"fork\"]\n url = https://gitlab.com/a/b\n") == "https://gitlab.com/a/b")
        #expect(GitRepository.remoteURL(fromConfig: "[core]\n bare = false\n") == nil)
    }

    @Test func readsRemoteOfRepositoryFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("macorn-remote-\(UUID().uuidString)")
        let git = folder.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try "ref: refs/heads/main\n".write(to: git.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        #expect(GitRepository.remoteWebURL(ofRepositoryAt: folder) == nil)
        try "[remote \"origin\"]\n\turl = git@github.com:a/b.git\n".write(to: git.appendingPathComponent("config"), atomically: true, encoding: .utf8)
        #expect(GitRepository.remoteWebURL(ofRepositoryAt: folder)?.absoluteString == "https://github.com/a/b")
        #expect(GitRepository.headBranch(ofRepositoryAt: folder) == "main")
    }
}
