import AppKit
import SwiftUI

/// タグの一覧を開く場所。`macorn-tag:///<タグの ID>` の形の URL で表す。
/// 画面はこの URL を「フォルダ」の代わりに開き、タグが付いた項目を並べる。
enum TagLocation {
    static let scheme = "macorn-tag"

    static func url(for id: UUID) -> URL {
        URL(string: "\(scheme):///\(id.uuidString)")!
    }

    static func tagID(from url: URL) -> UUID? {
        guard url.scheme == scheme else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }

    /// 保存用の文字列（タグは URL、フォルダはパス）から場所を作る
    static func location(from saved: String) -> URL {
        saved.hasPrefix(scheme + ":") ? (URL(string: saved) ?? FileManager.default.homeDirectoryForCurrentUser) : URL(fileURLWithPath: saved)
    }

    static func savedString(for url: URL) -> String {
        url.isFileURL ? url.path : url.absoluteString
    }

    /// 保存した場所が今も開けるか（フォルダがある・タグがある）
    static func exists(_ saved: String) -> Bool {
        let url = location(from: saved)
        if let id = tagID(from: url) { return TagStore.shared.tag(id: id) != nil }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// 画面のタイトルやパンくずに出す名前
    static func displayName(for url: URL) -> String {
        if let id = tagID(from: url) {
            return "タグ: " + (TagStore.shared.tag(id: id)?.name ?? "（削除済み）")
        }
        return url.path == "/" ? FileManager.default.displayName(atPath: "/") : FileManager.default.displayName(atPath: url.path)
    }
}

/// タグ（要件 S-07 を独自タグとして実装）: タグの一覧の表示、タグの編集、タグを付けるドロップ。
extension FileBrowserViewController {
    var isTagView: Bool { TagLocation.tagID(from: state.currentURL) != nil }
    var currentTag: Tag? { TagLocation.tagID(from: state.currentURL).flatMap(TagStore.shared.tag(id:)) }

    /// タグの一覧の、いちばん上の項目を読む（タグが付いた項目。消えたものは除く）
    func readTaggedEntries(_ id: UUID) async -> Result<[FileEntry], any Error> {
        await TagStore.shared.resolveMovedItems()
        let urls = TagStore.shared.urls(taggedWith: id)
        let entries = await Task.detached(priority: .userInitiated) {
            urls.filter { FileManager.default.fileExists(atPath: $0.path) }.map(DirectoryReader.entry(for:))
        }.value
        return .success(entries)
    }

    /// タグの一覧の、いちばん上の項目（画面のルート）の代わりの情報
    static func tagRootEntry(for url: URL) -> FileEntry {
        FileEntry(
            url: url, name: TagLocation.displayName(for: url), isFolder: true, isPackage: false,
            isHidden: false, isSymbolicLink: false, size: nil, dateModified: nil, kind: "タグ"
        )
    }

    @objc func tagsDidChange(_ notification: Notification) {
        if isTagView {
            if currentTag == nil {
                // 開いているタグが削除されたら、ホームへ戻る
                navigate(to: FileManager.default.homeDirectoryForCurrentUser)
            } else {
                delegate?.browser(self, didNavigateTo: state.currentURL)
                load(root)
            }
        }
        reloadVisibleRows()
    }

    // MARK: - タグを編集する

    /// ⌥⌘G: 選択中の項目のタグを編集する（なければ表示中のフォルダ）
    @objc func editTags(_ sender: Any?) {
        var urls = selectedURLs
        if urls.isEmpty, !isTagView { urls = [state.currentURL] }
        guard !urls.isEmpty else {
            NSSound.beep()
            return
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: TagEditorView(
            urls: urls,
            store: .shared,
            onClose: { [weak popover] in popover?.performClose(nil) },
            onManage: { [weak popover] in
                popover?.performClose(nil)
                SettingsWindowController.shared.show(tab: .tags)
            }
        ))
        // 選択中の最初の行の横に出す。行がなければ一覧の上の方に出す
        let row = outlineView.selectedRowIndexes.first ?? -1
        let rect = row >= 0
            ? outlineView.rect(ofRow: row)
            : NSRect(x: outlineView.visibleRect.midX - 1, y: outlineView.visibleRect.minY + 4, width: 2, height: 2)
        popover.show(relativeTo: rect, of: outlineView, preferredEdge: row >= 0 ? .maxY : .minY)
        tagPopover = popover
    }

    /// 右クリックメニューの「タグ」: よく使うタグを付け外しでき、最後に「タグを編集…」
    func tagMenuItem(for urls: [URL]) -> NSMenuItem {
        let item = NSMenuItem(title: "タグ", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let store = TagStore.shared
        for tag in store.sortedTags.prefix(20) {
            let tagItem = NSMenuItem(title: String(repeating: "    ", count: tag.depth) + tag.leafName, action: #selector(toggleTagFromMenu(_:)), keyEquivalent: "")
            tagItem.target = self
            tagItem.representedObject = (tag.id, urls) as (UUID, [URL])
            let count = urls.filter { store.hasTag(tag.id, on: $0) }.count
            tagItem.state = count == 0 ? .off : (count == urls.count ? .on : .mixed)
            tagItem.image = Self.tagDot(tag.color)
            submenu.addItem(tagItem)
        }
        if !store.tags.isEmpty { submenu.addItem(.separator()) }
        let edit = NSMenuItem(title: "タグを編集…", action: #selector(editTags(_:)), keyEquivalent: "")
        edit.target = self
        submenu.addItem(edit)
        item.submenu = submenu
        return item
    }

    @objc private func toggleTagFromMenu(_ sender: NSMenuItem) {
        guard let (id, urls) = sender.representedObject as? (UUID, [URL]) else { return }
        TagStore.shared.toggle(id, on: urls)
    }

    static func tagDot(_ hex: String, size: CGFloat = 10) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor(hex: hex).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
    }
}
