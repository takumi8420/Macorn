import AppKit

/// タブの右端にいつも出す「×」（閉じるボタン）。
/// macOS 標準のタブの「×」はカーソルを乗せたときしか出ないため、タブの付属のビュー（`NSWindowTab.accessoryView`）として置く。
/// 押すと、このボタンが付いたタブ（ウィンドウ）を閉じる。選んでいないタブでも閉じられる。
final class TabCloseButton: NSView {
    private weak var targetWindow: NSWindow?
    private let imageView = NSImageView()
    private var hovering = false { didSet { needsDisplay = true; updateTint() } }
    private var pressing = false { didSet { needsDisplay = true } }

    static let size: CGFloat = 16

    init(window: NSWindow) {
        targetWindow = window
        super.init(frame: NSRect(x: 0, y: 0, width: Self.size, height: Self.size))
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.size),
            heightAnchor.constraint(equalToConstant: Self.size),
        ])
        let configuration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        imageView.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "タブを閉じる")?
            .withSymbolConfiguration(configuration)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        toolTip = "タブを閉じる（⌘W）"
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("タブを閉じる")
        updateTint()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateTint() {
        imageView.contentTintColor = hovering ? .labelColor : .secondaryLabelColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false; pressing = false }

    // タブを選ぶ・ドラッグする動きより先に、このボタンで受け取る
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { pressing = true }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        pressing = false
        if inside { closeTab() }
    }

    override func accessibilityPerformPress() -> Bool {
        closeTab()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard hovering || pressing else { return }
        NSColor.labelColor.withAlphaComponent(pressing ? 0.2 : 0.1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
    }

    /// ⌘W と同じ閉じ方（windowShouldClose を通す）。選んでいないタブでも、そのタブだけを閉じる
    func closeTab() {
        targetWindow?.performClose(nil)
    }
}
