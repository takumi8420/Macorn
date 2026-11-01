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

    /// ほかの場所からのドラッグが、いまこの一覧の上にある
    private(set) var isDragTargeted = false
    /// 一覧の上でのドラッグが終わった（外へ出た・落とした・取りやめた）
    var onDragTargetEnded: (() -> Void)?

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        isDragTargeted = true
        return super.draggingEntered(sender)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        super.draggingExited(sender)
        endDragTarget()
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        super.draggingEnded(sender)
        endDragTarget()
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        super.concludeDragOperation(sender)
        endDragTarget()
    }

    private func endDragTarget() {
        guard isDragTargeted else { return }
        isDragTargeted = false
        onDragTargetEnded?()
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { onFocus?() }
        return result
    }
}
