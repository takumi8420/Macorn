import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// サイドバーのタグの木（「仕事」の下に「仕事/案件A」）
struct TagTreeNode: Identifiable, Hashable {
    var tag: Tag
    var children: [TagTreeNode]?

    var id: UUID { tag.id }

    static func build(from store: TagStore) -> [TagTreeNode] {
        func node(_ tag: Tag) -> TagTreeNode {
            let children = store.children(of: tag).map(node)
            return TagTreeNode(tag: tag, children: children.isEmpty ? nil : children)
        }
        return store.rootTags.map(node)
    }
}

struct SidebarView: View {
    var store: SidebarStore
    /// 操作対象の画面（2画面のときはその時々で変わる）
    var window: WindowModel
    var tags: TagStore = .shared
    var onSelect: (URL) -> Void

    var body: some View {
        List(selection: selection) {
            // セクションの順番と表示・非表示は、見出しの右クリックか設定で変えられる
            ForEach(store.visibleSections) { section in
                sectionView(section)
            }
            if store.visibleSections.isEmpty {
                Button("サイドバーを元に戻す") { store.resetSections() }
            }
        }
        .listStyle(.sidebar)
        // 選択の色やアイコンを、テーマのアクセントカラーにする
        .tint(Theme.shared.accent)
        .onAppear { store.refreshMissing() }
    }

    @ViewBuilder
    private func sectionView(_ section: SidebarSection) -> some View {
        switch section {
        case .favorites: favoritesSection
        case .tags: tagsSection
        case .locations: locationsSection
        case .tag(let id): tagSection(id)
        }
    }

    private var favoritesSection: some View {
        Section {
            ForEach(store.favorites) { item in
                FavoriteRow(item: item, store: store)
                    .tag(item.id)
            }
            .onMove { store.moveFavorites(from: $0, to: $1) }
            // Finder や一覧からフォルダをドラッグすると、その位置にお気に入りとして入る
            .onInsert(of: [.fileURL]) { index, providers in
                insertFavorites(providers, at: index)
            }
            if store.favorites.isEmpty {
                Text("フォルダやタグをここへ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            SectionHeader(section: .favorites, store: store)
        }
    }

    private var tagsSection: some View {
        Section {
            OutlineGroup(TagTreeNode.build(from: tags), children: \.children) { node in
                TagRow(tag: node.tag, tags: tags, sidebar: store)
                    .tag("tag:" + node.tag.id.uuidString)
            }
            if tags.tags.isEmpty {
                Text("項目を右クリック ›「タグ」で作れます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            SectionHeader(section: .tags, store: store) {
                Button {
                    SidebarPrompts.createTag(parent: nil, in: tags)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("タグを作る")
            }
        }
    }

    private var locationsSection: some View {
        Section {
            ForEach(store.volumes) { item in
                HStack {
                    Label(item.name, systemImage: item.symbol)
                    Spacer()
                    if item.isEjectable {
                        Button {
                            store.eject(item)
                        } label: {
                            Image(systemName: "eject.fill")
                        }
                        .buttonStyle(.borderless)
                        .help("取り出す")
                    }
                }
                .tag(item.id)
                .contextMenu {
                    if item.isEjectable {
                        Button("取り出す") { store.eject(item) }
                    }
                }
            }
        } header: {
            SectionHeader(section: .locations, store: store)
        }
    }

    /// タグを1つのセクションにしたもの。そのタグが付いた項目を並べる（クリックでその場所へ移動）
    private func tagSection(_ id: UUID) -> some View {
        Section {
            let urls = tags.urls(taggedWith: id).filter { FileManager.default.fileExists(atPath: $0.path) }
            ForEach(urls, id: \.path) { url in
                TaggedItemRow(url: url, tags: tags)
                    .tag(url.path)
            }
            if urls.isEmpty {
                Text("このタグが付いた項目はまだありません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            SectionHeader(section: .tag(id), store: store) {
                Circle()
                    .fill(Color(nsColor: NSColor(hex: tags.tag(id: id)?.color ?? "#8E8E93")))
                    .frame(width: 8, height: 8)
            }
        }
    }

    /// 表示中のフォルダ（またはタグ）と同じ項目を選択状態にする。クリックされたらそこへ移動する。
    private var selection: Binding<String?> {
        Binding(
            get: {
                let url = window.activePane.currentURL
                if let id = TagLocation.tagID(from: url) { return "tag:" + id.uuidString }
                let path = url.path
                let all = store.favorites + store.volumes
                if all.contains(where: { $0.id == path }) { return path }
                // タグのセクションに出ているフォルダ
                for case .tag(let id) in store.visibleSections where tags.urls(taggedWith: id).contains(where: { $0.path == path }) {
                    return path
                }
                return nil
            },
            set: { newValue in
                guard let newValue else { return }
                if newValue.hasPrefix("tag:"), let id = UUID(uuidString: String(newValue.dropFirst(4))) {
                    let url = TagLocation.url(for: id)
                    if url != window.activePane.currentURL { onSelect(url) }
                    return
                }
                guard newValue != window.activePane.currentURL.path else { return }
                onSelect(URL(fileURLWithPath: newValue))
            }
        )
    }

    private func insertFavorites(_ providers: [NSItemProvider], at index: Int) {
        for (offset, provider) in providers.enumerated() {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    store.addFavorite(url, at: index + offset)
                }
            }
        }
    }
}

private struct FavoriteRow: View {
    let item: SidebarItem
    var store: SidebarStore
    var tags: TagStore = .shared

    var body: some View {
        if let tagID = item.tagID {
            tagBody(tagID)
        } else {
            folderBody
        }
    }

    /// お気に入りに入れたタグ（クリックでタグの一覧を開く）
    private func tagBody(_ id: UUID) -> some View {
        let tag = tags.tag(id: id)
        return HStack(spacing: 6) {
            Image(systemName: "tag.fill")
                .foregroundStyle(Color(nsColor: NSColor(hex: tag?.color ?? "#8E8E93")))
            Text(item.customName ?? tag?.name ?? "（削除されたタグ）")
                .foregroundStyle(tag == nil ? .secondary : .primary)
                .lineLimit(1)
            Spacer()
            if tag != nil {
                Text("\(tags.count(for: id))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button("名前を変更…") { SidebarPrompts.renameFavorite(item, in: store) }
            if item.customName != nil {
                Button("タグの名前に戻す") { store.renameFavorite(item.url, to: "") }
            }
            Divider()
            Button("お気に入りから外す") { store.removeFavoriteTag(id) }
        }
    }

    private var folderBody: some View {
        Label {
            Text(item.name)
                .foregroundStyle(item.isMissing ? .secondary : .primary)
        } icon: {
            // タグの付いたフォルダは、タグの色で塗る
            if let color = tags.folderColor(for: item.url), !item.isMissing {
                Image(systemName: item.symbol == "folder" ? "folder.fill" : item.symbol)
                    .foregroundStyle(Color(nsColor: NSColor(hex: color)))
            } else {
                Image(systemName: item.isMissing ? "exclamationmark.triangle" : item.symbol)
            }
        }
        .help(item.isMissing ? "\(item.url.path) が見つかりません" : item.url.path)
        .contextMenu {
            Button("名前を変更…") { SidebarPrompts.renameFavorite(item, in: store) }
            if item.customName != nil {
                Button("フォルダ名に戻す") { store.renameFavorite(item.url, to: "") }
            }
            Button("Finder で表示") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                .disabled(item.isMissing)
            Divider()
            Button("お気に入りから外す") { store.removeFavorite(item.url) }
        }
    }
}

private struct TagRow: View {
    let tag: Tag
    var tags: TagStore
    var sidebar: SidebarStore = .shared

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(nsColor: NSColor(hex: tag.color)))
                .frame(width: 10, height: 10)
            Text(tag.leafName)
                .lineLimit(1)
            Spacer()
            Text("\(tags.count(for: tag.id))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .help(tag.name)
        // ファイルやフォルダをタグにドロップすると、そのタグを付ける
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            tags.assign(tag.id, to: files)
            return true
        }
        .contextMenu {
            Button("名前を変更…") { SidebarPrompts.renameTag(tag, in: tags) }
            Menu("色") {
                ForEach(Array(TagStore.palette.enumerated()), id: \.offset) { index, color in
                    Button {
                        tags.setColor(tag.id, to: color)
                    } label: {
                        Label(Self.colorNames[index], systemImage: tag.color == color ? "checkmark.circle.fill" : "circle.fill")
                    }
                }
                Divider()
                Button("その他の色…") { SettingsWindowController.shared.show(tab: .tags) }
            }
            Button("下の階層にタグを作る…") { SidebarPrompts.createTag(parent: tag, in: tags) }
            Divider()
            // お気に入りと並べたり、1つのセクションとして置いたりできる
            if sidebar.containsFavoriteTag(tag.id) {
                Button("お気に入りから外す") { sidebar.removeFavoriteTag(tag.id) }
            } else {
                Button("お気に入りに追加") { sidebar.addFavoriteTag(tag.id) }
            }
            if sidebar.containsTagSection(tag.id) {
                Button("サイドバーのセクションから外す") { sidebar.removeTagSection(tag.id) }
            } else {
                Button("サイドバーのセクションにする") { sidebar.addTagSection(tag.id) }
            }
            Divider()
            Button("タグを削除…", role: .destructive) { SidebarPrompts.deleteTag(tag, in: tags) }
        }
    }

    static let colorNames = ["赤", "オレンジ", "黄", "緑", "青", "紫", "ピンク", "グレー"]
}

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


/// セクションの見出し。右クリックで順番の入れ替え・隠す・（タグのセクションなら）外す
private struct SectionHeader<Accessory: View>: View {
    let section: SidebarSection
    var store: SidebarStore
    @ViewBuilder var accessory: () -> Accessory

    init(section: SidebarSection, store: SidebarStore, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.section = section
        self.store = store
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: 6) {
            if case .tag = section { accessory() }
            Text(section.title)
            Spacer()
            if case .tag = section {} else { accessory() }
        }
        // 見出しは行より右端まで広がるので、下の件数の列とそろうよう内側に寄せる
        .padding(.trailing, 10)
        .contentShape(Rectangle())
        .contextMenu {
            Button("上へ移動") { store.moveSection(section, by: -1) }
                .disabled(store.visibleSections.first == section)
            Button("下へ移動") { store.moveSection(section, by: 1) }
                .disabled(store.visibleSections.last == section)
            Divider()
            if case .tag(let id) = section {
                Button("サイドバーから外す") { store.removeTagSection(id) }
            } else {
                Button("「\(section.title)」を隠す") { store.setSection(section, hidden: true) }
            }
            Divider()
            Button("サイドバーをカスタマイズ…") { SettingsWindowController.shared.show(tab: .sidebar) }
        }
    }
}

extension SectionHeader where Accessory == EmptyView {
    init(section: SidebarSection, store: SidebarStore) {
        self.init(section: section, store: store) { EmptyView() }
    }
}

/// タグのセクションに並べる項目（フォルダはタグの色で塗る）
private struct TaggedItemRow: View {
    let url: URL
    var tags: TagStore

    var body: some View {
        let isFolder = FileTransfer.isDirectory(url)
        Label {
            Text(url.lastPathComponent).lineLimit(1)
        } icon: {
            if isFolder {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Color(nsColor: NSColor(hex: tags.folderColor(for: url) ?? "#8E8E93")))
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 16, height: 16)
            }
        }
        .help(url.path)
        .contextMenu {
            Button("Finder で表示") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }
}
