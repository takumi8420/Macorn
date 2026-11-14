import AppKit
import Testing
@testable import Macorn

/// メニューのショートカット
@MainActor struct MenuShortcutTests {
    private func findItem(_ title: String, in menu: NSMenu) -> NSMenuItem? {
        var found: NSMenuItem?
        ShortcutStore.forEachItem(in: menu) { item in
            if found == nil, item.title == title { found = item }
        }
        return found
    }

    /// 右クリックのメニューをキーボードで出す項目は、既定で ⌥Return（2つのキー）。ほかの項目とは重ならない
    @Test func contextMenuShortcutIsOptionReturn() throws {
        let menu = MainMenu.build()
        let item = try #require(findItem("右クリックのメニューを出す", in: menu))
        #expect(item.keyEquivalent == "\r")
        #expect(item.keyEquivalentModifierMask == [.option])
        #expect(CommandCatalog.shortcutText(for: item) == "⌥↩")
        let id = try #require(ShortcutStore.identifier(for: item))
        let combo = KeyCombo(key: item.keyEquivalent, flags: item.keyEquivalentModifierMask)
        #expect(ShortcutStore.conflict(for: combo, excluding: id, in: menu) == nil)
    }
}
