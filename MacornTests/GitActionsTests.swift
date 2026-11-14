import Foundation
import Testing
@testable import Macorn

/// ブランチの作成・切り替え、選んだファイルのコミット、プッシュ・プル（手元に作ったリモートで確かめる）
struct GitActionsTests {
    /// 一時フォルダのリポジトリ。コミットする人の名前は、そのリポジトリの設定に書く（普段の設定は使わない）
    private struct Repo {
        let url: URL

        init(_ name: String, bare: Bool = false) throws {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("macorn-\(name)-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            git(bare ? ["init", "-q", "--bare", "-b", "main"] : ["init", "-q", "-b", "main"])
            if !bare {
                git(["config", "user.name", "t"])
                git(["config", "user.email", "t@example.com"])
                git(["config", "commit.gpgsign", "false"])
            }
        }

        @discardableResult
        func git(_ arguments: [String]) -> GitCommandResult {
            GitActions.run(arguments, in: url)
        }

        func write(_ text: String, to path: String) throws {
            try Data(text.utf8).write(to: url.appendingPathComponent(path))
        }

        func remove() { try? FileManager.default.removeItem(at: url) }
    }

    @Test func readsAheadAndBehindFromStatusHeader() {
        #expect(GitSnapshot.aheadBehind(fromHeader: "main...origin/main [ahead 1, behind 2]") == (1, 2))
        #expect(GitSnapshot.aheadBehind(fromHeader: "main...origin/main [behind 3]") == (0, 3))
        #expect(GitSnapshot.aheadBehind(fromHeader: "main") == (0, 0))
    }

    /// 選んだファイルだけがコミットされ、ほかの変更は残る。新しいファイル・名前の変更も含められる
    @Test func commitsOnlySelectedFiles() throws {
        let repo = try Repo("commit")
        defer { repo.remove() }
        try repo.write("a\n", to: "a.txt")
        try repo.write("b\n", to: "b.txt")
        #expect(GitActions.commit(paths: ["a.txt", "b.txt"], summary: "最初", description: "", root: repo.url).succeeded)

        try repo.write("a2\n", to: "a.txt")
        try repo.write("b2\n", to: "b.txt")
        try repo.write("new\n", to: "new.txt")
        let result = GitActions.commit(paths: ["a.txt", "new.txt"], summary: "a と new", description: "説明の行", root: repo.url)
        #expect(result.succeeded, "\(result.message)")
        #expect(GitRepository.changes(root: repo.url)?.map(\.path) == ["b.txt"])
        #expect(repo.git(["log", "-1", "--format=%s%n%b"]).output.contains("a と new\n説明の行"))
        #expect(!GitActions.commit(paths: [], summary: "空", description: "", root: repo.url).succeeded)
    }

    /// ブランチを作って切り替え、変更を退避して戻る。リモートのブランチは、同じ名前のローカルのブランチを作って追いかける
    @Test func createsAndSwitchesBranches() throws {
        let remote = try Repo("remote", bare: true)
        let repo = try Repo("branch")
        defer {
            remote.remove()
            repo.remove()
        }
        try repo.write("a\n", to: "a.txt")
        #expect(GitActions.commit(paths: ["a.txt"], summary: "init", description: "", root: repo.url).succeeded)
        repo.git(["remote", "add", "origin", remote.url.path])

        // まだリモートにないので、プッシュは「公開」になる
        var branches = GitActions.branches(root: repo.url)
        #expect(branches.current == "main")
        #expect(branches.upstream == nil)
        #expect(branches.defaultRemote == "origin")
        #expect(GitOperations.SyncAction.available(for: branches) == [.push, .fetch])
        #expect(GitActions.push(root: repo.url, branches: branches).succeeded)
        branches = GitActions.branches(root: repo.url)
        #expect(branches.upstream == "origin/main")

        #expect(GitActions.isValidBranchName("feature/login", root: repo.url))
        #expect(!GitActions.isValidBranchName("bad..name", root: repo.url))
        #expect(!GitActions.isValidBranchName("", root: repo.url))
        #expect(GitActions.createBranch("feature/login", root: repo.url).succeeded)
        #expect(GitActions.branches(root: repo.url).current == "feature/login")
        #expect(GitActions.push(root: repo.url, branches: GitActions.branches(root: repo.url)).succeeded)

        // 変更を退避して main に戻る
        try repo.write("changed\n", to: "a.txt")
        #expect(GitActions.switchBranch("main", root: repo.url, changes: .stash).succeeded)
        branches = GitActions.branches(root: repo.url)
        #expect(branches.current == "main")
        #expect(GitRepository.changes(root: repo.url)?.isEmpty == true)
        #expect(repo.git(["stash", "list"]).output.contains("feature/login から切り替える前の変更"))

        // ローカルの feature/login を消すと、リモートのブランチとして並び、選ぶと追いかけるブランチができる
        repo.git(["branch", "-D", "feature/login"])
        branches = GitActions.branches(root: repo.url)
        #expect(branches.remote == ["origin/feature/login"])
        #expect(GitActions.switchBranch("origin/feature/login", root: repo.url, changes: .bring).succeeded)
        branches = GitActions.branches(root: repo.url)
        #expect(branches.current == "feature/login")
        #expect(branches.upstream == "origin/feature/login")
    }

    /// ほかの人がプッシュしたコミットを、フェッチして遅れを数え、プルで取り込む
    @Test func fetchesAndPulls() throws {
        let remote = try Repo("remote", bare: true)
        let repo = try Repo("me")
        let other = try Repo("other")
        defer {
            remote.remove()
            repo.remove()
            other.remove()
        }
        try repo.write("a\n", to: "a.txt")
        #expect(GitActions.commit(paths: ["a.txt"], summary: "init", description: "", root: repo.url).succeeded)
        repo.git(["remote", "add", "origin", remote.url.path])
        #expect(GitActions.push(root: repo.url, branches: GitActions.branches(root: repo.url)).succeeded)

        other.git(["remote", "add", "origin", remote.url.path])
        other.git(["pull", "-q", "origin", "main"])
        other.git(["branch", "--set-upstream-to=origin/main", "main"])
        try other.write("b\n", to: "b.txt")
        #expect(GitActions.commit(paths: ["b.txt"], summary: "b", description: "", root: other.url).succeeded)
        #expect(GitActions.push(root: other.url, branches: GitActions.branches(root: other.url)).succeeded)

        #expect(GitActions.fetch(root: repo.url).succeeded)
        let branches = GitActions.branches(root: repo.url)
        #expect(branches.behind == 1)
        #expect(GitOperations.SyncAction.available(for: branches).first == .pull)
        #expect(GitActions.pull(root: repo.url).succeeded)
        #expect(FileManager.default.fileExists(atPath: repo.url.appendingPathComponent("b.txt").path))
        #expect(GitActions.branches(root: repo.url).behind == 0)
    }
}
