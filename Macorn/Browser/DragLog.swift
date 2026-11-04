import AppKit
import os

/// ドラッグ＆ドロップの流れを記録する（うまくいかないときに、どの段階で止まったかを調べるため）。
/// 見るとき: log show --last 10m --predicate 'subsystem == "dev.macorn.Macorn" AND category == "drag"'
nonisolated enum DragLog {
    private static let logger = Logger(subsystem: "dev.macorn.Macorn", category: "drag")

    static func note(_ message: String) {
        let buttons = NSEvent.pressedMouseButtons
        logger.notice("\(message, privacy: .public) [buttons=\(buttons)]")
    }
}
