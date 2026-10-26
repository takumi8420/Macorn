import AppKit
import Observation

struct SidebarItem: Identifiable, Hashable {
    var url: URL
    var name: String
    var symbol: String
    var isEjectable = false

    var id: String { url.path }
}

/// サイドバーの「よく使う項目」と「場所」。全ウィンドウで共有する。
@Observable
final class SidebarStore {
    static let shared = SidebarStore()

    private static let favoritesKey = "sidebarFavorites"

    private(set) var favorites: [SidebarItem] = []
    private(set) var volumes: [SidebarItem] = []

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.favoritesKey) ?? Self.defaultFavoritePaths()
        favorites = paths.map { Self.makeFavorite(URL(fileURLWithPath: $0)) }
        refreshVolumes()

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshVolumes() }
            })
        }
    }

    // MARK: よく使う項目

    func containsFavorite(_ url: URL) -> Bool {
        favorites.contains { $0.url.path == url.standardizedFileURL.path }
    }

    func addFavorite(_ url: URL) {
        let url = url.standardizedFileURL
        guard !containsFavorite(url) else { return }
        favorites.append(Self.makeFavorite(url))
        saveFavorites()
    }

    func removeFavorite(_ url: URL) {
        favorites.removeAll { $0.url.path == url.path }
        saveFavorites()
    }

    func moveFavorites(from source: IndexSet, to destination: Int) {
        favorites.move(fromOffsets: source, toOffset: destination)
        saveFavorites()
    }

    private func saveFavorites() {
        UserDefaults.standard.set(favorites.map(\.url.path), forKey: Self.favoritesKey)
    }

    private static func defaultFavoritePaths() -> [String] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let directories: [FileManager.SearchPathDirectory] = [.desktopDirectory, .documentDirectory, .downloadsDirectory]
        let others = directories.compactMap { fm.urls(for: $0, in: .userDomainMask).first }
        return ([home] + others + [URL(fileURLWithPath: "/Applications")]).map(\.path)
    }

    private static func makeFavorite(_ url: URL) -> SidebarItem {
        SidebarItem(url: url, name: FileManager.default.displayName(atPath: url.path), symbol: symbol(for: url))
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
