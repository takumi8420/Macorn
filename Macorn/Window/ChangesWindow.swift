import AppKit
import SwiftUI

/// Git の変更のウィンドウ（GitHub Desktop の「Changes」のように、左に変更のあるファイル、右に差分）。
/// 左上でブランチの切り替え・作成とリモートとの同期、左下で選んだファイルのコミットができる。
/// 変更の取り消し・履歴は扱わない。リポジトリごとに1つ。
final class ChangesWindowController: NSWindowController, NSWindowDelegate {
    private static var controllers: [String: ChangesWindowController] = [:]

    let model: ChangesModel

    /// root のリポジトリの変更のウィンドウを開く（開いていれば前に出して読み直す）。
    /// activate が false のときはキーにしない（自動操作用）
    @discardableResult
    /// selecting にリポジトリのルートからの相対パスを渡すと、そのファイル（フォルダならその中の最初の変更）を選んで開く
    static func show(root: URL, selecting: String? = nil, activate: Bool = true) -> ChangesWindowController {
        let key = root.standardizedFileURL.path
        let controller = controllers[key] ?? ChangesWindowController(root: root)
        controllers[key] = controller
        if activate {
            controller.showWindow(nil)
        } else {
            controller.window?.orderFront(nil)
        }
        controller.model.reload(selecting: selecting)
        return controller
    }

    static var open: [ChangesWindowController] { Array(controllers.values) }

    private init(root: URL) {
        model = ChangesModel(root: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "変更 — \(root.lastPathComponent)"
        window.minSize = NSSize(width: 640, height: 400)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: ChangesView(model: model))
        window.setContentSize(NSSize(width: 1040, height: 700))
        window.setFrameAutosaveName("macorn.ChangesWindow")
        if window.frame.origin == .zero { window.center() }
        window.delegate = self
        // Macorn の中でブランチを切り替えたり、コミットしたりしたら読み直す
        NotificationCenter.default.addObserver(forName: .macornGitRepositoryChanged, object: nil, queue: .main) { [weak self] note in
            let changed = (note.object as? URL)?.standardizedFileURL.path
            MainActor.assumeIsolated {
                guard let self, changed == nil || changed == self.model.root.standardizedFileURL.path else { return }
                self.model.reload()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 前に出てきたら読み直す（ほかのアプリで編集したあとに戻ってきたときのため）
    func windowDidBecomeKey(_ notification: Notification) {
        model.reload()
    }

    func windowWillClose(_ notification: Notification) {
        Self.controllers[model.root.standardizedFileURL.path] = nil
    }
}

@MainActor @Observable
final class ChangesModel {
    let root: URL
    var branch: String?
    /// ブランチの一覧とリモートとの差（左上のブランチの欄と、同期のボタンに使う）
    var branches = GitBranches()
    var changes: [GitChange] = []
    /// コミットに含めないファイル（初めはすべて含める。新しく出てきたファイルも含める）
    var excludedPaths: Set<String> = []
    /// コミットの要約（1行目）と説明
    var summary = ""
    var commitDescription = ""
    var selectedPath: String?
    var diff: FileDiff?
    var isLoading = false
    var isLoadingDiff = false
    /// リポジトリを読めなかった
    var failed = false

    private var reloadToken = UUID()
    private var diffToken = UUID()

    init(root: URL) {
        self.root = root
    }

    var selectedChange: GitChange? {
        changes.first { $0.path == selectedPath }
    }

    func reload(selecting preferred: String? = nil) {
        let token = UUID()
        reloadToken = token
        isLoading = true
        let root = root
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                (GitRepository.changes(root: root), GitRepository.snapshot(root: root)?.branch, GitActions.branches(root: root))
            }.value
            guard token == reloadToken else { return }
            isLoading = false
            failed = result.0 == nil
            changes = result.0 ?? []
            branch = result.1
            branches = result.2
            excludedPaths.formIntersection(changes.map(\.path))
            // 一覧から開いたファイルがあればそれを選ぶ
            if let preferred,
               let match = changes.first(where: { $0.path == preferred || $0.path.hasPrefix(preferred + "/") }) {
                selectedPath = match.path
            }
            // 選んでいたファイルが残っていればそのまま、なければ先頭を選ぶ
            if selectedPath == nil || !changes.contains(where: { $0.path == selectedPath }) {
                selectedPath = changes.first?.path
            }
            loadDiff()
        }
    }

    // MARK: コミット

    var includedChanges: [GitChange] { changes.filter { !excludedPaths.contains($0.path) } }

    func isIncluded(_ change: GitChange) -> Bool { !excludedPaths.contains(change.path) }

    func setIncluded(_ included: Bool, _ change: GitChange) {
        if included { excludedPaths.remove(change.path) } else { excludedPaths.insert(change.path) }
    }

    /// すべて含める・すべて外す（一覧の上のチェックボックス）
    var allIncluded: Bool {
        get { !changes.isEmpty && excludedPaths.isEmpty }
        set { excludedPaths = newValue ? [] : Set(changes.map(\.path)) }
    }

    var canCommit: Bool {
        !summary.trimmingCharacters(in: .whitespaces).isEmpty && !includedChanges.isEmpty
            && !includedChanges.contains { $0.status == .conflicted } && !GitOperations.isBusy(root)
    }

    /// 選んだファイルだけをコミットする。うまくいったら要約と説明を空にする
    func commit() {
        guard canCommit else { return }
        let paths = includedChanges.flatMap { [$0.originalPath, $0.path].compactMap { $0 } }
        let summary = summary.trimmingCharacters(in: .whitespaces)
        let description = commitDescription
        let root = root
        Task {
            let succeeded = await GitOperations.perform(root: root, failure: "コミットできませんでした") {
                GitActions.commit(paths: paths, summary: summary, description: description, root: root)
            }
            if succeeded {
                self.summary = ""
                commitDescription = ""
            }
        }
    }

    func select(_ path: String?) {
        guard path != selectedPath else { return }
        selectedPath = path
        loadDiff()
    }

    private func loadDiff() {
        let token = UUID()
        diffToken = token
        guard let change = selectedChange else {
            diff = nil
            return
        }
        isLoadingDiff = true
        let root = root
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                GitRepository.diff(root: root, change: change)
            }.value
            guard token == diffToken else { return }
            isLoadingDiff = false
            diff = result
        }
    }
}

// MARK: - 画面

struct ChangesView: View {
    @Bindable var model: ChangesModel

    var body: some View {
        HSplitView {
            fileList
                .frame(minWidth: 220, idealWidth: 280, maxWidth: 360)
            diffPane
                .frame(minWidth: 360, maxWidth: .infinity)
        }
        .frame(minWidth: 640, minHeight: 400)
    }

    private var fileList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                // 押すとブランチの切り替え・作成・同期のメニュー（GitHub Desktop の上の「Current Branch」）
                Button {
                    GitOperations.showBranchMenu(root: model.root)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                        Text(model.branch ?? "ブランチ").lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                    }
                }
                .buttonStyle(.borderless)
                .help("ブランチを切り替える・作る（⇧⌘B）")
                Spacer()
                if model.isLoading || GitOperations.isBusy(model.root) { ProgressView().controlSize(.small) }
                SyncButton(model: model)
                Button {
                    model.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("r", modifiers: .command)
                .help("読み直す（⌘R）")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            HStack(spacing: 6) {
                if !model.changes.isEmpty {
                    Toggle("", isOn: $model.allIncluded)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .help("すべてコミットに含める・外す")
                }
                Text(model.changes.isEmpty ? "変更はありません" : "\(model.changes.count) 件の変更")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            Divider()

            List(selection: Binding(get: { model.selectedPath }, set: { model.select($0) })) {
                ForEach(model.changes) { change in
                    HStack(spacing: 6) {
                        Toggle("", isOn: Binding(get: { model.isIncluded(change) }, set: { model.setIncluded($0, change) }))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .help("コミットに含める")
                        ChangeRow(change: change)
                    }
                    .tag(change.path)
                }
            }
            .listStyle(.sidebar)
            if !model.changes.isEmpty {
                Divider()
                CommitBox(model: model)
            }
        }
    }

    @ViewBuilder
    private var diffPane: some View {
        if model.failed {
            placeholder("リポジトリの状態を読めませんでした", symbol: "exclamationmark.triangle")
        } else if let change = model.selectedChange {
            VStack(spacing: 0) {
                DiffHeader(change: change, diff: model.diff)
                Divider()
                if let diff = model.diff {
                    DiffBody(diff: diff, status: change.status)
                } else {
                    Spacer()
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        } else if !model.isLoading {
            placeholder("コミットしていない変更はありません", symbol: "checkmark.circle")
        } else {
            Color(nsColor: .textBackgroundColor)
        }
    }

    private func placeholder(_ text: String, symbol: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 30))
            Text(text)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

/// コミットの要約・説明と、コミットのボタン（GitHub Desktop の左下）
private struct CommitBox: View {
    @Bindable var model: ChangesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("要約（必須）", text: $model.summary)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.commit() }
            TextEditor(text: $model.commitDescription)
                .font(.system(size: 12))
                .frame(height: 54)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(alignment: .topLeading) {
                    if model.commitDescription.isEmpty {
                        Text("説明").foregroundStyle(.tertiary).padding(.horizontal, 9).padding(.vertical, 4).allowsHitTesting(false)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.12)))
            Button {
                model.commit()
            } label: {
                Text(commitTitle)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.canCommit)
            .keyboardShortcut(.return, modifiers: .command)
            .help(model.includedChanges.contains { $0.status == .conflicted } ? "競合しているファイルは、解決してからコミットしてください" : "選んだファイルをコミットする（⌘Return）")
        }
        .padding(10)
    }

    private var commitTitle: String {
        let count = model.includedChanges.count
        let target = model.branch.map { "「\($0)」に" } ?? ""
        return count == model.changes.count ? "\(target)コミット" : "\(count) 件を\(target)コミット"
    }
}

/// リモートとの同期のボタン（GitHub Desktop の右上の「Fetch origin / Pull / Push」）
private struct SyncButton: View {
    var model: ChangesModel

    var body: some View {
        if let action = GitOperations.SyncAction.available(for: model.branches).first {
            Button {
                GitOperations.sync(action, root: model.root)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: symbol(action))
                    Text(label(action))
                }
            }
            .buttonStyle(.borderless)
            .disabled(GitOperations.isBusy(model.root))
            .help(action.title(for: model.branches))
        }
    }

    private func symbol(_ action: GitOperations.SyncAction) -> String {
        switch action {
        case .fetch: "arrow.triangle.2.circlepath"
        case .pull: "arrow.down"
        case .push: "arrow.up"
        }
    }

    private func label(_ action: GitOperations.SyncAction) -> String {
        switch action {
        case .fetch: "フェッチ"
        case .pull: "プル \(model.branches.behind)"
        case .push: model.branches.upstream == nil ? "公開" : "プッシュ \(model.branches.ahead)"
        }
    }
}

private struct ChangeRow: View {
    var change: GitChange

    var body: some View {
        HStack(spacing: 8) {
            StatusBadge(status: change.status)
            VStack(alignment: .leading, spacing: 1) {
                Text(change.fileName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !change.folder.isEmpty {
                    Text(change.folder)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
        }
        .help(change.originalPath.map { "\($0) → \(change.path)" } ?? change.path)
    }
}

/// 変更の種類の印（GitHub Desktop と同じく、色つきの四角に1文字）
struct StatusBadge: View {
    var status: GitFileStatus

    var body: some View {
        Text(status.badge)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .frame(width: 15, height: 15)
            .background(RoundedRectangle(cornerRadius: 3).fill(status.color))
            .help(status.label)
    }
}

extension GitFileStatus {
    var color: Color {
        switch self {
        case .added, .untracked: .green
        case .deleted: .red
        case .renamed: .blue
        case .conflicted: .orange
        case .modified, .ignored: .yellow.mix(with: .orange, by: 0.4)
        }
    }

    var label: String {
        switch self {
        case .modified: "変更"
        case .added: "追加"
        case .untracked: "新規（未追跡）"
        case .deleted: "削除"
        case .renamed: "名前の変更"
        case .conflicted: "競合"
        case .ignored: "無視"
        }
    }
}

private struct DiffHeader: View {
    var change: GitChange
    var diff: FileDiff?

    var body: some View {
        HStack(spacing: 8) {
            StatusBadge(status: change.status)
            Text(change.originalPath.map { "\($0) → \(change.path)" } ?? change.path)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.head)
                .textSelection(.enabled)
            Spacer()
            if let diff, !diff.isBinary {
                Text("+\(diff.addedCount)").foregroundStyle(.green)
                Text("−\(diff.removedCount)").foregroundStyle(.red)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}

private struct DiffBody: View {
    var diff: FileDiff
    var status: GitFileStatus

    var body: some View {
        if diff.isBinary {
            message("バイナリファイルのため、差分は表示できません")
        } else if diff.hunks.isEmpty {
            message(status == .renamed ? "名前だけを変えています（中身の変更はありません）" : "表示できる差分はありません（空のファイル、または権限・属性だけの変更）")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(diff.hunks.enumerated()), id: \.offset) { _, hunk in
                        Text(hunk.header)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.08))
                        ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                            DiffLineRow(line: line)
                        }
                    }
                    if diff.isTruncated {
                        Text("長いため、先頭の \(FileDiff.maxLines) 行だけを表示しています")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(10)
                    }
                }
                .textSelection(.enabled)
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DiffLineRow: View {
    var line: DiffLine

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            number(line.oldNumber)
            number(line.newNumber)
            Text(sign)
                .frame(width: 16, alignment: .center)
                .foregroundStyle(signColor)
            Text(line.text.isEmpty ? " " : line.text)
                .foregroundStyle(line.kind == .note ? .secondary : .primary)
                .italic(line.kind == .note)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.vertical, 1)
        .background(background)
    }

    private func number(_ value: Int?) -> some View {
        Text(value.map(String.init) ?? "")
            .foregroundStyle(.tertiary)
            .frame(width: 44, alignment: .trailing)
            .padding(.trailing, 6)
    }

    private var sign: String {
        switch line.kind {
        case .added: "+"
        case .removed: "−"
        case .context, .note: ""
        }
    }

    private var signColor: Color {
        line.kind == .added ? .green : .red
    }

    private var background: Color {
        switch line.kind {
        case .added: .green.opacity(0.14)
        case .removed: .red.opacity(0.14)
        case .context, .note: .clear
        }
    }
}
