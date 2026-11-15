import SwiftUI

/// ブランチを選ぶポップオーバー（GitHub Desktop の上の「Current Branch」と同じ使い方）。
/// 上の欄で名前を打って絞り込み、↑↓ と Return で切り替える。打った名前のブランチがなければ、その名前で作れる。
/// 上部にリモートとの同期（プル・プッシュ・フェッチ）のボタンを並べる
struct BranchPickerView: View {
    let root: URL
    /// 閉じる（選んだあとも閉じる）
    let close: () -> Void

    @State private var branches: GitBranches?
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            if let branches {
                let actions = GitOperations.SyncAction.available(for: branches)
                if !actions.isEmpty {
                    syncBar(actions, branches: branches)
                }
                Divider()
                list(branches)
            } else {
                Divider()
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .frame(width: 340)
        .task {
            let root = root
            branches = await Task.detached(priority: .userInitiated) { GitActions.branches(root: root) }.value
        }
        .onAppear {
            // ポップオーバーが出きってから入力欄に移す（すぐだと受け付けられないことがある）
            Task { @MainActor in isSearchFocused = true }
        }
    }

    // MARK: 検索の欄

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("ブランチを探す・新しいブランチの名前", text: $query)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onChange(of: query) { highlighted = 0 }
                .onSubmit { activate(highlighted) }
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-1) }
                .onKeyPress(.escape) {
                    close()
                    return .handled
                }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: 同期のボタン

    private func syncBar(_ actions: [GitOperations.SyncAction], branches: GitBranches) -> some View {
        HStack(spacing: 6) {
            ForEach(actions, id: \.self) { action in
                Button {
                    close()
                    GitOperations.sync(action, root: root)
                } label: {
                    Label(Self.shortTitle(action, branches: branches), systemImage: Self.symbol(action))
                        .frame(maxWidth: action == .fetch ? nil : .infinity)
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .tint(action == actions.first && action != .fetch ? .accentColor : nil)
                .help(action.title(for: branches))
            }
            if actions == [.fetch] { Spacer() }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    static func shortTitle(_ action: GitOperations.SyncAction, branches: GitBranches) -> String {
        switch action {
        case .fetch: "フェッチ"
        case .pull: "プル（\(branches.behind)）"
        case .push: branches.upstream == nil ? "公開する" : "プッシュ（\(branches.ahead)）"
        }
    }

    static func symbol(_ action: GitOperations.SyncAction) -> String {
        switch action {
        case .fetch: "arrow.triangle.2.circlepath"
        case .pull: "arrow.down"
        case .push: "arrow.up"
        }
    }

    // MARK: 一覧

    private func list(_ branches: GitBranches) -> some View {
        let entries = Self.entries(for: branches, query: query)
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if let title = Self.sectionTitle(entries, at: index) {
                            Text(title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.top, index == 0 ? 2 : 8)
                                .padding(.bottom, 2)
                        }
                        BranchRow(entry: entry, isHighlighted: index == highlighted)
                            .id(entry.id)
                            .onTapGesture { activate(index) }
                            .onHover { if $0 { highlighted = index } }
                    }
                    if entries.isEmpty {
                        Text("ブランチがありません")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                }
                .padding(6)
            }
            // ポップオーバーは中身の高さに合わせるので、項目の数から高さを決める（多いときは 360 で打ち切ってスクロール）
            .frame(height: Self.listHeight(entries))
            .onChange(of: highlighted) {
                guard entries.indices.contains(highlighted) else { return }
                proxy.scrollTo(entries[highlighted].id)
            }
        }
    }

    static func listHeight(_ entries: [Entry]) -> CGFloat {
        var height: CGFloat = 12
        for (index, entry) in entries.enumerated() {
            height += entry.worktree != nil || entry.kind == .remote || entry.kind == .create ? 44 : 30
            if sectionTitle(entries, at: index) != nil { height += 26 }
        }
        return min(max(height, 80), 360)
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        guard let branches else { return .handled }
        let count = Self.entries(for: branches, query: query).count
        guard count > 0 else { return .handled }
        highlighted = min(max(highlighted + delta, 0), count - 1)
        return .handled
    }

    private func activate(_ index: Int) {
        guard let branches else { return }
        let entries = Self.entries(for: branches, query: query)
        guard entries.indices.contains(index) else {
            NSSound.beep()
            return
        }
        let entry = entries[index]
        switch entry.kind {
        case .current:
            close()
        case .local, .remote:
            close()
            GitOperations.switchBranch(entry.name, root: root)
        case .create:
            close()
            GitOperations.createBranch(named: entry.name, root: root)
        case .createPrompt:
            close()
            GitOperations.createBranch(root: root)
        }
    }

    // MARK: 並べる項目

    struct Entry: Equatable {
        enum Kind: Equatable {
            case current, local, remote
            /// 打った名前で新しいブランチを作る
            case create
            /// 名前を尋ねてから新しいブランチを作る（何も打っていないとき）
            case createPrompt
        }
        var name: String
        var kind: Kind
        var worktree: GitWorktree?

        var id: String { "\(kind)/\(name)" }
    }

    /// 今のブランチ → ローカル → リモート → 新しいブランチ の順。query があれば、名前にそれを含むものだけ（大文字・小文字は区別しない）
    static func entries(for branches: GitBranches, query: String) -> [Entry] {
        let text = query.trimmingCharacters(in: .whitespaces)
        func matches(_ name: String) -> Bool { text.isEmpty || name.localizedCaseInsensitiveContains(text) }
        var result: [Entry] = []
        if let current = branches.current, matches(current) {
            result.append(Entry(name: current, kind: .current))
        }
        for name in branches.local where name != branches.current && matches(name) {
            result.append(Entry(name: name, kind: .local, worktree: branches.worktrees[name]))
        }
        for name in branches.remote where matches(name) {
            result.append(Entry(name: name, kind: .remote))
        }
        if text.isEmpty {
            result.append(Entry(name: "", kind: .createPrompt))
        } else if !branches.local.contains(text) {
            result.append(Entry(name: text, kind: .create))
        }
        // 打った名前に当たるブランチがあれば、まずそれ（今のブランチは除く）を選んでおけるよう、新しいブランチは最後に置く
        return result
    }

    static func sectionTitle(_ entries: [Entry], at index: Int) -> String? {
        func section(_ kind: Entry.Kind) -> String? {
            switch kind {
            case .current: "今のブランチ"
            case .local: "ローカルのブランチ"
            case .remote: "リモートのブランチ"
            case .create, .createPrompt: nil
            }
        }
        let title = section(entries[index].kind)
        if index > 0, section(entries[index - 1].kind) == title { return nil }
        return title
    }
}

/// 一覧の1行
private struct BranchRow: View {
    let entry: BranchPickerView.Entry
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 16)
                .foregroundStyle(entry.kind == .create || entry.kind == .createPrompt ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .fontWeight(entry.kind == .current ? .semibold : .regular)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let note {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if entry.kind == .current {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(isHighlighted ? Color.accentColor.opacity(0.18) : .clear))
        .contentShape(Rectangle())
    }

    private var symbol: String {
        switch entry.kind {
        case .current, .local: entry.worktree == nil ? "arrow.triangle.branch" : "folder"
        case .remote: "cloud"
        case .create, .createPrompt: "plus"
        }
    }

    private var title: String {
        switch entry.kind {
        case .create: "新しいブランチ「\(entry.name)」を作る"
        case .createPrompt: "新しいブランチ…"
        default: entry.name
        }
    }

    private var note: String? {
        if let worktree = entry.worktree {
            if worktree.isMissing { return "消えたワークツリーの記録に残っています" }
            if worktree.isRemovable { return "別のワークツリーで使用中・変更なし（外して切り替えられます）" }
            if let count = worktree.changeCount { return "別のワークツリーで使用中・コミットしていない変更 \(count) 件" }
            return "別のワークツリーで使用中"
        }
        switch entry.kind {
        case .remote: return "選ぶと、同じ名前のブランチを作って追いかけます"
        case .create: return "今のコミットから作って切り替えます"
        default: return nil
        }
    }
}

/// パスバー・変更のウィンドウに置く、今のブランチのボタン。押すとブランチを選ぶポップオーバーを出す
struct BranchPickerButton: View {
    let root: URL
    let branch: String?
    var ahead = 0
    var behind = 0
    @Binding var isPresented: Bool
    @State private var isHovering = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .semibold))
                Text(branch ?? "ブランチの外")
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 180)
                    .fixedSize(horizontal: true, vertical: false)
                if ahead > 0 { Text("↑\(ahead)").foregroundStyle(.secondary) }
                if behind > 0 { Text("↓\(behind)").foregroundStyle(.secondary) }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(isHovering || isPresented ? Color.primary.opacity(0.08) : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("ブランチを切り替える・作る、プル・プッシュ（⇧⌘B）")
        .accessibilityLabel("ブランチ \(branch ?? "なし")。押すとブランチを切り替える")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            BranchPickerView(root: root) { isPresented = false }
        }
    }
}
