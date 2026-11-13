import AppKit
import SwiftUI

/// 表示中のフォルダの絞り込み（要件 S-04）。⌘F または「/」で開き、入力に合わせて一覧を絞る。
/// 「サブフォルダも」（⌥⌘F）をオンにすると、サブフォルダの中まで名前で探す
struct FilterBarView: View {
    var state: PaneState
    var onChange: (String) -> Void
    var onFinish: (_ clear: Bool) -> Void
    var onToggleSubfolders: (Bool) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease")
                .foregroundStyle(.secondary)
            FilterTextField(
                text: state.filterText,
                placeholder: placeholder,
                focusesOnAppear: !state.isFilterBarAlwaysShown,
                onChange: onChange,
                onFinish: onFinish
            )
            if !state.filterText.isEmpty {
                if searchesSubfolders, state.isSearchingSubfolders {
                    ProgressView().controlSize(.small)
                }
                Text(countText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .help(state.isSubfolderSearchTruncated ? "見つかった数が多いため、途中で探すのをやめました。文字を足して絞ってください" : "")
            }
            if canSearchSubfolders {
                Toggle("サブフォルダも", isOn: Binding(
                    get: { state.filterIncludesSubfolders },
                    set: { onToggleSubfolders($0) }
                ))
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .font(.system(size: 11))
                .help("サブフォルダの中まで名前で探す（⌥⌘F）")
            }
            // いつも出しているときは、何も打っていなければ「×」は要らない
            if !state.isFilterBarAlwaysShown || !state.filterText.isEmpty {
                Button {
                    onFinish(true)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("絞り込みをやめる（Esc）")
            }
        }
        // 帯ではなく、ガラスのカプセルの検索欄として見せる（区切りの線を重ねない）
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCapsule()
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .padding(.bottom, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    /// タグの一覧では、サブフォルダは探さない
    private var canSearchSubfolders: Bool { TagLocation.tagID(from: state.currentURL) == nil }

    private var searchesSubfolders: Bool { canSearchSubfolders && state.filterIncludesSubfolders }

    private var placeholder: String {
        let what = searchesSubfolders ? "サブフォルダも含めて名前で探す" : "名前で絞り込み"
        // いつも出しているときは、使い始めのキーを添える
        return state.isFilterBarAlwaysShown && !state.isFiltering ? "\(what)（⌘F）" : "\(what)（Esc でやめる）"
    }

    private var countText: String {
        guard state.isShowingSubfolderResults else { return "\(state.visibleCount) / \(state.itemCount) 項目" }
        return state.isSubfolderSearchTruncated ? "\(state.visibleCount) 件以上" : "\(state.visibleCount) 件"
    }
}

/// Esc（やめる）と Enter・↓（一覧へ戻る）を受け取るため AppKit の入力欄を使う。
private struct FilterTextField: NSViewRepresentable {
    var text: String
    var placeholder: String
    /// 出てきたときに入力欄にフォーカスを移す（⌘F で開いたとき）。いつも出しているときは移さない（起動時に一覧のキー入力を奪わない）
    var focusesOnAppear: Bool
    var onChange: (String) -> Void
    var onFinish: (_ clear: Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = FocusOnAppearTextField(string: text)
        field.focusesOnAppear = focusesOnAppear
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = placeholder
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.placeholderString != placeholder { field.placeholderString = placeholder }
        (field as? FocusOnAppearTextField)?.focusesOnAppear = focusesOnAppear
        if field.currentEditor() == nil, field.stringValue != text { field.stringValue = text }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FilterTextField

        init(parent: FilterTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.onChange(field.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onFinish(true)
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.moveDown(_:)), #selector(NSResponder.insertTab(_:)):
                // 絞り込んだまま一覧を操作する
                parent.onFinish(false)
            default:
                return false
            }
            return true
        }
    }
}

final class FocusOnAppearTextField: NSTextField {
    var focusesOnAppear = true

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // 隠れている欄は、フォーカスを取らない（取れずに一覧のフォーカスだけが外れてしまう）
        guard focusesOnAppear, !isHiddenOrHasHiddenAncestor, let window else { return }
        Task { @MainActor in
            window.makeFirstResponder(self)
            self.currentEditor()?.moveToEndOfDocument(nil)
        }
    }
}
