import AppKit

/// ファイル一覧。Finder と同じく、Return で名前の変更、スペースでクイックルックを行う。
final class FileOutlineView: NSOutlineView {
    var onReturn: (() -> Void)?
    var onSpace: (() -> Void)?
    var onFocus: (() -> Void)?
    var onTab: (() -> Void)?
    /// ほかの処理より先にキー入力を見る（絞り込み・Vim 風のキー操作）。true を返すと処理済み
    var onKeyDown: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true { return }
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])
        if modifiers.isEmpty {
            switch event.keyCode {
            case 36, 76: // Return / テンキーの Enter
                onReturn?()
                return
            case 49: // スペース
                onSpace?()
                return
            case 48: // Tab: 2画面のとき、もう一方の画面へ
                if let onTab {
                    onTab()
                    return
                }
            default:
                break
            }
        }
        super.keyDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { onFocus?() }
        return result
    }
}
