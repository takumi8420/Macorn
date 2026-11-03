import AppKit

/// 区切り線（1 ポイントの細い線）の、マウスで掴める範囲。
/// 見た目は細いまま、線の両側を少しずつ掴めるようにする（線ちょうどを狙わなくても幅を変えられるように）
enum DividerGrab {
    /// 線の両側に足す幅（ポイント）
    static let margin: CGFloat = 4

    static func rect(_ rect: NSRect, vertical: Bool) -> NSRect {
        vertical ? rect.insetBy(dx: -margin, dy: 0) : rect.insetBy(dx: 0, dy: -margin)
    }
}

/// ウィンドウ全体（サイドバーと画面）の分割。区切り線を掴みやすくする
final class BrowserSplitViewController: NSSplitViewController {
    override func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect, forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
        let rect = super.splitView(splitView, effectiveRect: proposedEffectiveRect, forDrawnRect: drawnRect, ofDividerAt: dividerIndex)
        return DividerGrab.rect(rect, vertical: splitView.isVertical)
    }
}
