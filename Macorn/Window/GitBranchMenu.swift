import AppKit

/// ブランチの切り替え・作成と、リモートとの同期（GitHub Desktop の上のブランチの欄と「Fetch / Pull / Push」のボタン）。
/// 選ぶ画面は BranchPickerView（パスバーのブランチのボタンから出すポップオーバー）。
/// 確認や失敗の知らせはアラートで出し、うまくいったら開いている画面の Git の状態を読み直させる
@MainActor
enum GitOperations {
    // MARK: ブランチ

    /// detach のときは、ブランチから切り離してそのコミットを見る（ほかのワークツリーで使っているブランチを見るため）
    static func switchBranch(_ branch: String, root: URL, detach: Bool = false) {
        Task {
            let (changes, worktree) = await Task.detached {
                (GitRepository.changes(root: root) ?? [], GitActions.branches(root: root).worktrees[branch])
            }.value
            if let worktree, !detach {
                handleBranchInWorktree(branch, worktree: worktree, root: root)
                return
            }
            var pending = GitActions.PendingChanges.bring
            if !changes.isEmpty {
                let alert = NSAlert()
                alert.messageText = "コミットしていない変更が \(changes.count) 件あります"
                alert.informativeText = "「\(branch)」へ切り替える前に、変更をどうしますか。\n持っていく：変更をそのまま切り替え先へ持っていきます（ぶつかるときは切り替えません）。\n退避する：今のブランチに退避（stash）してから切り替えます。退避した変更は git stash pop で戻せます。"
                alert.addButton(withTitle: "持っていく")
                alert.addButton(withTitle: "退避する")
                alert.addButton(withTitle: "やめる")
                switch alert.runModal() {
                case .alertFirstButtonReturn: pending = .bring
                case .alertSecondButtonReturn: pending = .stash
                default: return
                }
            }
            let mode = pending
            await perform(root: root, failure: "「\(branch)」に切り替えられませんでした") {
                GitActions.switchBranch(branch, root: root, changes: mode, detach: detach)
            }
        }
    }

    /// ほかのワークツリーで使っているブランチを選んだとき。git は同じブランチを2か所で使わせないので、
    /// 変更のないワークツリーは外してから切り替え、変更があればそのフォルダを Macorn で開く。フォルダが消えていれば記録を片付けてから切り替える
    static func handleBranchInWorktree(_ branch: String, worktree: GitWorktree, root: URL) {
        let alert = NSAlert()
        if worktree.isMissing {
            alert.messageText = "「\(branch)」は、消えたワークツリーの記録に残っています"
            alert.informativeText = "このブランチを使っていたフォルダはもうありませんが、git に記録が残っているため切り替えられません。\n記録を片付けて（git worktree prune）から切り替えますか。\n\nフォルダ：\(worktree.path)"
            alert.addButton(withTitle: "片付けて切り替える")
            alert.addButton(withTitle: "やめる")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            Task {
                let pruned = await perform(root: root, failure: "ワークツリーの記録を片付けられませんでした") {
                    GitActions.pruneWorktrees(root: root)
                }
                if pruned { switchBranch(branch, root: root) }
            }
        } else if worktree.isRemovable {
            alert.messageText = "「\(branch)」は別のワークツリーで使われています"
            alert.informativeText = "git は同じブランチを2つのフォルダで同時に使えないため、このままでは切り替えられません。\nそのワークツリーにはコミットしていない変更がないので、外して（git worktree remove）からここで切り替えられます。コミットはブランチに残ります。git で無視しているファイル（ビルドの出力など）はフォルダと一緒に消えます。\n\nフォルダ：\(worktree.path)"
            alert.informativeText += "\n\n\(viewHereNote)"
            alert.addButton(withTitle: "外して切り替える")
            alert.addButton(withTitle: "ここで見る")
            alert.addButton(withTitle: "そのフォルダを開く")
            alert.addButton(withTitle: "やめる")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                Task {
                    let removed = await perform(root: root, failure: "ワークツリーを外せませんでした") {
                        GitActions.removeWorktree(path: worktree.path, root: root)
                    }
                    if removed { switchBranch(branch, root: root) }
                }
            case .alertSecondButtonReturn:
                switchBranch(branch, root: root, detach: true)
            case .alertThirdButtonReturn:
                openWorktree(worktree)
            default:
                return
            }
        } else {
            alert.messageText = "「\(branch)」は別のワークツリーで使われています"
            let changes = worktree.changeCount.map { "そのワークツリーにはコミットしていない変更が \($0) 件あるため、外さずに残しています。" } ?? ""
            alert.informativeText = "git は同じブランチを2つのフォルダで同時に使えないため、ここでは切り替えられません。\(changes)\n\nフォルダ：\(worktree.path)\n\n\(viewHereNote)"
            alert.addButton(withTitle: "ここで見る")
            alert.addButton(withTitle: "そのフォルダを開く")
            alert.addButton(withTitle: "やめる")
            switch alert.runModal() {
            case .alertFirstButtonReturn: switchBranch(branch, root: root, detach: true)
            case .alertSecondButtonReturn: openWorktree(worktree)
            default: return
            }
        }
    }

    /// 「ここで見る」の説明（確認の画面に添える）
    private static let viewHereNote = "ここで見る：このフォルダを、そのブランチの最新のコミットへ切り離して切り替えます（git switch --detach）。ワークツリーにもブランチにも触れないので、そちらの作業には影響しません。見えるのはコミットされた中身だけで、あとからのコミットは選び直すまで出ません。見終わったら、ほかのブランチを選べば戻れます。"

    private static func openWorktree(_ worktree: GitWorktree) {
        NSApp.delegate?.application?(NSApp, open: [URL(fileURLWithPath: worktree.path, isDirectory: true)])
    }

    static func createBranch(root: URL) {
        let alert = NSAlert()
        alert.messageText = "新しいブランチ"
        alert.informativeText = "今のコミットから作って切り替えます。コミットしていない変更は、そのまま持っていきます。"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "feature/新しい機能"
        alert.accessoryView = field
        alert.addButton(withTitle: "作る")
        alert.addButton(withTitle: "やめる")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        createBranch(named: field.stringValue, root: root)
    }

    /// 名前を決めて、今のコミットから新しいブランチを作って切り替える
    static func createBranch(named rawName: String, root: URL) {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        Task {
            let valid = await Task.detached { GitActions.isValidBranchName(name, root: root) }.value
            guard valid else {
                showError("「\(name)」はブランチの名前に使えません", detail: "空白・「..」・「~」「^」「:」などは使えません。")
                return
            }
            await perform(root: root, failure: "ブランチ「\(name)」を作れませんでした") {
                GitActions.createBranch(name, root: root)
            }
        }
    }

    // MARK: 同期

    enum SyncAction: Sendable {
        case fetch, pull, push

        /// GitHub Desktop と同じく、遅れていればプル、進んでいればプッシュ、まだリモートになければ公開を出す。フェッチはいつも出す
        static func available(for branches: GitBranches) -> [SyncAction] {
            guard branches.defaultRemote != nil, branches.current != nil else { return [] }
            var actions: [SyncAction] = []
            if branches.behind > 0 { actions.append(.pull) }
            if branches.upstream == nil || branches.ahead > 0 { actions.append(.push) }
            actions.append(.fetch)
            return actions
        }

        func title(for branches: GitBranches) -> String {
            switch self {
            case .fetch: "フェッチ（リモートの変更を確かめる）"
            case .pull: "プル（\(branches.behind) 件を取り込む）"
            case .push: branches.upstream == nil ? "公開する（リモートにブランチを作ってプッシュ）" : "プッシュ（\(branches.ahead) 件を送る）"
            }
        }
    }

    static func sync(_ action: SyncAction, root: URL) {
        Task {
            switch action {
            case .fetch:
                await perform(root: root, failure: "フェッチできませんでした") { GitActions.fetch(root: root) }
            case .pull:
                await perform(root: root, failure: "プルできませんでした") { GitActions.pull(root: root) }
            case .push:
                await perform(root: root, failure: "プッシュできませんでした") {
                    GitActions.push(root: root, branches: GitActions.branches(root: root))
                }
            }
        }
    }

    // MARK: 実行と知らせ

    /// 処理中のリポジトリ（ボタンを押し直して二重に動かさないため）
    private(set) static var busyRoots: Set<String> = []

    static func isBusy(_ root: URL) -> Bool { busyRoots.contains(root.standardizedFileURL.path) }

    /// 裏で git を動かし、失敗したらアラートを出す。終わったら画面に読み直させる
    @discardableResult
    static func perform(root: URL, failure: String, _ work: @escaping @Sendable () -> GitCommandResult) async -> Bool {
        let key = root.standardizedFileURL.path
        guard !busyRoots.contains(key) else {
            NSSound.beep()
            return false
        }
        busyRoots.insert(key)
        NotificationCenter.default.post(name: .macornGitRepositoryChanged, object: root)
        let result = await Task.detached(priority: .userInitiated, operation: work).value
        busyRoots.remove(key)
        NotificationCenter.default.post(name: .macornGitRepositoryChanged, object: root)
        if !result.succeeded {
            showError(failure, detail: result.message)
        }
        return result.succeeded
    }

    static func showError(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }
}
