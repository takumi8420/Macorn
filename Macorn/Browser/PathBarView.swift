import AppKit
import SwiftUI

struct PathBarActions {
    var navigate: (URL) -> Void
    /// 入力されたパスへ移動する。移動できなければ false。
    var commitPath: (String) -> Bool
    var complete: (String) -> String
    var endEditing: () -> Void
}

/// パンくずリスト（要件 N-06）と、パスの直接入力欄（要件 N-07）。
struct PathBarView: View {
    var state: PaneState
    var actions: PathBarActions

    var body: some View {
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
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .opacity(isDimmed ? 0.55 : 1)
        .background(isHighlighted ? Color.accentColor.opacity(0.10) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { state.isEditingPath = true }
        .overlay(alignment: .bottom) {
            // 2画面のときは、操作対象の画面の下に色付きの線を引いて区別する（要件 P-03）
            if isHighlighted {
                Rectangle().fill(Color.accentColor).frame(height: 2)
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

    private func finishEditing() {
        state.isEditingPath = false
        actions.endEditing()
    }

    private var breadcrumbs: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                breadcrumbRow
                    // 短いパスは左寄せ、長いパスは末尾（今いるフォルダ）が見えるようにする
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .leading)
            }
            .defaultScrollAnchor(.trailing)
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
                        navigate: actions.navigate
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

private struct BreadcrumbButton: View {
    let url: URL
    let isCurrent: Bool
    let navigate: (URL) -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            navigate(url)
        } label: {
            HStack(spacing: 4) {
                Image(nsImage: Self.icon(for: url))
                    .resizable()
                    .frame(width: 14, height: 14)
                Text(Self.name(for: url))
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .lineLimit(1)
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
        .help(url.path)
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

        func controlTextDidEndEditing(_ notification: Notification) {
            // 別の場所をクリックしてフォーカスが外れたときは取り消し扱い
            guard !finished else { return }
            finished = true
            parent.onCancel()
        }
    }
}

/// 表示されたらすぐに入力できる状態にするテキスト欄。
private final class AutoFocusTextField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        Task { @MainActor in
            window.makeFirstResponder(self)
            self.currentEditor()?.moveToEndOfDocument(nil)
        }
    }
}
