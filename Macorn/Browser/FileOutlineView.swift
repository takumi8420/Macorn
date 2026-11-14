import AppKit

/// ファイル一覧。Finder と同じく、Return で名前の変更、スペースでクイックルックを行う。⌘Return で開く。
final class FileOutlineView: NSOutlineView {
    var onReturn: (() -> Void)?
    /// ⌘Return（⌘↓・⌘O と同じく、フォルダなら中へ、ファイルなら開く）
    var onOpen: (() -> Void)?
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
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if modifiers == .command, isReturn, let onOpen {
            onOpen()
            return
        }
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

    /// ほかの場所からのドラッグが、いまこの一覧の上にある。
    /// ドロップを受け付けなかったときなど、終わりの知らせが届かないことがあるので、
    /// マウスのボタンを離していればドラッグは終わったとみなす（「ドラッグ中」のまま残らないように）
    var isDragTargeted: Bool {
        dragEntered && NSEvent.pressedMouseButtons & 1 != 0
    }
    private var dragEntered = false
    /// 一覧の上でのドラッグが終わった（外へ出た・落とした・取りやめた）
    var onDragTargetEnded: (() -> Void)?

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dragEntered = true
        let result = super.draggingEntered(sender)
        DragLog.note("entered seq=\(sender.draggingSequenceNumber) result=\(result.rawValue)")
        return result
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        super.draggingExited(sender)
        DragLog.note("exited")
        endDragTarget()
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        // NSOutlineView（NSTableView）は draggingEnded を持っていないので、super は呼ばない。
        // 呼ぶと「知らない命令」の例外になり、macOS 側のドラッグの後始末が途中で止まって、
        // 次のドラッグが「前のドラッグが終わっていない」として始められなくなる
        if NSOutlineView.instancesRespond(to: #selector(NSDraggingDestination.draggingEnded(_:))) {
            super.draggingEnded(sender)
        }
        DragLog.note("ended(target)")
        endDragTarget()
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let result = super.performDragOperation(sender)
        DragLog.note("perform result=\(result)")
        return result
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        super.concludeDragOperation(sender)
        DragLog.note("conclude")
        endDragTarget()
    }


    #if DEBUG
    /// 自動操作用: ドラッグが入ってきたまま、終わりの知らせが届かなかった状態を作る
    func debugMarkDragEntered() { dragEntered = true }
    #endif

    private func endDragTarget() {
        guard dragEntered else { return }
        dragEntered = false
        onDragTargetEnded?()
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { onFocus?() }
        return result
    }
}
