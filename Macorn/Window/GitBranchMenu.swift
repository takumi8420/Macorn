import AppKit

/// ブランチの切り替え・作成と、リモートとの同期（GitHub Desktop の上のブランチの欄と「Fetch / Pull / Push」のボタン）。
/// 確認や失敗の知らせはアラートで出し、うまくいったら開いている画面の Git の状態を読み直させる
@MainActor
enum GitOperations {
    /// root のリポジトリのブランチのメニューを出す。view が nil なら、マウスの位置（画面の座標）に出す
    static func showBranchMenu(root: URL, in view: NSView? = nil, at point: NSPoint? = nil) {
        Task {
            let branches = await Task.detached(priority: .userInitiated) { GitActions.branches(root: root) }.value
            let menu = branchMenu(root: root, branches: branches)
            if let view {
                menu.popUp(positioning: nil, at: point ?? .zero, in: view)
            } else {
                menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            }
        }
    }

    static func branchMenu(root: URL, branches: GitBranches) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let header = NSMenuItem(title: "ブランチを切り替える", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for name in branches.local {
            let item = ClosureMenuItem.make(title: name) { switchBranch(name, root: root) }
            item.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil)
            if name == branches.current {
                item.state = .on
                item.isEnabled = false
            }
            menu.addItem(item)
        }
        if !branches.remote.isEmpty {
            let remote = NSMenuItem(title: "リモートのブランチ", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for name in branches.remote {
                submenu.addItem(ClosureMenuItem.make(title: name) { switchBranch(name, root: root) })
            }
            remote.submenu = submenu
            menu.addItem(remote)
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem.make(title: "新しいブランチ…") { createBranch(root: root) })
        menu.addItem(.separator())
        for action in SyncAction.available(for: branches) {
            menu.addItem(ClosureMenuItem.make(title: action.title(for: branches)) { sync(action, root: root) })
        }
        return menu
    }

    // MARK: ブランチ

    static func switchBranch(_ branch: String, root: URL) {
        Task {
            let changes = await Task.detached { GitRepository.changes(root: root) ?? [] }.value
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
                GitActions.switchBranch(branch, root: root, changes: mode)
            }
        }
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
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
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
