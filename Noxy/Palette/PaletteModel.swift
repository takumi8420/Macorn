import AppKit
import Observation

/// パレットの1行。
struct PaletteItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case command(Selector)
        case folder(URL)
        case file(URL)
        /// パス入力（「/」「~」で始まる入力）の移動先
        case path(URL)
    }

    enum Icon: Equatable {
        case symbol(String)
        case file(String)
    }

    var id: String
    var kind: Kind
    var title: String
    var subtitle: String
    /// 右端に出すもの（ショートカットや種類）
    var detail: String
    var icon: Icon
    /// title の中で強調する文字の位置
    var highlights: [Int] = []
    var score: Double = 0

    var url: URL? {
        switch kind {
        case .folder(let url), .file(let url), .path(let url): url
        case .command: nil
        }
    }
}

/// 入力の頭文字で検索対象を切り替える（要件 5.2）。
enum PaletteMode: Equatable {
    case all
    case commands
    case path
    case files
    case sidebar

    static func detect(_ query: String) -> PaletteMode {
        switch query.first {
        case ">": .commands
        case "/", "~": .path
        case "@": .files
        case "#": .sidebar
        default: .all
        }
    }

    /// 頭文字を除いた検索語
    static func term(_ query: String) -> String {
        switch detect(query) {
        case .commands, .files, .sidebar: String(query.dropFirst()).trimmingCharacters(in: .whitespaces)
        case .path: query
        case .all: query.trimmingCharacters(in: .whitespaces)
        }
    }
}

/// コマンドの使用回数（よく使うものを上に出す。要件 C-05）
enum CommandUsage {
    private static let key = "paletteCommandUsage"

    static func record(_ action: Selector) {
        var usage = all
        let name = NSStringFromSelector(action)
        let count = (usage[name]?.first ?? 0) + 1
        usage[name] = [count, Date().timeIntervalSince1970]
        UserDefaults.standard.set(usage, forKey: key)
    }

    static var all: [String: [Double]] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: [Double]] ?? [:]
    }
}

@Observable
final class PaletteModel {
    static let maxResults = 50
    static let maxIndexedFiles = 10_000

    var query = "" {
        didSet { search() }
    }
    private(set) var items: [PaletteItem] = []
    var selectedIndex = 0
    private(set) var isIndexingFiles = false

    @ObservationIgnored let commands: [PaletteCommand]
    @ObservationIgnored let currentFolder: URL
    @ObservationIgnored private let history: FolderHistory
    @ObservationIgnored private let sidebarItems: [SidebarItem]
    @ObservationIgnored private var currentChildren: [FileEntry] = []
    @ObservationIgnored private var fileIndex: [URL]?
    @ObservationIgnored private let commandAliases: [String: [String]]

    init(commands: [PaletteCommand], currentFolder: URL, history: FolderHistory = .shared, sidebarItems: [SidebarItem]) {
        self.commands = commands
        self.currentFolder = currentFolder
        self.history = history
        self.sidebarItems = sidebarItems
        var aliases: [String: [String]] = [:]
        for command in commands { aliases[command.id] = command.searchAliases }
        commandAliases = aliases
        currentChildren = (try? DirectoryReader.read(currentFolder, includeHidden: Preferences.showHiddenFiles)) ?? []
        search()
    }

    var mode: PaletteMode { PaletteMode.detect(query) }

    var selectedItem: PaletteItem? {
        items.indices.contains(selectedIndex) ? items[selectedIndex] : nil
    }

    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), items.count - 1)
    }

    // MARK: - 検索

    func search() {
        let term = PaletteMode.term(query)
        var results: [PaletteItem]
        switch mode {
        case .commands:
            results = commandItems(term)
        case .path:
            results = pathItems(query)
        case .files:
            results = fileItems(term)
        case .sidebar:
            results = sidebarResults(term)
        case .all:
            results = term.isEmpty ? recentItems() : commandItems(term) + folderItems(term) + sidebarResults(term) + childItems(term)
        }
        if mode != .path {
            results.sort { $0.score > $1.score }
            // 同じフォルダが「履歴」と「サイドバー」の両方に出ないようにする
            var seen = Set<String>()
            results = results.filter { seen.insert($0.id).inserted }
        }
        items = Array(results.prefix(Self.maxResults))
        selectedIndex = 0
    }

    /// 何も入力していないとき: 最近使ったコマンドと、よく開くフォルダ（要件 C-06）
    private func recentItems() -> [PaletteItem] {
        let usage = CommandUsage.all
        let recentCommands = commands
            .filter { usage[NSStringFromSelector($0.action)] != nil }
            .sorted { (usage[NSStringFromSelector($0.action)]?.last ?? 0) > (usage[NSStringFromSelector($1.action)]?.last ?? 0) }
            .prefix(5)
            .enumerated()
            .map { index, command in
                var item = makeItem(command)
                item.score = 1_000 - Double(index)
                return item
            }
        let now = Date()
        let folders = history.entries()
            .filter { $0.path != currentFolder.path }
            .sorted { $0.frecency(now: now) > $1.frecency(now: now) }
            .prefix(15)
            .enumerated()
            .map { index, entry in
                var item = folderItem(URL(fileURLWithPath: entry.path), detail: "履歴")
                item.score = 500 - Double(index)
                return item
            }
        return Array(recentCommands) + folders
    }

    private func commandItems(_ term: String) -> [PaletteItem] {
        let usage = CommandUsage.all
        return commands.compactMap { command in
            guard var item = match(term, title: command.title, aliases: [command.menuPath + command.title] + command.searchAliases, base: makeItem(command)) else {
                return nil
            }
            let count = usage[NSStringFromSelector(command.action)]?.first ?? 0
            item.score += 4 * log2(1 + count) + 5
            return item
        }
    }

    private func folderItems(_ term: String) -> [PaletteItem] {
        let now = Date()
        return history.entries().compactMap { entry in
            let url = URL(fileURLWithPath: entry.path)
            let name = url.lastPathComponent
            let display = PathCompletion.abbreviate(entry.path)
            // フォルダ名での一致を、パス全体での一致より優先する（要件 C-11）
            var best: FuzzyMatch?
            var onName = false
            if let nameMatch = FuzzyMatcher.match(term, in: name) {
                best = FuzzyMatch(score: nameMatch.score + 20, positions: nameMatch.positions)
                onName = true
            }
            if let pathMatch = FuzzyMatcher.match(term, in: display), pathMatch.score > (best?.score ?? .min) {
                best = pathMatch
                onName = false
            }
            guard let best else { return nil }
            var item = folderItem(url, detail: "履歴")
            item.highlights = onName ? best.positions : []
            item.score = Double(best.score) + 8 * log2(1 + entry.frecency(now: now))
            return item
        }
    }

    private func sidebarResults(_ term: String) -> [PaletteItem] {
        sidebarItems.compactMap { sidebar in
            var base = folderItem(sidebar.url, detail: "サイドバー")
            base.title = sidebar.name
            base.icon = .symbol(sidebar.symbol)
            guard var item = match(term, title: sidebar.name, aliases: [sidebar.url.lastPathComponent, Romaji.transcribe(sidebar.name)], base: base) else {
                return nil
            }
            item.score += 6
            return item
        }
    }

    /// 表示中のフォルダの中身（「すべて」のときに一緒に探す）
    private func childItems(_ term: String) -> [PaletteItem] {
        currentChildren.compactMap { entry in
            let base = entry.isFolder ? folderItem(entry.url, detail: "このフォルダ") : fileItem(entry.url, relativeTo: currentFolder)
            return match(term, title: entry.name, aliases: [], base: base)
        }
    }

    // MARK: - 「@」: 表示中のフォルダ以下のファイル

    private func fileItems(_ term: String) -> [PaletteItem] {
        guard let fileIndex else {
            startIndexingFiles()
            return []
        }
        // 列挙した結果は /private/tmp のように実体のパスで返ることがあるので、どちらでも切り出せるようにする
        let bases = [currentFolder.path, FileBrowserViewController.realPath(currentFolder.path)].map { $0 + "/" }
        return fileIndex.compactMap { url in
            let path = url.path
            guard let base = bases.first(where: { path.hasPrefix($0) }) else { return nil }
            let relative = String(path.dropFirst(base.count))
            let name = url.lastPathComponent
            var best = FuzzyMatcher.match(term, in: relative)
            if let nameMatch = FuzzyMatcher.match(term, in: name) {
                // ファイル名での一致を優先する。強調はファイル名の位置を相対パスの位置に直す
                let offset = relative.count - name.count
                let shifted = FuzzyMatch(score: nameMatch.score + 15, positions: nameMatch.positions.map { $0 + offset })
                if shifted.score > (best?.score ?? .min) { best = shifted }
            }
            guard let best else { return nil }
            var item = fileItem(url, relativeTo: currentFolder)
            item.title = relative
            item.highlights = best.positions
            item.score = Double(best.score)
            return item
        }
    }

    private func startIndexingFiles() {
        guard !isIndexingFiles else { return }
        isIndexingFiles = true
        let folder = currentFolder
        let includeHidden = Preferences.showHiddenFiles
        let limit = Self.maxIndexedFiles
        Task {
            let urls = await Task.detached(priority: .userInitiated) {
                Self.indexFiles(in: folder, includeHidden: includeHidden, limit: limit)
            }.value
            fileIndex = urls
            isIndexingFiles = false
            if mode == .files { search() }
        }
    }

    /// フォルダ以下の項目を集める。.git・node_modules とパッケージの中身は除く。
    nonisolated static func indexFiles(in folder: URL, includeHidden: Bool, limit: Int) -> [URL] {
        let skipped: Set<String> = [".git", "node_modules", ".build", "DerivedData", "Pods", ".venv"]
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !includeHidden { options.insert(.skipsHiddenFiles) }
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: options, errorHandler: { _, _ in true }
        ) else { return [] }
        var result: [URL] = []
        while let url = enumerator.nextObject() as? URL, result.count < limit {
            if skipped.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            result.append(url)
        }
        return result
    }

    // MARK: - 「/」「~」: パス入力

    private func pathItems(_ query: String) -> [PaletteItem] {
        var results: [PaletteItem] = []
        if let target = PathCompletion.resolve(query, relativeTo: currentFolder) {
            var item = target.isDirectory ? folderItem(target.url, detail: "移動") : fileItem(target.url, relativeTo: target.url.deletingLastPathComponent())
            item.id = "path:" + target.url.path
            item.kind = .path(target.url)
            item.title = PathCompletion.abbreviate(target.url.path)
            results.append(item)
        }
        // 入力中の名前で始まるフォルダを候補に出す
        let directory: String
        let partial: String
        if let slash = query.lastIndex(of: "/") {
            directory = String(query[...slash])
            partial = String(query[query.index(after: slash)...])
        } else {
            directory = query == "~" ? "~/" : ""
            partial = ""
        }
        let directoryPath = PathCompletion.expand(directory, relativeTo: currentFolder)
        let children = (try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: directoryPath),
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: partial.hasPrefix(".") ? [] : [.skipsHiddenFiles]
        )) ?? []
        let folders = children
            .filter { child in
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                return values?.isDirectory == true && values?.isPackage != true
                    && child.lastPathComponent.lowercased().hasPrefix(partial.lowercased())
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .prefix(30)
        for folder in folders where folder.standardizedFileURL.path != results.first?.url?.standardizedFileURL.path {
            var item = folderItem(folder, detail: "")
            item.kind = .path(folder)
            item.title = directory + folder.lastPathComponent + "/"
            results.append(item)
        }
        return results
    }

    // MARK: - 行の組み立て

    private func match(_ term: String, title: String, aliases: [String], base: PaletteItem) -> PaletteItem? {
        var item = base
        if let titleMatch = FuzzyMatcher.match(term, in: title) {
            item.highlights = titleMatch.positions
            item.score = Double(titleMatch.score) + 10
            return item
        }
        let best = aliases.compactMap { FuzzyMatcher.match(term, in: $0) }.max { $0.score < $1.score }
        guard let best else { return nil }
        item.highlights = []
        item.score = Double(best.score)
        return item
    }

    private func makeItem(_ command: PaletteCommand) -> PaletteItem {
        PaletteItem(
            id: "command:" + command.id,
            kind: .command(command.action),
            title: command.title,
            subtitle: command.menuPath,
            detail: command.shortcut,
            icon: .symbol("command")
        )
    }

    private func folderItem(_ url: URL, detail: String) -> PaletteItem {
        PaletteItem(
            id: "folder:" + url.standardizedFileURL.path,
            kind: .folder(url),
            title: url.path == "/" ? "/" : url.lastPathComponent,
            subtitle: PathCompletion.abbreviate(url.deletingLastPathComponent().path),
            detail: detail,
            icon: .file(url.path)
        )
    }

    private func fileItem(_ url: URL, relativeTo folder: URL) -> PaletteItem {
        PaletteItem(
            id: "file:" + url.standardizedFileURL.path,
            kind: FileTransfer.isDirectory(url) && !(url.pathExtension == "app") ? .folder(url) : .file(url),
            title: url.lastPathComponent,
            subtitle: PathCompletion.abbreviate(url.deletingLastPathComponent().path),
            detail: "",
            icon: .file(url.path)
        )
    }
}
