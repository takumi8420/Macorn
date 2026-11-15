import Testing
@testable import Macorn

/// ブランチを選ぶポップオーバーに並べる項目
@MainActor struct BranchPickerTests {
    private var branches: GitBranches {
        var b = GitBranches()
        b.current = "main"
        b.local = ["docs/readme", "feature/login", "main"]
        b.remote = ["origin/feature/search"]
        b.worktrees = ["docs/readme": GitWorktree(path: "/tmp/wt", isMissing: false)]
        return b
    }

    @Test func listsCurrentLocalRemoteThenCreate() {
        let entries = BranchPickerView.entries(for: branches, query: "")
        #expect(entries.map(\.kind) == [.current, .local, .local, .remote, .createPrompt])
        #expect(entries[1].worktree?.path == "/tmp/wt")
        #expect(BranchPickerView.sectionTitle(entries, at: 0) == "今のブランチ")
        #expect(BranchPickerView.sectionTitle(entries, at: 1) == "ローカルのブランチ")
        #expect(BranchPickerView.sectionTitle(entries, at: 2) == nil)
        #expect(BranchPickerView.sectionTitle(entries, at: 3) == "リモートのブランチ")
    }

    /// 打った文字で絞り込み（大文字・小文字は区別しない）、同じ名前のローカルのブランチがなければ作る項目を最後に出す
    @Test func filtersAndOffersToCreate() {
        let entries = BranchPickerView.entries(for: branches, query: "FEATURE")
        #expect(entries.map(\.name) == ["feature/login", "origin/feature/search", "FEATURE"])
        #expect(entries.last?.kind == .create)
        let exact = BranchPickerView.entries(for: branches, query: "feature/login")
        #expect(exact.map(\.kind) == [.local])
    }
}
