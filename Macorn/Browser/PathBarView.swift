import AppKit
import SwiftUI

struct PathBarActions {
    var navigate: (URL) -> Void
    /// 入力されたパスへ移動する。移動できなければ false。
    var commitPath: (String) -> Bool
    var complete: (String) -> String
    var endEditing: () -> Void
    /// パスの直接入力を始める（1回のクリック・⌘L）
    var beginEditing: () -> Void
    /// 表示中のフォルダのパスをコピーする（パスのすぐ右のボタン）。コピーできたら true
    var copyCurrentPath: () -> Bool
    /// 画面を分けているとき、この画面を閉じる（パスバーの右端の「×」）
    var closePane: () -> Void
    /// パスバーの右の、この画面で表示中のフォルダへの追加（新規フォルダ・新規ファイル・お気に入り）
    var newFolder: () -> Void = {}
    var newFile: () -> Void = {}
    var toggleFavorite: () -> Void = {}
}

/// パンくずリスト（要件 N-06）と、パスの直接入力欄（要件 N-07）。
struct PathBarView: View {
    var state: PaneState
    var actions: PathBarActions
    /// パスバーの幅（狭いときは、リポジトリのボタンを短くする）
    @State private var width: CGFloat = 1000

    var body: some View {
        HStack(spacing: 6) {
            ZStack(alignment: .leading) {
                if state.isEditingPath {
                    PathTextField(
                        initialText: initialEditingText,
                        onCommit: { text in
                            guard actions.commitPath(text) else { return false }
                            finishEditing()
                            return true
                        },
                        onCancel: finishEditing,
                        onComplete: actions.complete
                    )
                } else {
                    if let id = TagLocation.tagID(from: state.currentURL) {
                        tagChip(id)
                    } else {
                        breadcrumbs
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            // 右端: この画面への追加（新規フォルダ・新規ファイル・お気に入り）、Git のリポジトリのページを開くボタン、
            // 分けているときはこの画面を閉じる「×」。ウィンドウ全体に関わるもの（分割・ターミナル）は上のツールバーに置く
            if !state.isEditingPath {
                if state.currentURL.isFileURL {
                    let isFavorite = SidebarStore.shared.containsFavorite(state.currentURL)
                    HStack(spacing: 2) {
                        PathBarIconButton(symbol: "folder.badge.plus", help: "このフォルダに、新しいフォルダを作る（⇧⌘N）", action: actions.newFolder)
                        PathBarIconButton(symbol: "doc.badge.plus", help: "このフォルダに、新しいファイルを作る（⌥⌘N）", action: actions.newFile)
                        PathBarIconButton(
                            symbol: isFavorite ? "star.fill" : "star",
                            help: isFavorite ? "このフォルダをお気に入りから外す" : "このフォルダをお気に入りに追加",
                            action: actions.toggleFavorite
                        )
                    }
                }
                if let url = state.gitRemoteWebURL {
                    RepositoryWebButton(
                        url: url,
                        name: state.gitRepositoryName ?? url.lastPathComponent,
                        service: state.gitRemoteServiceName ?? "Web",
                        isCompact: width < 760
                    )
                }
                if state.isInSplit {
                    ClosePaneButton(close: actions.closePane)
                }
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .opacity(isDimmed ? 0.55 : 1)
        .background(isHighlighted ? Theme.shared.accent.opacity(0.10) : .clear)
        .contentShape(Rectangle())
        // 空いている所を1回クリックすると、パスを直接入力できる（⌘L と同じ）
        .onTapGesture { startEditing() }
        .overlay(alignment: .bottom) {
            // 2画面のときは、操作対象の画面の下に色付きの線を引いて区別する（要件 P-03）
            if isHighlighted {
                Rectangle().fill(Theme.shared.accent).frame(height: 2)
            } else {
                Divider()
            }
        }
    }

    private var isHighlighted: Bool { state.isInSplit && state.isActive }
    private var isDimmed: Bool { state.isInSplit && !state.isActive }

    /// タグの一覧を開いているときは、パンくずの代わりにタグの名前を出す
    private func tagChip(_ id: UUID) -> some View {
        let tag = TagStore.shared.tag(id: id)
        return HStack(spacing: 6) {
            Image(systemName: "tag.fill")
                .foregroundStyle(Color(nsColor: NSColor(hex: tag?.color ?? "#8E8E93")))
            Text(tag?.name.replacingOccurrences(of: "/", with: " › ") ?? "（削除されたタグ）")
                .fontWeight(.semibold)
            Text("のタグが付いた項目")
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
    }

    private var initialEditingText: String {
        // タグの一覧にはパスがないので、ホームから入力を始める
        guard state.currentURL.isFileURL else { return "~/" }
        let path = PathCompletion.abbreviate(state.currentURL.path)
        return path.hasSuffix("/") ? path : path + "/"
    }

    private func startEditing() {
        guard !state.isEditingPath else { return }
        actions.beginEditing()
    }

    private func finishEditing() {
        state.isEditingPath = false
        actions.endEditing()
    }

    private var breadcrumbs: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                // コピーのボタンは、パスの末尾（今いるフォルダ）のすぐ右に置く
                HStack(spacing: 6) {
                    breadcrumbRow
                    CopyPathButton(path: state.currentURL.path, copy: actions.copyCurrentPath)
                }
                // 短いパスは左寄せ、長いパスは末尾（今いるフォルダ）とコピーのボタンが見えるようにする
                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .leading)
            }
            .defaultScrollAnchor(.trailing)
            // 幅が変わったら作り直して、末尾（今いるフォルダとコピーのボタン）が見える位置に戻す
            .id(Int(geometry.size.width))
        }
    }

    private var breadcrumbRow: some View {
            HStack(spacing: 2) {
                let components = Self.components(of: state.currentURL)
                ForEach(Array(components.enumerated()), id: \.element.path) { index, url in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    BreadcrumbButton(
                        url: url,
                        isCurrent: index == components.count - 1,
                        branch: state.gitRepositoryRoot?.standardizedFileURL.path == url.path ? state.gitBranch : nil,
                        navigate: actions.navigate,
                        beginEditing: startEditing
                    )
                }
            }
            .padding(.vertical, 2)
    }

    /// ルートから表示中フォルダまでの各階層。
    static func components(of url: URL) -> [URL] {
        var result: [URL] = []
        var current = url.standardizedFileURL
        while true {
            result.insert(current, at: 0)
            guard current.path != "/" else { break }
            current = current.deletingLastPathComponent()
        }
        return result
    }
}

/// パスのすぐ右のボタン：表示中のフォルダのパスをコピーし、しばらくチェックの印を出す
private struct CopyPathButton: View {
    /// コピーされるパス（説明に出す）
    let path: String
    let copy: () -> Bool
    @State private var copied = false
    @State private var isHovering = false

    var body: some View {
        Button {
            guard copy() else { NSSound.beep(); return }
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(copied ? Color.accentColor : .secondary)
                .frame(width: 24, height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(isHovering ? Color.primary.opacity(0.08) : .clear))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(copied ? "コピーしました" : "表示中のフォルダのパスをコピー\n\(path)")
    }
}

/// Git リポジトリの中を表示しているときに、パスバーの右端に出すボタン。
/// 「持ち主/リポジトリ」と「GitHub」を並べ、押すとリポジトリのページをブラウザで開く
private struct RepositoryWebButton: View {
    let url: URL
    let name: String
    let service: String
    /// 狭い画面では「持ち主/リポジトリ」を省き、「GitHub」だけにする
    let isCompact: Bool
    @State private var isHovering = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 5) {
                if !isCompact {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(name)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                serviceLabel
            }
            .font(.system(size: 11))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(isHovering ? 0.10 : 0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .fixedSize()
        .help("\(url.absoluteString) をブラウザで開く")
        .accessibilityLabel("\(name) を \(service) で開く")
    }

    private var serviceLabel: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.up.right.square")
            Text(service)
                .fontWeight(.medium)
        }
        .lineLimit(1)
        .foregroundStyle(isHovering ? Color.accentColor : .primary)
    }
}

/// 画面を分けているときに、パスバーの右端に出す「×」。押すとこの画面を閉じる
/// パスバーの右に並べる小さなアイコンのボタン（カーソルを乗せるとうすく塗る）
private struct PathBarIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(isHovering ? Color.primary : .secondary)
                .frame(width: 26, height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(isHovering ? Color.primary.opacity(0.08) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct ClosePaneButton: View {
    let close: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isHovering ? Color.primary : .secondary)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(isHovering ? Color.primary.opacity(0.08) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("この画面を閉じる（⌥⌘W）")
        .accessibilityLabel("この画面を閉じる")
    }
}

private struct BreadcrumbButton: View {
    let url: URL
    let isCurrent: Bool
    /// この階層が Git リポジトリのルートなら、そのブランチ名
    var branch: String? = nil
    let navigate: (URL) -> Void
    /// 今いるフォルダ（いちばん右）をクリックしたら、移動の代わりにパスの入力にする
    let beginEditing: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            if isCurrent { beginEditing() } else { navigate(url) }
        } label: {
            HStack(spacing: 4) {
                Image(nsImage: Self.icon(for: url))
                    .resizable()
                    .frame(width: 14, height: 14)
                Text(Self.name(for: url))
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .lineLimit(1)
                if let branch {
                    // リポジトリのルートに、ブランチ名の小さな札を付ける
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.triangle.branch")
                        Text(branch).lineLimit(1)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                    .help("Git リポジトリ「\(Self.name(for: url))」・ブランチ \(branch)")
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovering ? Color.primary.opacity(0.08) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            SiblingFolderMenu(url: url, navigate: navigate)
        }
        .help(isCurrent ? "クリックでパスを入力（⌘L）" : "\(url.path) へ移動（右クリックで同じ階層のフォルダ）")
    }

    static func name(for url: URL) -> String {
        url.path == "/" ? FileManager.default.displayName(atPath: "/") : url.lastPathComponent
    }

    static func icon(for url: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// パンくずの右クリックで出す、同じ階層のフォルダ一覧。
private struct SiblingFolderMenu: View {
    let url: URL
    let navigate: (URL) -> Void

    var body: some View {
        let siblings = PathCompletion.siblingFolders(of: url, includeHidden: Preferences.showHiddenFiles)
        if siblings.isEmpty {
            Text("同じ階層のフォルダはありません")
        } else {
            ForEach(siblings, id: \.path) { sibling in
                Button {
                    navigate(sibling)
                } label: {
                    if sibling.path == url.path {
                        Label(sibling.lastPathComponent, systemImage: "checkmark")
                    } else {
                        Text(sibling.lastPathComponent)
                    }
                }
            }
        }
    }
}

/// パス入力欄。Tab で補完、Enter で移動、Esc で取り消し。
/// SwiftUI の TextField では Tab キーを受け取れないため、AppKit の NSTextField を使う。
struct PathTextField: NSViewRepresentable {
    let initialText: String
    let onCommit: (String) -> Bool
    let onCancel: () -> Void
    let onComplete: (String) -> String

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = AutoFocusTextField(string: initialText)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        field.placeholderString = "パスを入力（Tab で補完、Esc で取り消し）"
        field.delegate = context.coordinator
        field.onOutsideClick = { [weak coordinator = context.coordinator] in coordinator?.cancelByOutsideClick() }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PathTextField
        private var finished = false

        init(parent: PathTextField) {
            self.parent = parent
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertTab(_:)):
                let completed = parent.onComplete(textView.string)
                if completed == textView.string {
                    NSSound.beep()
                } else {
                    textView.string = completed
                    textView.setSelectedRange(NSRange(location: (completed as NSString).length, length: 0))
                }
                return true
            case #selector(NSResponder.insertNewline(_:)):
                finished = true
                if !parent.onCommit(textView.string) {
                    finished = false
                    NSSound.beep()
                }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                finished = true
                parent.onCancel()
                return true
            default:
                return false
            }
        }

        /// 入力欄の外をクリックしたら、入力をやめて元の表示に戻す
        func cancelByOutsideClick() {
            guard !finished else { return }
            finished = true
            parent.onCancel()
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            // 別の場所をクリックしてフォーカスが外れたときは取り消し扱い
            guard !finished else { return }
            finished = true
            parent.onCancel()
        }
    }
}

/// 表示されたらすぐに入力できる状態にするテキスト欄。
/// 入力欄の外をクリックしたら `onOutsideClick` を呼ぶ。一覧などフォーカスを取らない場所のクリックでは
/// フォーカスが外れず（controlTextDidEndEditing が来ず）、入力欄のまま残ってしまうため、クリックを見張る。
private final class AutoFocusTextField: NSTextField {
    var onOutsideClick: (() -> Void)?
    private var clickMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeClickMonitor()
        guard let window else { return }
        Task { @MainActor in
            window.makeFirstResponder(self)
            self.currentEditor()?.moveToEndOfDocument(nil)
        }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleClick(event) }
            // クリックそのものは止めない（一覧の項目を選ぶなど、押した先の操作もそのまま行う）
            return event
        }
    }

    private func handleClick(_ event: NSEvent) {
        guard let window else { return }
        if event.window === window {
            let point = convert(event.locationInWindow, from: nil)
            guard !bounds.contains(point) else { return }
        }
        onOutsideClick?()
    }

    private func removeClickMonitor() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    override func removeFromSuperview() {
        removeClickMonitor()
        super.removeFromSuperview()
    }
}
