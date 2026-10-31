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

    /// お気に入り・自分で作ったセクションの項目の表示名を変える
    static func renameItem(_ item: SidebarItem, in section: SidebarSection, store: SidebarStore) {
        let original = item.tagID.flatMap { TagStore.shared.tag(id: $0)?.name } ?? FileManager.default.displayName(atPath: item.url.path)
        guard let name = ask(
            title: "表示名を変更",
            message: "サイドバーに出す名前だけが変わります（フォルダやタグの名前は変わりません）。空にすると元の名前に戻ります。",
            value: item.name, placeholder: original, button: "変更"
        ) else { return }
        store.renameItem(id: item.id, in: section, to: name)
    }

    /// 新しいセクションを作る（サイドバーの見た目だけのまとまり）
    static func createSection(before target: SidebarSection? = nil, in store: SidebarStore) {
        guard let name = ask(
            title: "セクションを作る",
            message: "サイドバーでタグ・フォルダ・ファイルをまとめる見出しです。項目には何も付きません。作ったら、タグやフォルダをドラッグして入れてください。",
            value: "", placeholder: "セクションの名前", button: "作成"
        ) else { return }
        store.createSection(named: name, before: target)
    }

    /// 新しいセクションを作り、フォルダ・ファイルをそこに置く（一覧の右クリック「セクションに置く」から）
    static func createSection(placing urls: [URL], in store: SidebarStore) {
        guard let name = ask(
            title: "セクションを作って置く",
            message: "サイドバーに新しい見出しを作り、選んだ項目をそこに置きます。項目には何も付きません。",
            value: "", placeholder: "セクションの名前", button: "作成"
        ), let section = store.createSection(named: name) else { return }
        for url in urls { store.placeURL(url, in: section) }
    }

    static func renameSection(_ id: UUID, in store: SidebarStore) {
        guard let section = store.customSection(id), let name = ask(
            title: "セクションの名前を変更", message: "", value: section.name, placeholder: "セクションの名前", button: "変更"
        ) else { return }
        store.renameSection(id, to: name)
    }

    static func deleteSection(_ id: UUID, in store: SidebarStore) {
        guard let section = store.customSection(id) else { return }
        if section.items.isEmpty {
            store.deleteSection(id)
            return
        }
        let alert = NSAlert()
        alert.messageText = "セクション「\(section.name)」を削除しますか？"
        alert.informativeText = "中の項目はサイドバーから外れるだけで、フォルダ・ファイル・タグはそのまま残ります。"
        alert.addButton(withTitle: "削除")
        alert.addButton(withTitle: "キャンセル")
        if alert.runModal() == .alertFirstButtonReturn { store.deleteSection(id) }
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
