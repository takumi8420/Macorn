import AppKit

/// タブをドラッグして画面の中に置く場所。置いた先の画面の、どの辺に新しい画面を作るか
enum PaneDropZone: Equatable {
    case left, right, top, bottom
    /// 真ん中：その画面のタブにする
    case center

    /// 画面の中の位置（左上を 0、右下を 1 とした割合）から、置き場所を決める。
    /// 真ん中の四角（縦横とも 30%〜70%）ならその画面のタブに、それ以外はいちばん近い辺
    static func zone(x: CGFloat, yFromTop y: CGFloat) -> PaneDropZone {
        let distances: [(PaneDropZone, CGFloat)] = [(.left, x), (.right, 1 - x), (.top, y), (.bottom, 1 - y)]
        let nearest = distances.min { $0.1 < $1.1 }!
        return nearest.1 > 0.3 ? .center : nearest.0
    }

    /// 置いたあとに新しい画面が来る場所（画面の半分、真ん中なら画面全体）。rect は左下が原点の座標
    func highlight(in rect: NSRect) -> NSRect {
        switch self {
        case .left: NSRect(x: rect.minX, y: rect.minY, width: rect.width / 2, height: rect.height)
        case .right: NSRect(x: rect.midX, y: rect.minY, width: rect.width / 2, height: rect.height)
        case .top: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2)
        case .bottom: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height / 2)
        case .center: rect
        }
    }
}

/// タブをドラッグしている間だけ、画面の並びの上に重ねるビュー。置き場所を色で示し、置いたら並びを組み替える。
/// 一覧やプレビューより上に置くので、ファイルのドラッグとは混ざらない（受け取るのは画面のドラッグだけ）。
final class PaneDropOverlay: NSView {
    static let pasteboardType = NSPasteboard.PasteboardType("dev.macorn.pane")

    /// 指したところの、色を付ける範囲と、置いたときにすること（置けないところは nil）
    var resolve: (NSPoint) -> (rect: NSRect, perform: () -> Void)? = { _ in nil }

    /// 色を付けている範囲（開発用の自動操作では、ドラッグせずに直接決める）
    var highlight: NSRect? {
        didSet { if highlight != oldValue { needsDisplay = true } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([Self.pasteboardType])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func update(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.types?.contains(Self.pasteboardType) == true,
              let found = resolve(convert(sender.draggingLocation, from: nil)) else {
            highlight = nil
            return []
        }
        highlight = found.rect
        return .move
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { highlight = nil }
    override func draggingEnded(_ sender: NSDraggingInfo) { highlight = nil }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { highlight = nil }
        guard let found = resolve(convert(sender.draggingLocation, from: nil)) else { return false }
        found.perform()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let highlight else { return }
        // タブの列の間に置くときは、細い線だけを引く
        if highlight.width < 8 {
            Theme.shared.accentColor.setFill()
            highlight.fill()
            return
        }
        let rect = highlight.insetBy(dx: 3, dy: 3)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        Theme.shared.accentColor.withAlphaComponent(0.18).setFill()
        path.fill()
        Theme.shared.accentColor.withAlphaComponent(0.8).setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}
