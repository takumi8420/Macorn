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

/// ほかのアプリのファイルを選ぶ画面を、Macorn のフォルダへ移すキー
struct FilePanelJumpKeyTests {
    /// 既定は ⌘G。修飾キーが過不足なく同じときだけ当たる（⇧⌘G の「フォルダへ移動」は通す）
    @Test func defaultKeyMatchesOnlyExactModifiers() {
        let key = GlobalHotKey.defaultKey
        #expect(key.display == "⌘G")
        #expect(key.matches(keyCode: 5, flags: [.command]))
        #expect(key.matches(keyCode: 5, flags: [.command, .capsLock, .numericPad]))
        #expect(!key.matches(keyCode: 5, flags: [.command, .shift]))
        #expect(!key.matches(keyCode: 5, flags: []))
        #expect(!key.matches(keyCode: 0, flags: [.command]))
    }

    @Test func roundTripsThroughJSON() throws {
        let key = GlobalHotKey(keyCode: 46, flags: [.control, .option, .function], display: "⌃⌥M")
        let decoded = try JSONDecoder().decode(GlobalHotKey.self, from: JSONEncoder().encode(key))
        #expect(decoded == key)
        #expect(decoded.flags == [.control, .option])
    }
}
