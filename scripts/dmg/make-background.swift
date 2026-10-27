// DMG のウィンドウの背景（「Macorn を『アプリケーション』へドラッグ」の案内）を描く。
// 使い方（リポジトリのルートで）: swift scripts/dmg/make-background.swift scripts/dmg
// 出力: background.png（1x）と background@2x.png。release.sh が tiffutil で1つの TIFF にまとめる。
// アイコンの位置（左 170,200／右 490,200。ウィンドウ 660×400）は release.sh の Finder の設定とそろえる。
import AppKit

let size = NSSize(width: 660, height: 400)
let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let cream = color(0xFBF5EA)      // 背景（ブランドのクリームを淡く）
let orange = color(0xC9773A)     // 矢印（リスの体の色）
let ink = color(0x2A211B)        // 文字
let muted = color(0x2A211B, 0.55)

func font(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: weight)
}

func drawCentered(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let textSize = (text as NSString).size(withAttributes: attributes)
    (text as NSString).draw(at: NSPoint(x: (size.width - textSize.width) / 2, y: y), withAttributes: attributes)
}

func render(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    cream.setFill()
    NSRect(origin: .zero, size: size).fill()

    // 上の見出し（座標は左下が原点。アイコンの中心は上から 200 = 下から 200）
    drawCentered("Macorn を「アプリケーション」へドラッグ", y: size.height - 74, font: font(20, .semibold), color: ink)

    // 2つのアイコンの間の矢印（アイコン 128px の端から少し離す）
    let y: CGFloat = size.height - 200
    let start = NSPoint(x: 170 + 64 + 30, y: y)
    let end = NSPoint(x: 490 - 64 - 30, y: y)
    let shaft = NSBezierPath()
    shaft.move(to: start)
    shaft.line(to: NSPoint(x: end.x - 14, y: y))
    shaft.lineWidth = 6
    shaft.lineCapStyle = .round
    orange.setStroke()
    shaft.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: end.x + 4, y: y))
    head.line(to: NSPoint(x: end.x - 20, y: y + 16))
    head.line(to: NSPoint(x: end.x - 20, y: y - 16))
    head.close()
    orange.setFill()
    head.fill()

    // 下の補足
    drawCentered("入れたら「アプリケーション」から Macorn を開いてください", y: 58, font: font(13, .regular), color: muted)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
try render(scale: 1).write(to: outDir.appendingPathComponent("background.png"))
try render(scale: 2).write(to: outDir.appendingPathComponent("background@2x.png"))
print("描きました: \(outDir.path)/background.png, background@2x.png")
