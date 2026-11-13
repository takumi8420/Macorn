import AppKit
import SwiftUI

/// リキッドグラス（macOS 26）の面。タブの列・パスバーのボタン・絞り込みの欄など、中身の上に浮かぶ操作の部品に使う。
/// macOS 15 ではガラスがないので、うすい塗りの面で代わりにする
enum Glass {
    /// 角の丸いガラスの面（AppKit 用）。部品の奥に置く
    static func makeView(cornerRadius: CGFloat) -> NSView {
        if #available(macOS 26.0, *) {
            let view = NSGlassEffectView()
            view.cornerRadius = cornerRadius
            return view
        }
        return FallbackGlassView(cornerRadius: cornerRadius)
    }
}

/// macOS 15 用の、ガラスの代わりのうすい面
private final class FallbackGlassView: NSView {
    private let cornerRadius: CGFloat

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
    }
}

extension View {
    /// ガラスのカプセルに入れる（macOS 15 ではうすい塗りのカプセル）
    @ViewBuilder func glassCapsule() -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: Capsule())
        } else {
            background(Capsule().fill(Color.primary.opacity(0.05)))
        }
    }
}
