import AppKit
import SwiftUI

/// 表示中のフォルダの絞り込み（要件 S-04）。⌘F または「/」で開き、入力に合わせて一覧を絞る。
struct FilterBarView: View {
    var state: PaneState
    var onChange: (String) -> Void
    var onFinish: (_ clear: Bool) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease")
                .foregroundStyle(.secondary)
            FilterTextField(text: state.filterText, onChange: onChange, onFinish: onFinish)
            if !state.filterText.isEmpty {
                Text("\(state.visibleCount) / \(state.itemCount) 項目")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Button {
                onFinish(true)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("絞り込みをやめる（Esc）")
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// Esc（やめる）と Enter・↓（一覧へ戻る）を受け取るため AppKit の入力欄を使う。
private struct FilterTextField: NSViewRepresentable {
    var text: String
    var onChange: (String) -> Void
    var onFinish: (_ clear: Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = FocusOnAppearTextField(string: text)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = "名前で絞り込み（Esc でやめる）"
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
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
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        Task { @MainActor in
            window.makeFirstResponder(self)
            self.currentEditor()?.moveToEndOfDocument(nil)
        }
    }
}
