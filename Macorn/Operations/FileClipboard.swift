import AppKit

/// ファイルのコピー・カット・ペースト（要件 F-04）。
/// クリップボードには普通のファイル URL を書くので、Finder やほかのアプリにも貼り付けられる。
/// macOS にはファイルの「カット」がないため、カットしたときのクリップボードの番号を覚えておき、
/// 次のペーストが同じ内容なら移動として扱う。
enum FileClipboard {
    private static var cutChangeCount: Int?
    private static var pasteboard: NSPasteboard { .general }

    static func write(_ urls: [URL], cut: Bool) {
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
        cutChangeCount = cut ? pasteboard.changeCount : nil
    }

    static var fileURLs: [URL] {
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        return objects ?? []
    }

    static var hasFiles: Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    static var isCut: Bool {
        cutChangeCount != nil && cutChangeCount == pasteboard.changeCount
    }

    /// カットした項目を移動し終えたら、二重に移動しないようクリップボードを空にする。
    static func finishCut() {
        cutChangeCount = nil
        pasteboard.clearContents()
    }
}
