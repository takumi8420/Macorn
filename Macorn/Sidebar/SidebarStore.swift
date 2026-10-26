import AppKit
import Observation

struct SidebarItem: Identifiable, Hashable {
    var url: URL
    var name: String
    var symbol: String
    var isEjectable = false
    /// お気に入りに付けた表示名（無ければフォルダ名）
    var customName: String?
    /// フォルダが見つからない（移動・削除された）
    var isMissing = false
    /// お気に入りに入れたタグ（フォルダではなくタグの一覧を開く）
    var tagID: UUID?

    var id: String { tagID.map { "tag:" + $0.uuidString } ?? url.path }
}

/// サイドバーのセクション。順番と表示・非表示を変えられ、タグもセクションとして置ける
enum SidebarSection: Hashable, Identifiable {
    case favorites, tags, locations
    /// 1つのタグを、そのタグが付いた項目の一覧としてセクションにしたもの
    case tag(UUID)

    var id: String {
        switch self {
        case .favorites: "favorites"
        case .tags: "tags"
        case .locations: "locations"
        case .tag(let id): "tag:" + id.uuidString
        }
    }

    init?(id: String) {
        switch id {
        case "favorites": self = .favorites
        case "tags": self = .tags
        case "locations": self = .locations
        default:
            guard id.hasPrefix("tag:"), let uuid = UUID(uuidString: String(id.dropFirst(4))) else { return nil }
            self = .tag(uuid)
        }
    }

    var title: String {
        switch self {
        case .favorites: "お気に入り"
        case .tags: "タグ"
        case .locations: "場所"
        case .tag(let id): TagStore.shared.tag(id: id)?.name ?? "（削除されたタグ）"
        }
    }

    static let defaultOrder: [SidebarSection] = [.favorites, .tags, .locations]
}

/// サイドバーの「お気に入り」と「場所」。全ウィンドウで共有する。
@Observable
final class SidebarStore {
    static let shared = SidebarStore()

    private static let favoritesKey = "sidebarFavorites"
    private static let sectionsKey = "sidebarSections"
    private static let hiddenSectionsKey = "sidebarHiddenSections"

    /// セクションの順番（タグのセクションも含む）と、隠しているセクション
    private(set) var sections: [SidebarSection] = SidebarSection.defaultOrder
    private(set) var hiddenSections: Set<String> = []

    private(set) var favorites: [SidebarItem] = []
    private(set) var volumes: [SidebarItem] = []

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// 設定の保存先（テストでは別の場所を渡す）
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        favorites = Self.loadFavorites(from: defaults)
        loadSections()
        refreshVolumes()

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshVolumes() }
            })
        }
    }

    // MARK: お気に入り

    func containsFavorite(_ url: URL) -> Bool {
        favorites.contains { $0.tagID == nil && $0.url.path == url.standardizedFileURL.path }
    }

    func containsFavoriteTag(_ id: UUID) -> Bool {
        favorites.contains { $0.tagID == id }
    }

    /// タグをお気に入りに入れる（フォルダと同じ並びに置き、順番も自由に変えられる）
    func addFavoriteTag(_ id: UUID, at index: Int? = nil) {
        // すでにあれば、指定の位置へ動かすだけ（ドラッグ＆ドロップ）
        if let existing = favorites.firstIndex(where: { $0.tagID == id }) {
            guard let index else { return }
            let item = favorites.remove(at: existing)
            favorites.insert(item, at: min(index > existing ? index - 1 : index, favorites.count))
            saveFavorites()
            return
        }
        guard let tag = TagStore.shared.tag(id: id) else { return }
        let item = SidebarItem(url: TagLocation.url(for: id), name: tag.name, symbol: "tag.fill", tagID: id)
        favorites.insert(item, at: min(index ?? favorites.count, favorites.count))
        saveFavorites()
    }

    func removeFavoriteTag(_ id: UUID) {
        favorites.removeAll { $0.tagID == id }
        saveFavorites()
    }

    /// お気に入りに入れる（フォルダだけ）。index を指定すると、その位置に入れる（ドラッグ＆ドロップ用）
    func addFavorite(_ url: URL, at index: Int? = nil) {
        let url = url.standardizedFileURL
        guard FileTransfer.isDirectory(url) else { return }
        if let existing = favorites.firstIndex(where: { $0.url.path == url.path }) {
            // すでにあれば、指定の位置へ動かすだけ
            guard let index else { return }
            let item = favorites.remove(at: existing)
            favorites.insert(item, at: min(index > existing ? index - 1 : index, favorites.count))
        } else {
            let item = Self.makeFavorite(url)
            favorites.insert(item, at: min(index ?? favorites.count, favorites.count))
        }
        saveFavorites()
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
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        favorites[index].customName = trimmed.isEmpty ? nil : trimmed
        let fallback = favorites[index].tagID.flatMap { TagStore.shared.tag(id: $0)?.name } ?? FileManager.default.displayName(atPath: url.path)
        favorites[index].name = favorites[index].customName ?? fallback
        saveFavorites()
    }

    /// 移動・削除されたフォルダの印を付け直す
    func refreshMissing() {
        for index in favorites.indices {
            if let tagID = favorites[index].tagID {
                favorites[index].isMissing = TagStore.shared.tag(id: tagID) == nil
            } else {
                favorites[index].isMissing = !FileManager.default.fileExists(atPath: favorites[index].url.path)
            }
        }
    }

    func removeFavorite(_ url: URL) {
        favorites.removeAll { $0.url.path == url.path }
        saveFavorites()
    }

    func moveFavorites(from source: IndexSet, to destination: Int) {
        favorites.move(fromOffsets: source, toOffset: destination)
        saveFavorites()
    }

    /// 保存の形: [{"path": …, "name": …（表示名を変えたときだけ）}]。タグは {"tag": ID}
    private func saveFavorites() {
        let records: [[String: String]] = favorites.map { item in
            var record = item.tagID.map { ["tag": $0.uuidString] } ?? ["path": item.url.path]
            if let customName = item.customName { record["name"] = customName }
            return record
        }
        defaults.set(records, forKey: Self.favoritesKey)
    }

    private static func loadFavorites(from defaults: UserDefaults) -> [SidebarItem] {
        var records: [[String: String]]
        if let saved = defaults.array(forKey: favoritesKey) as? [[String: String]] {
            records = saved
        } else if let paths = defaults.stringArray(forKey: favoritesKey) {
            // 以前はパスの配列で保存していた
            records = paths.map { ["path": $0] }
        } else {
            records = defaultFavoritePaths().map { ["path": $0] }
        }
        return records.compactMap { record in
            var item: SidebarItem
            if let tag = record["tag"], let id = UUID(uuidString: tag) {
                let name = TagStore.shared.tag(id: id)?.name ?? "（削除されたタグ）"
                item = SidebarItem(url: TagLocation.url(for: id), name: name, symbol: "tag.fill", isMissing: TagStore.shared.tag(id: id) == nil, tagID: id)
            } else if let path = record["path"] {
                item = makeFavorite(URL(fileURLWithPath: path))
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

    /// 表示するセクション（隠したもの・削除されたタグのものは除く）
    var visibleSections: [SidebarSection] {
        sections.filter { section in
            guard !hiddenSections.contains(section.id) else { return false }
            if case .tag(let id) = section { return TagStore.shared.tag(id: id) != nil }
            return true
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

    /// ドラッグ＆ドロップ: お気に入りの項目を index の位置へ動かす
    func moveFavorite(id: String, to index: Int) {
        guard let from = favorites.firstIndex(where: { $0.id == id }) else { return }
        moveFavorites(from: IndexSet(integer: from), to: index)
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
        sections = SidebarSection.defaultOrder
        hiddenSections = []
        saveSections()
    }

    private func loadSections() {
        if let ids = defaults.stringArray(forKey: Self.sectionsKey) {
            var loaded = ids.compactMap(SidebarSection.init(id:))
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

    private static func makeFavorite(_ url: URL) -> SidebarItem {
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
        return "folder"
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
