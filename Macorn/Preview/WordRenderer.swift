import Foundation
import UniformTypeIdentifiers

/// Word の書類（.docx・.doc）を、プレビューの幅に合わせて折り返す HTML にする
///
/// 変換は macOS のクイックルックと同じもの（qlmanage）に任せるので、見出し・表・画像の見た目はクイックルックと変わらない。
/// クイックルックのままだとページの幅が決め打ち（600pt ほど）で、狭いと行の右が切れ、広げても余白が増えるだけなので、
/// その決め打ちだけを外して、プレビューの幅で折り返す
enum WordRenderer {
    static let types: [UTType] = [
        UTType("org.openxmlformats.wordprocessingml.document"),
        UTType("com.microsoft.word.doc"),
    ].compactMap { $0 }

    static func isWord(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return types.contains { type.conforms(to: $0) }
    }

    /// ページの幅の決め打ちを外し、画像・表をはみ出させない
    /// （クイックルックの HTML は、ページを `body > div` に幅・余白つきで置いている）
    nonisolated static let style = """
    <style id="macorn-word">
    html, body { margin: 0 !important; padding: 0 !important; background: #fff; }
    body > div { width: auto !important; min-height: 0 !important; max-width: 1000px; margin: 0 auto !important;
                 padding: 20px 28px 48px !important; box-sizing: border-box; overflow: visible !important; }
    img, svg { max-width: 100% !important; height: auto !important; }
    table { max-width: 100% !important; }
    td, th { overflow-wrap: anywhere; }
    </style>
    """

    /// 変換して、表示する HTML の場所を返す。変換できなければ nil
    /// directory はこの変換専用の作業場所（中身は消してから使う）
    nonisolated static func render(_ url: URL, into directory: URL) async -> URL? {
        let manager = FileManager.default
        try? manager.removeItem(at: directory)
        guard (try? manager.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        process.arguments = ["-p", "-o", directory.path, url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let finished: Bool = await withCheckedContinuation { continuation in
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus == 0)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: false)
                return
            }
            // 固まったときのために、しばらくで打ち切る
            DispatchQueue.global().asyncAfter(deadline: .now() + 20) {
                if process.isRunning { process.terminate() }
            }
        }
        guard finished,
              let bundle = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?
                  .first(where: { $0.pathExtension == "qlpreview" })
        else { return nil }
        let page = bundle.appendingPathComponent("Preview.html")
        guard let html = try? String(contentsOf: page, encoding: .utf8) else { return nil }
        try? styled(html).write(to: page, atomically: true, encoding: .utf8)
        return page
    }

    /// クイックルックの HTML に、幅に合わせて折り返すための指定を足す
    nonisolated static func styled(_ html: String) -> String {
        if let head = html.range(of: "</head>", options: .caseInsensitive) {
            var result = html
            result.insert(contentsOf: style, at: head.lowerBound)
            return result
        }
        return style + html
    }
}
