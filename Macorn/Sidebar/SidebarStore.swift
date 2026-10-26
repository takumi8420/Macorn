import AppKit
import Observation

struct SidebarItem: Identifiable, Hashable {
    var url: URL
    var name: String
    var symbol: String
    var isEjectable = false
    /// サイドバーで付けた表示名（無ければフォルダ名・タグの名前）
    var customName: String?
    /// 項目が見つからない（移動・削除された、タグが削除された）
    var isMissing = false
    /// タグの行（項目ではなくタグの一覧を開く）
    var tagID: UUID?

    var id: String { tagID.map { "tag:" + $0.uuidString } ?? url.path }
}

/// サイドバーのセクション。順番と表示・非表示を変えられる。
/// 「お気に入り」「タグ」「場所」は中身が決まっているもの。ほかに、タグ1つ分の一覧と、自分で作るセクションがある
enum SidebarSection: Hashable, Identifiable {
    case favorites, tags, locations
    /// 1つのタグを、そのタグが付いた項目の一覧としてセクションにしたもの
    case tag(UUID)
    /// 自分で名前を付けて作るセクション。タグ・フォルダ・ファイルを並べるだけで、項目に何かを付けるわけではない
    case custom(UUID)

    var id: String {
        switch self {
        case .favorites: "favorites"
        case .tags: "tags"
        case .locations: "locations"
        case .tag(let id): "tag:" + id.uuidString
        case .custom(let id): "custom:" + id.uuidString
        }
    }

    init?(id: String) {
        switch id {
        case "favorites": self = .favorites
        case "tags": self = .tags
        case "locations": self = .locations
        default:
            if id.hasPrefix("tag:"), let uuid = UUID(uuidString: String(id.dropFirst(4))) {
                self = .tag(uuid)
            } else if id.hasPrefix("custom:"), let uuid = UUID(uuidString: String(id.dropFirst(7))) {
                self = .custom(uuid)
            } else {
                return nil
            }
        }
    }

    var title: String {
        switch self {
        case .favorites: "お気に入り"
        case .tags: "タグ"
        case .locations: "場所"
        case .tag(let id): TagStore.shared.tag(id: id)?.name ?? "（削除されたタグ）"
        case .custom(let id): SidebarStore.shared.customSection(id)?.name ?? "セクション"
        }
    }

    /// タグ・フォルダ・ファイルを自由に並べられるセクション（お気に入りと自分で作ったもの）
    var holdsItems: Bool {
        switch self {
        case .favorites, .custom: true
        default: false
        }
    }

    static let defaultOrder: [SidebarSection] = [.favorites, .tags, .locations]
}

/// 自分で作るセクション
struct CustomSidebarSection: Identifiable, Hashable {
    let id: UUID
    var name: String
    var items: [SidebarItem]
}

/// サイドバーの構成（お気に入り・自分で作ったセクション・場所・セクションの順番）。全ウィンドウで共有する。
///
/// お気に入りは「お気に入り」のタグが付いた項目の一覧で、ここではその並び順と表示名を覚えている。
/// お気に入りと自分で作ったセクションには、タグそのものも置ける。1つのタグを置けるのは1か所だけ。
@Observable
final class SidebarStore {
    static let shared = SidebarStore(defaults: sharedDefaults)

    /// 共有のサイドバーの設定の保存先。ユニットテストと、MACORN_DEFAULTS_SUITE を指定した自動操作では、
    /// 普段の設定（お気に入りの並びなど）を書き換えないよう別の場所を使う
    private static var sharedDefaults: UserDefaults {
        let env = ProcessInfo.processInfo.environment
        if let suite = env["MACORN_DEFAULTS_SUITE"], let defaults = UserDefaults(suiteName: suite) { return defaults }
        if env["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil {
            return UserDefaults(suiteName: "dev.macorn.Macorn.tests") ?? .standard
        }
        return .standard
    }

    private static let favoritesKey = "sidebarFavorites"
    private static let sectionsKey = "sidebarSections"
    private static let hiddenSectionsKey = "sidebarHiddenSections"
    private static let customSectionsKey = "sidebarCustomSections"

    /// セクションの順番（タグのセクション・自分で作ったセクションも含む）と、隠しているセクション
    private(set) var sections: [SidebarSection] = SidebarSection.defaultOrder
    private(set) var hiddenSections: Set<String> = []

    private(set) var favorites: [SidebarItem] = []
    private(set) var customSections: [CustomSidebarSection] = []
    private(set) var volumes: [SidebarItem] = []

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// 設定の保存先（テストでは別の場所を渡す）
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let tags: TagStore

    init(defaults: UserDefaults = .standard, tags: TagStore = .shared) {
        self.defaults = defaults
        self.tags = tags
        favorites = loadItems(Self.loadFavoriteRecords(from: defaults))
        customSections = loadCustomSections()
        loadSections()
        migrateFavoritesToTag()
        syncFavoritesWithTag()
        refreshVolumes()

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshVolumes() }
            })
        }
        // 「お気に入り」のタグをほかの画面（右クリックの「タグ」など）で付け外ししたら、お気に入りにも反映する
        observers.append(NotificationCenter.default.addObserver(forName: .macornTagsChanged, object: tags, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncFavoritesWithTag() }
        })
    }

    // MARK: お気に入り

    func containsFavorite(_ url: URL) -> Bool {
        let key = TagStore.key(url)
        return favorites.contains { $0.tagID == nil && TagStore.key($0.url) == key }
    }

    func containsFavoriteTag(_ id: UUID) -> Bool {
        favorites.contains { $0.tagID == id }
    }

    /// タグをお気に入りに入れる（ほかのセクションに置いてあれば、こちらへ移る）
    func addFavoriteTag(_ id: UUID, at index: Int? = nil) {
        placeTag(id, in: .favorites, at: index)
    }

    func removeFavoriteTag(_ id: UUID) {
        favorites.removeAll { $0.tagID == id }
        saveFavorites()
    }

    /// お気に入りに入れる（「お気に入り」のタグを付ける）。index を指定すると、その位置に入れる（ドラッグ＆ドロップ用）
    func addFavorite(_ url: URL, at index: Int? = nil) {
        let url = url.standardizedFileURL
        // 先に並びへ入れてからタグを付ける（タグの変更の知らせで、末尾に足されないように）
        Self.insert(Self.makeItem(url), into: &favorites, at: index)
        saveFavorites()
        if !tags.hasTag(TagStore.favoritesID, on: url) { tags.assign(TagStore.favoritesID, to: [url]) }
    }

    /// お気に入りにあれば外し、無ければ入れる
    func toggleFavorite(_ url: URL) {
        if containsFavorite(url) {
            removeFavorite(url.standardizedFileURL)
        } else {
            addFavorite(url)
        }
    }

    /// 表示名を変える。空にするとフォルダ名に戻す
    func renameFavorite(_ url: URL, to name: String) {
        guard let index = favorites.firstIndex(where: { $0.url.path == url.path }) else { return }
        rename(&favorites[index], to: name)
        saveFavorites()
    }

    /// 移動・削除された項目の印を付け直す
    func refreshMissing() {
        for index in favorites.indices { refreshMissing(&favorites[index]) }
        for section in customSections.indices {
            for index in customSections[section].items.indices { refreshMissing(&customSections[section].items[index]) }
        }
    }

    /// お気に入りから外す（「お気に入り」のタグも外す）
    func removeFavorite(_ url: URL) {
        favorites.removeAll { $0.tagID == nil && $0.url.path == url.path }
        saveFavorites()
        if tags.hasTag(TagStore.favoritesID, on: url) { tags.unassign(TagStore.favoritesID, from: [url]) }
    }

    func moveFavorites(from source: IndexSet, to destination: Int) {
        favorites.move(fromOffsets: source, toOffset: destination)
        saveFavorites()
    }

    /// ドラッグ＆ドロップ: お気に入りの項目を index の位置へ動かす
    func moveFavorite(id: String, to index: Int) {
        moveItem(id: id, in: .favorites, to: index)
    }

    /// 「お気に入り」のタグを作ったばかり（初めての起動・タグの保存ファイルが新しい）なら、
    /// 今までのお気に入り（フォルダのパスの並び）にそのタグを付ける。
    /// 設定ではなくタグの保存ファイルを基準にするので、タグのファイルが別のもの（テストなど）でもお気に入りは消えない
    private func migrateFavoritesToTag() {
        guard tags.consumeCreatedFavoritesTag() else { return }
        let urls = favorites.filter { $0.tagID == nil }.map(\.url)
        if !urls.isEmpty { tags.assign(TagStore.favoritesID, to: urls) }
    }

    /// お気に入りの並びを「お気に入り」のタグに合わせる。タグが付いた項目を足し、外れた項目を除く。
    /// 1つ外れて1つ増えたときは、移動・改名とみなして同じ位置・表示名のまま入れ替える
    private func syncFavoritesWithTag() {
        let tagged = tags.urls(taggedWith: TagStore.favoritesID, includingDescendants: false)
        let taggedKeys = Set(tagged.map { TagStore.key($0) })
        let presentKeys = Set(favorites.filter { $0.tagID == nil }.map { TagStore.key($0.url) })
        let removed = favorites.indices.filter { favorites[$0].tagID == nil && !taggedKeys.contains(TagStore.key(favorites[$0].url)) }
        let added = tagged.filter { !presentKeys.contains(TagStore.key($0)) }
        guard !removed.isEmpty || !added.isEmpty else { return }
        if removed.count == 1, added.count == 1 {
            var item = Self.makeItem(added[0])
            item.customName = favorites[removed[0]].customName
            item.name = item.customName ?? item.name
            favorites[removed[0]] = item
        } else {
            for index in removed.reversed() { favorites.remove(at: index) }
            favorites.append(contentsOf: added.map(Self.makeItem))
        }
        saveFavorites()
    }

    private func saveFavorites() {
        defaults.set(favorites.map(Self.record(for:)), forKey: Self.favoritesKey)
    }

    private static func loadFavoriteRecords(from defaults: UserDefaults) -> [[String: String]] {
        if let saved = defaults.array(forKey: favoritesKey) as? [[String: String]] {
            return saved
        } else if let paths = defaults.stringArray(forKey: favoritesKey) {
            // 以前はパスの配列で保存していた
            return paths.map { ["path": $0] }
        }
        return defaultFavoritePaths().map { ["path": $0] }
    }

    // MARK: タグ・フォルダ・ファイルを置くセクション（お気に入りと自分で作ったセクション）

    func items(in section: SidebarSection) -> [SidebarItem] {
        switch section {
        case .favorites: favorites
        case .custom(let id): customSection(id)?.items ?? []
        default: []
        }
    }

    func customSection(_ id: UUID) -> CustomSidebarSection? {
        customSections.first { $0.id == id }
    }

    /// タグが置いてあるセクション（お気に入りか、自分で作ったセクション）
    func placement(ofTag id: UUID) -> SidebarSection? {
        if containsFavoriteTag(id) { return .favorites }
        return customSections.first { $0.items.contains { $0.tagID == id } }.map { .custom($0.id) }
    }

    /// タグを section の index の位置に置く。ほかに置いてあれば、そこからは外す（1つのタグは1か所だけ）
    func placeTag(_ id: UUID, in section: SidebarSection, at index: Int? = nil) {
        guard section.holdsItems, let tag = tags.tag(id: id) else { return }
        if let current = placement(ofTag: id), current != section {
            removeItem(id: "tag:" + id.uuidString, from: current)
        }
        let item = SidebarItem(url: TagLocation.url(for: id), name: tag.name, symbol: "tag.fill", tagID: id)
        mutateItems(section) { Self.insert(item, into: &$0, at: index) }
    }

    /// フォルダ・ファイルを section の index の位置に置く。お気に入りなら「お気に入り」のタグも付く
    func placeURL(_ url: URL, in section: SidebarSection, at index: Int? = nil) {
        switch section {
        case .favorites: addFavorite(url, at: index)
        case .custom: mutateItems(section) { Self.insert(Self.makeItem(url.standardizedFileURL), into: &$0, at: index) }
        default: break
        }
    }

    /// section の中で項目を index の位置へ動かす
    func moveItem(id: String, in section: SidebarSection, to index: Int) {
        mutateItems(section) { items in
            guard let item = items.first(where: { $0.id == id }) else { return }
            Self.insert(item, into: &items, at: index)
        }
    }

    /// section から項目を外す。お気に入りのフォルダ・ファイルなら「お気に入り」のタグも外す
    func removeItem(id: String, from section: SidebarSection) {
        if section == .favorites, let item = favorites.first(where: { $0.id == id }), item.tagID == nil {
            removeFavorite(item.url)
            return
        }
        mutateItems(section) { $0.removeAll { $0.id == id } }
    }

    /// 項目の表示名を変える。空にすると元の名前に戻す
    func renameItem(id: String, in section: SidebarSection, to name: String) {
        mutateItems(section) { items in
            guard let index = items.firstIndex(where: { $0.id == id }) else { return }
            rename(&items[index], to: name)
        }
    }

    /// 新しいセクションを作る。before を指定するとそのセクションの前、指定しなければ最後に置く
    @discardableResult
    func createSection(named rawName: String, before target: SidebarSection? = nil) -> SidebarSection? {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        let custom = CustomSidebarSection(id: UUID(), name: name, items: [])
        customSections.append(custom)
        let section = SidebarSection.custom(custom.id)
        if let target, let index = sections.firstIndex(of: target) {
            sections.insert(section, at: index)
        } else {
            sections.append(section)
        }
        saveCustomSections()
        saveSections()
        return section
    }

    func renameSection(_ id: UUID, to rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let index = customSections.firstIndex(where: { $0.id == id }) else { return }
        customSections[index].name = name
        saveCustomSections()
        // 見出しの名前はセクションの一覧から引くので、並びも知らせ直す
        sections = sections
    }

    /// セクションを削除する。中の項目はサイドバーから外れるだけで、項目やタグはそのまま
    func deleteSection(_ id: UUID) {
        customSections.removeAll { $0.id == id }
        sections.removeAll { $0 == .custom(id) }
        hiddenSections.remove(SidebarSection.custom(id).id)
        saveCustomSections()
        saveSections()
    }

    private func mutateItems(_ section: SidebarSection, _ body: (inout [SidebarItem]) -> Void) {
        switch section {
        case .favorites:
            body(&favorites)
            saveFavorites()
        case .custom(let id):
            guard let index = customSections.firstIndex(where: { $0.id == id }) else { return }
            body(&customSections[index].items)
            saveCustomSections()
        default:
            break
        }
    }

    /// index の位置に入れる。同じ項目がすでにあれば、そこから動かす
    private static func insert(_ item: SidebarItem, into items: inout [SidebarItem], at index: Int?) {
        if let existing = items.firstIndex(where: { $0.id == item.id }) {
            guard let index else { return }
            let current = items.remove(at: existing)
            items.insert(current, at: min(index > existing ? index - 1 : index, items.count))
        } else {
            items.insert(item, at: min(index ?? items.count, items.count))
        }
    }

    private func rename(_ item: inout SidebarItem, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        item.customName = trimmed.isEmpty ? nil : trimmed
        let fallback = item.tagID.flatMap { tags.tag(id: $0)?.name } ?? FileManager.default.displayName(atPath: item.url.path)
        item.name = item.customName ?? fallback
    }

    private func refreshMissing(_ item: inout SidebarItem) {
        if let tagID = item.tagID {
            item.isMissing = tags.tag(id: tagID) == nil
        } else {
            item.isMissing = !FileManager.default.fileExists(atPath: item.url.path)
        }
    }

    private func saveCustomSections() {
        let records: [[String: Any]] = customSections.map {
            ["id": $0.id.uuidString, "name": $0.name, "items": $0.items.map(Self.record(for:))]
        }
        defaults.set(records, forKey: Self.customSectionsKey)
    }

    private func loadCustomSections() -> [CustomSidebarSection] {
        let records = defaults.array(forKey: Self.customSectionsKey) as? [[String: Any]] ?? []
        return records.compactMap { record in
            guard let idText = record["id"] as? String, let id = UUID(uuidString: idText), let name = record["name"] as? String else { return nil }
            return CustomSidebarSection(id: id, name: name, items: loadItems(record["items"] as? [[String: String]] ?? []))
        }
    }

    /// 保存の形: フォルダ・ファイルは {"path": …}、タグは {"tag": ID}。表示名を変えたときだけ "name" も
    private static func record(for item: SidebarItem) -> [String: String] {
        var record = item.tagID.map { ["tag": $0.uuidString] } ?? ["path": item.url.path]
        if let customName = item.customName { record["name"] = customName }
        return record
    }

    private func loadItems(_ records: [[String: String]]) -> [SidebarItem] {
        records.compactMap { record in
            var item: SidebarItem
            if let tag = record["tag"], let id = UUID(uuidString: tag) {
                let name = tags.tag(id: id)?.name ?? "（削除されたタグ）"
                item = SidebarItem(url: TagLocation.url(for: id), name: name, symbol: "tag.fill", isMissing: tags.tag(id: id) == nil, tagID: id)
            } else if let path = record["path"] {
                item = Self.makeItem(URL(fileURLWithPath: path))
            } else {
                return nil
            }
            if let name = record["name"] {
                item.customName = name
                item.name = name
            }
            return item
        }
    }

    // MARK: セクション

    /// 表示するセクション（隠したもの・削除されたタグのもの・無くなったセクションは除く）
    var visibleSections: [SidebarSection] {
        sections.filter { section in
            guard !hiddenSections.contains(section.id) else { return false }
            switch section {
            case .tag(let id): return tags.tag(id: id) != nil
            case .custom(let id): return customSection(id) != nil
            default: return true
            }
        }
    }

    func isSectionHidden(_ section: SidebarSection) -> Bool { hiddenSections.contains(section.id) }

    func setSection(_ section: SidebarSection, hidden: Bool) {
        if hidden { hiddenSections.insert(section.id) } else { hiddenSections.remove(section.id) }
        saveSections()
    }

    /// 表示中のセクションの中で、1つ上（-1）・下（+1）へ動かす
    func moveSection(_ section: SidebarSection, by delta: Int) {
        let visible = visibleSections
        guard let position = visible.firstIndex(of: section) else { return }
        let target = position + delta
        guard visible.indices.contains(target), let from = sections.firstIndex(of: section),
              let to = sections.firstIndex(of: visible[target]) else { return }
        // 入れ替えではなく、目的の位置へずらして入れる（間のセクションの順番は保つ）
        sections.remove(at: from)
        sections.insert(section, at: to)
        saveSections()
    }

    /// 設定画面のドラッグでの並べ替え
    func moveSections(from source: IndexSet, to destination: Int) {
        sections.move(fromOffsets: source, toOffset: destination)
        saveSections()
    }

    func containsTagSection(_ id: UUID) -> Bool { sections.contains(.tag(id)) }

    /// ドラッグ＆ドロップ: section を target の位置へ移す（target の前に入れる）
    func moveSection(_ section: SidebarSection, before target: SidebarSection) {
        guard section != target, sections.contains(section), sections.contains(target) else { return }
        sections.removeAll { $0 == section }
        let position = sections.firstIndex(of: target) ?? sections.count
        sections.insert(section, at: position)
        saveSections()
    }

    /// ドラッグ＆ドロップ: section を最後へ移す
    func moveSectionToEnd(_ section: SidebarSection) {
        guard sections.contains(section) else { return }
        sections.removeAll { $0 == section }
        sections.append(section)
        saveSections()
    }

    /// ドラッグ＆ドロップ: タグのセクションを target の前（nil なら最後）に置く。すでにあれば動かす
    func placeTagSection(_ id: UUID, before target: SidebarSection?) {
        let section = SidebarSection.tag(id)
        if !containsTagSection(id) {
            sections.append(section)
            hiddenSections.remove(section.id)
        }
        if let target {
            moveSection(section, before: target)
        } else {
            moveSectionToEnd(section)
        }
    }

    /// タグを1つのセクションとしてサイドバーに置く。before を指定するとそのセクションの前、
    /// 指定しなければお気に入りの下に入れる。すでにあれば、その位置へ移すだけ
    func addTagSection(_ id: UUID, before target: SidebarSection? = nil) {
        let section = SidebarSection.tag(id)
        if let target, containsTagSection(id) {
            moveSection(section, before: target)
            return
        }
        guard !containsTagSection(id) else { return }
        let position: Int
        if let target, let index = sections.firstIndex(of: target) {
            position = index
        } else {
            position = (sections.firstIndex(of: .favorites) ?? -1) + 1
        }
        sections.insert(section, at: position)
        hiddenSections.remove(section.id)
        saveSections()
    }

    func removeTagSection(_ id: UUID) {
        sections.removeAll { $0 == .tag(id) }
        hiddenSections.remove(SidebarSection.tag(id).id)
        saveSections()
    }

    func resetSections() {
        // 自分で作ったセクションは消さず、最初の3つのあとに並べる
        sections = SidebarSection.defaultOrder + customSections.map { .custom($0.id) }
        hiddenSections = []
        saveSections()
    }

    private func loadSections() {
        if let ids = defaults.stringArray(forKey: Self.sectionsKey) {
            var loaded = ids.compactMap(SidebarSection.init(id:)).filter { section in
                if case .custom(let id) = section { return customSection(id) != nil }
                return true
            }
            // あとから増えたセクションは最後に足す
            for section in SidebarSection.defaultOrder where !loaded.contains(section) { loaded.append(section) }
            sections = loaded
        }
        hiddenSections = Set(defaults.stringArray(forKey: Self.hiddenSectionsKey) ?? [])
    }

    private func saveSections() {
        defaults.set(sections.map(\.id), forKey: Self.sectionsKey)
        defaults.set(Array(hiddenSections), forKey: Self.hiddenSectionsKey)
    }

    private static func defaultFavoritePaths() -> [String] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let directories: [FileManager.SearchPathDirectory] = [.desktopDirectory, .documentDirectory, .downloadsDirectory]
        let others = directories.compactMap { fm.urls(for: $0, in: .userDomainMask).first }
        return ([home] + others + [URL(fileURLWithPath: "/Applications")]).map(\.path)
    }

    private static func makeItem(_ url: URL) -> SidebarItem {
        SidebarItem(
            url: url,
            name: FileManager.default.displayName(atPath: url.path),
            symbol: symbol(for: url),
            isMissing: !FileManager.default.fileExists(atPath: url.path)
        )
    }

    private static func symbol(for url: URL) -> String {
        let fm = FileManager.default
        func matches(_ directory: FileManager.SearchPathDirectory) -> Bool {
            fm.urls(for: directory, in: .userDomainMask).first?.path == url.path
        }
        if url.path == fm.homeDirectoryForCurrentUser.path { return "house" }
        if matches(.desktopDirectory) { return "menubar.dock.rectangle" }
        if matches(.documentDirectory) { return "doc" }
        if matches(.downloadsDirectory) { return "arrow.down.circle" }
        if url.path == "/Applications" { return "square.grid.2x2" }
        return FileTransfer.isDirectory(url) || !fm.fileExists(atPath: url.path) ? "folder" : "doc"
    }

    // MARK: 場所（ボリューム）

    func refreshVolumes() {
        let keys: [URLResourceKey] = [.volumeLocalizedNameKey, .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsLocalKey, .volumeIsRootFileSystemKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        volumes = urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isRoot = values?.volumeIsRootFileSystem ?? (url.path == "/")
            let isEjectable = !isRoot && ((values?.volumeIsEjectable ?? false) || (values?.volumeIsRemovable ?? false) || values?.volumeIsLocal == false)
            let symbol: String
            if isRoot {
                symbol = "internaldrive"
            } else if values?.volumeIsLocal == false {
                symbol = "server.rack"
            } else {
                symbol = "externaldrive"
            }
            return SidebarItem(
                url: url,
                name: values?.volumeLocalizedName ?? FileManager.default.displayName(atPath: url.path),
                symbol: symbol,
                isEjectable: isEjectable
            )
        }
    }

    func eject(_ item: SidebarItem) {
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: item.url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}


/// サイドバーの中でドラッグするもの（セクション・タグ）を、文字列で受け渡す
enum SidebarDragPayload: Equatable {
    case section(SidebarSection)
    case tag(UUID)

    static let sectionPrefix = "macorn-section:"
    static let tagPrefix = "macorn-tag:"

    var string: String {
        switch self {
        case .section(let section): Self.sectionPrefix + section.id
        case .tag(let id): Self.tagPrefix + id.uuidString
        }
    }

    init?(_ string: String) {
        if string.hasPrefix(Self.sectionPrefix), let section = SidebarSection(id: String(string.dropFirst(Self.sectionPrefix.count))) {
            self = .section(section)
        } else if string.hasPrefix(Self.tagPrefix), let id = UUID(uuidString: String(string.dropFirst(Self.tagPrefix.count))) {
            self = .tag(id)
        } else {
            return nil
        }
    }
}
