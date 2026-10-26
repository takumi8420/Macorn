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

    var id: String { url.path }
}

/// サイドバーの「お気に入り」と「場所」。全ウィンドウで共有する。
@Observable
final class SidebarStore {
    static let shared = SidebarStore()

    private static let favoritesKey = "sidebarFavorites"

    private(set) var favorites: [SidebarItem] = []
    private(set) var volumes: [SidebarItem] = []

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        favorites = Self.loadFavorites()
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
        favorites.contains { $0.url.path == url.standardizedFileURL.path }
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
        favorites[index].name = favorites[index].customName ?? FileManager.default.displayName(atPath: url.path)
        saveFavorites()
    }

    /// 移動・削除されたフォルダの印を付け直す
    func refreshMissing() {
        for index in favorites.indices {
            favorites[index].isMissing = !FileManager.default.fileExists(atPath: favorites[index].url.path)
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

    /// 保存の形: [{"path": …, "name": …（表示名を変えたときだけ）}]
    private func saveFavorites() {
        let records: [[String: String]] = favorites.map { item in
            var record = ["path": item.url.path]
            if let customName = item.customName { record["name"] = customName }
            return record
        }
        UserDefaults.standard.set(records, forKey: Self.favoritesKey)
    }

    private static func loadFavorites() -> [SidebarItem] {
        let defaults = UserDefaults.standard
        var records: [[String: String]]
        if let saved = defaults.array(forKey: favoritesKey) as? [[String: String]] {
            records = saved
        } else if let paths = defaults.stringArray(forKey: favoritesKey) {
            // 以前はパスの配列で保存していた
            records = paths.map { ["path": $0] }
        } else {
            records = defaultFavoritePaths().map { ["path": $0] }
        }
        records = records.filter { $0["path"] != nil }
        return records.map { record in
            var item = makeFavorite(URL(fileURLWithPath: record["path"]!))
            if let name = record["name"] {
                item.customName = name
                item.name = name
            }
            return item
        }
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
