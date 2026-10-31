import AppKit
import UniformTypeIdentifiers

/// Macorn で開けるファイルの種類（プレビューできるもの）。設定から種類ごとに既定のアプリにできる。
/// 「このアプリケーションで開く」に出すための申告は Macorn-Info.plist（CFBundleDocumentTypes）にある。
enum PreviewFileKind: String, CaseIterable, Identifiable {
    case pdf, markdown, html, csv, image, video, audio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pdf: "PDF"
        case .markdown: "Markdown（.md）"
        case .html: "HTML"
        case .csv: "CSV・TSV"
        case .image: "画像（PNG・JPEG・GIF・HEIC・WebP など）"
        case .video: "動画（MP4・MOV など）"
        case .audio: "音声（MP3・M4A・WAV など）"
        }
    }

    /// 既定のアプリを変える種類。macOS の既定は具体的な種類ごとなので、よく使うものを並べる（先頭で状態を判断する）
    var typeIdentifiers: [String] {
        switch self {
        case .pdf: ["com.adobe.pdf"]
        case .markdown: ["net.daringfireball.markdown"]
        case .html: ["public.html"]
        case .csv: ["public.comma-separated-values-text", "public.tab-separated-values-text"]
        case .image: ["public.png", "public.jpeg", "com.compuserve.gif", "public.heic", "org.webmproject.webp",
                      "public.tiff", "com.microsoft.bmp", "public.svg-image"]
        case .video: ["public.mpeg-4", "com.apple.quicktime-movie", "com.apple.m4v-video"]
        case .audio: ["public.mp3", "com.apple.m4a-audio", "com.microsoft.waveform-audio", "public.aiff-audio"]
        }
    }
}

/// 種類ごとの既定のアプリを Macorn にする・元に戻す。値は macOS 側の設定なので、毎回 macOS から読み直す。
/// 既定にする前のアプリを覚えておき、オフにしたらそれに戻す。
enum DefaultFileApps {
    private static var macornIdentifier: String { Bundle.main.bundleIdentifier ?? "dev.macorn.Macorn" }

    private static func handler(for identifier: String) -> URL? {
        guard let type = UTType(identifier) else { return nil }
        return NSWorkspace.shared.urlForApplication(toOpen: type)
    }

    private static func isMacorn(_ app: URL?) -> Bool {
        guard let app else { return false }
        return Bundle(url: app)?.bundleIdentifier == macornIdentifier
    }

    /// そのファイルの既定のアプリが Macorn か（Macorn の中で「開く」と自分に戻ってくる）
    static func isMacornDefault(for file: URL) -> Bool {
        isMacorn(NSWorkspace.shared.urlForApplication(toOpen: file))
    }

    /// そのファイルを開ける Macorn 以外のアプリ（覚えておいた前のアプリを優先）
    static func otherApp(for file: URL) -> URL? {
        guard let type = UTType(filenameExtension: file.pathExtension.lowercased()) else { return nil }
        let saved = Preferences.previousFileHandlers[type.identifier]
        if let saved, FileManager.default.fileExists(atPath: saved) { return URL(fileURLWithPath: saved) }
        let candidates = NSWorkspace.shared.urlsForApplications(toOpen: file).filter { !isMacorn($0) }
        return candidates.first { $0.path.hasPrefix("/System/") || $0.path.hasPrefix("/Applications/Safari") } ?? candidates.first
    }

    /// Macorn の外のアプリで開く。既定のアプリが Macorn なら、ほかのアプリで開く（自分に戻ってこないように）
    static func openOutside(_ file: URL) {
        if isMacornDefault(for: file), let app = otherApp(for: file) {
            NSWorkspace.shared.open([file], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(file)
        }
    }

    /// その種類を Macorn で開くようになっているか（代表の種類で判断する）
    static func opensFiles(of kind: PreviewFileKind) -> Bool {
        kind.typeIdentifiers.first.map { isMacorn(handler(for: $0)) } ?? false
    }

    /// その種類の既定のアプリを Macorn にする（on）か、前のアプリに戻す（off）
    static func setOpensFiles(_ enabled: Bool, kind: PreviewFileKind) async throws {
        var previous = Preferences.previousFileHandlers
        for identifier in kind.typeIdentifiers {
            guard let type = UTType(identifier) else { continue }
            let current = handler(for: identifier)
            let target: URL
            if enabled {
                if let current, !isMacorn(current) { previous[identifier] = current.path }
                target = Bundle.main.bundleURL
            } else {
                guard isMacorn(current) else { continue }
                target = restoreTarget(for: type, saved: previous[identifier])
                previous[identifier] = nil
            }
            try await NSWorkspace.shared.setDefaultApplication(at: target, toOpen: type)
        }
        Preferences.previousFileHandlers = previous
    }

    /// 戻す先：覚えておいたアプリ。なければ、その種類を開ける Macorn 以外のアプリ（macOS の付属を優先）
    private static func restoreTarget(for type: UTType, saved: String?) -> URL {
        if let saved, FileManager.default.fileExists(atPath: saved) { return URL(fileURLWithPath: saved) }
        let candidates = NSWorkspace.shared.urlsForApplications(toOpen: type).filter { !isMacorn($0) }
        return candidates.first { $0.path.hasPrefix("/System/") } ?? candidates.first
            ?? URL(fileURLWithPath: "/System/Applications/Preview.app")
    }
}
