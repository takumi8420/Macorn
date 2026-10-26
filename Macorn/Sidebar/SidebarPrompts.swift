import AppKit

/// サイドバーから出す入力・確認のダイアログ。
enum SidebarPrompts {
    static func createTag(parent: Tag?, in store: TagStore) {
        let prefix = parent.map { $0.name + "/" } ?? ""
        guard let name = ask(
            title: parent.map { "「\($0.name)」の下にタグを作る" } ?? "タグを作る",
            message: "/ で区切ると階層になります（例: 仕事/案件A）。",
            value: "", placeholder: "タグの名前", button: "作成"
        ) else { return }
        store.createTag(named: prefix + name)
    }

    static func renameTag(_ tag: Tag, in store: TagStore) {
        guard let name = ask(
            title: "タグの名前を変更",
            message: "下の階層のタグの名前もいっしょに変わります。/ で区切ると階層になります。",
            value: tag.name, placeholder: "タグの名前", button: "変更"
        ) else { return }
        if !store.renameTag(tag.id, to: name) {
            let alert = NSAlert()
            alert.messageText = "「\(name)」には変えられません。"
            alert.informativeText = "同じ名前のタグがあるか、名前が空です。"
            alert.runModal()
        }
    }

    static func deleteTag(_ tag: Tag, in store: TagStore) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "タグ「\(tag.name)」を削除しますか？"
        alert.informativeText = "下の階層のタグも削除し、付けていた項目からも外します。ファイル自体は消えません。"
        let delete = alert.addButton(withTitle: "削除")
        delete.hasDestructiveAction = true
        alert.addButton(withTitle: "キャンセル")
        if alert.runModal() == .alertFirstButtonReturn { store.deleteTag(tag.id) }
    }

    static func renameFavorite(_ item: SidebarItem, in store: SidebarStore) {
        guard let name = ask(
            title: "お気に入りの表示名を変更",
            message: "サイドバーに出す名前だけが変わります（フォルダの名前は変わりません）。空にするとフォルダ名に戻ります。",
            value: item.name, placeholder: FileManager.default.displayName(atPath: item.url.path), button: "変更"
        ) else { return }
        store.renameFavorite(item.url, to: name)
    }

    private static func ask(title: String, message: String, value: String, placeholder: String, button: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = value
        field.placeholderString = placeholder
        alert.accessoryView = field
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "キャンセル")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }
}
