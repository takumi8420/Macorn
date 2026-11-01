import AppKit
import Observation
import SwiftUI

/// アプリのテーマ（外観とアクセントカラー）。設定の「一般 › テーマ」で変える。
/// アクセントカラーは、選択中の行・操作対象の画面の線・パレットの選択・リンクなどに使う。
@Observable
final class Theme {
    static let shared = Theme()

    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark

        var id: String { rawValue }

        var title: String {
            switch self {
            case .system: "macOS に合わせる"
            case .light: "ライト"
            case .dark: "ダーク"
            }
        }

        var nsAppearance: NSAppearance? {
            switch self {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }
    }

    struct Preset: Identifiable, Hashable {
        var name: String
        /// nil は macOS のアクセントカラーに合わせる
        var hex: String?
        var id: String { hex ?? "system" }
    }

    static let presets: [Preset] = [
        Preset(name: "macOS に合わせる", hex: nil),
        Preset(name: "どんぐり", hex: "#C9773A"),
        Preset(name: "ブルー", hex: "#0A84FF"),
        Preset(name: "パープル", hex: "#BF5AF2"),
        Preset(name: "ピンク", hex: "#FF6FAE"),
        Preset(name: "レッド", hex: "#FF5F57"),
        Preset(name: "オレンジ", hex: "#FF9F0A"),
        Preset(name: "グリーン", hex: "#28A745"),
        Preset(name: "グラファイト", hex: "#8E8E93"),
    ]

    private enum Key {
        static let appearance = "themeAppearance"
        static let accent = "themeAccentColor"
    }

    var appearance: Appearance {
        didSet {
            AppDefaults.store.set(appearance.rawValue, forKey: Key.appearance)
            apply()
        }
    }

    /// 選んだアクセントカラー（#RRGGBB）。nil なら macOS に合わせる
    var accentHex: String? {
        didSet {
            AppDefaults.store.set(accentHex, forKey: Key.accent)
            apply()
        }
    }

    init() {
        appearance = AppDefaults.store.string(forKey: Key.appearance).flatMap(Appearance.init(rawValue:)) ?? .system
        accentHex = AppDefaults.store.string(forKey: Key.accent)
    }

    /// 実際に使うアクセントカラー
    var accentColor: NSColor {
        accentHex.map(NSColor.init(hex:)) ?? .controlAccentColor
    }

    var accent: Color { Color(nsColor: accentColor) }

    /// HTML（Markdown のプレビュー）で使う色
    static var accentHex: String { shared.accentColor.hexString }

    /// 外観をアプリ全体に反映し、色を使っている画面に描き直しを知らせる
    func apply() {
        NSApp?.appearance = appearance.nsAppearance
        NotificationCenter.default.post(name: .macornThemeChanged, object: nil)
    }
}

extension Notification.Name {
    /// テーマ（外観・アクセントカラー）が変わったとき
    static let macornThemeChanged = Notification.Name("macornThemeChanged")
}

/// 一覧の選択中の行を、テーマのアクセントカラーで塗る
class ThemedRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let color = isEmphasized ? Theme.shared.accentColor : Theme.shared.accentColor.withAlphaComponent(0.22)
        color.setFill()
        let rect = bounds.insetBy(dx: 4, dy: 1)
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
    }

    /// 選択中の行の文字を白にするのは、塗りが濃いときだけ（操作対象でない画面では普通の色）
    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        isSelected && isEmphasized ? .emphasized : .normal
    }
}
