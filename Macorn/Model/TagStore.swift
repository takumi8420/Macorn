import AppKit
import Observation

/// Macorn だけで使うタグ（要件 S-07 を独自タグとして実装）。
/// 名前は自由で、「仕事/案件A」のように / で区切ると階層になる。色も自由に決められる。
nonisolated struct Tag: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    /// 「仕事/案件A」のような、階層を含む名前
    var name: String
    /// 色（#RRGGBB）
    var color: String

    /// 階層の一番下の名前（「仕事/案件A」なら「案件A」）
    var leafName: String { name.split(separator: "/").last.map(String.init) ?? name }
    /// 階層の深さ（「仕事」なら 0、「仕事/案件A」なら 1）
    var depth: Int { max(0, name.split(separator: "/").count - 1) }
    var parentName: String? {
        let parts = name.split(separator: "/")
        return parts.count > 1 ? parts.dropLast().joined(separator: "/") : nil
    }

    /// name 自身か、その子孫か
    func isSelfOrDescendant(of other: String) -> Bool {
        name == other || name.hasPrefix(other + "/")
    }
}

/// タグを付けた項目。パスに加えてブックマークを持ち、Finder などで移動・改名されても追いかける。
nonisolated struct TaggedItem: Codable, Hashable, Sendable {
    var path: String
    var bookmark: Data?
    var tagIDs: Set<UUID>
}

nonisolated struct TagLibrary: Codable, Equatable, Sendable {
    var tags: [Tag] = []
    var items: [TaggedItem] = []
}

extension Notification.Name {
    /// タグの定義や、項目へのタグ付けが変わったとき
    static let macornTagsChanged = Notification.Name("macornTagsChanged")
}

/// タグの保存と操作。保存先は ~/Library/Application Support/Macorn/tags.json。
@Observable
final class TagStore {
    static let shared = TagStore(fileURL: defaultURL)

    /// 新しいタグに順番に割り当てる色（赤・橙・黄・緑・青・紫・桃・灰）
    static let palette = ["#FF5F57", "#FF9F0A", "#FFD60A", "#32D74B", "#0A84FF", "#BF5AF2", "#FF6FAE", "#8E8E93"]

    /// 最初から用意している「お気に入り」のタグ。ふつうのタグと同じように付け外しできるが、名前の変更・削除・移動はできない
    static let favoritesID = UUID(uuidString: "00000000-0000-0000-0000-0000000FA001")!
    static let favoritesName = "お気に入り"
    static let favoritesColor = "#FFD60A"

    /// 名前の変更・削除・ほかのタグの下への移動ができないタグか
    static func isBuiltIn(_ id: UUID) -> Bool { id == favoritesID }

    private(set) var tags: [Tag] = []
    /// 読み込んだときに「お気に入り」のタグが無く、新しく作ったか（お気に入りの引き継ぎに使う）
    @ObservationIgnored private var createdFavoritesTag = false
    /// パス → タグを付けた項目。サイドバーの件数などが付け外しに合わせて変わるよう、変更を画面に知らせる
    private var itemsByPath: [String: TaggedItem] = [:]
    @ObservationIgnored private let fileURL: URL

    private static var defaultURL: URL {
        if let path = ProcessInfo.processInfo.environment["MACORN_TAGS_PATH"] {
            return URL(fileURLWithPath: path)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Macorn/tags.json")
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let library = try? JSONDecoder().decode(TagLibrary.self, from: data) {
            tags = library.tags
            itemsByPath = Dictionary(library.items.map { (Self.key($0.path), $0) }, uniquingKeysWith: { first, _ in first })
        }
        ensureFavoritesTag()
    }

    /// 「お気に入り」のタグを用意する。同じ名前のタグを自分で作っていたら、それを「お気に入り」のタグにする
    private func ensureFavoritesTag() {
        guard tag(id: Self.favoritesID) == nil else { return }
        if let index = tags.firstIndex(where: { $0.name == Self.favoritesName }) {
            let oldID = tags[index].id
            tags[index].id = Self.favoritesID
            for path in itemsByPath.keys where itemsByPath[path]?.tagIDs.remove(oldID) != nil {
                itemsByPath[path]?.tagIDs.insert(Self.favoritesID)
            }
        } else {
            tags.append(Tag(id: Self.favoritesID, name: Self.favoritesName, color: Self.favoritesColor))
            createdFavoritesTag = true
        }
        save(notify: false)
    }

    /// 「お気に入り」のタグを新しく作ったか。一度だけ true を返す
    func consumeCreatedFavoritesTag() -> Bool {
        defer { createdFavoritesTag = false }
        return createdFavoritesTag
    }

    // MARK: - タグの定義

    /// 名前の順（階層は親の直後に子が来る）
    var sortedTags: [Tag] {
        tags.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func tag(id: UUID) -> Tag? { tags.first { $0.id == id } }
    func tag(named name: String) -> Tag? { tags.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } }

    func children(of tag: Tag) -> [Tag] {
        sortedTags.filter { $0.parentName == tag.name }
    }

    var rootTags: [Tag] { sortedTags.filter { $0.parentName == nil } }

    /// タグ名をそろえる（前後の空白と、/ の前後の空白・空の階層を取り除く）
    static func normalize(_ name: String) -> String {
        name.split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "/")
    }

    /// タグを作る。同じ名前があればそれを返す。階層の親が無ければ親も作る。
    @discardableResult
    func createTag(named rawName: String, color: String? = nil) -> Tag? {
        let name = Self.normalize(rawName)
        guard !name.isEmpty else { return nil }
        if let existing = tag(named: name) { return existing }
        if let parent = Tag(id: UUID(), name: name, color: "").parentName, tag(named: parent) == nil {
            createTag(named: parent, color: color)
        }
        let tag = Tag(id: UUID(), name: name, color: color ?? nextColor())
        tags.append(tag)
        save()
        return tag
    }

    private func nextColor() -> String {
        Self.palette[tags.count % Self.palette.count]
    }

    /// 名前を変える。子のタグの名前もいっしょに変える（「仕事」→「業務」なら「仕事/案件A」→「業務/案件A」）
    /// 同じ名前のタグが別にあれば false。
    @discardableResult
    func renameTag(_ id: UUID, to rawName: String) -> Bool {
        let newName = Self.normalize(rawName)
        guard !newName.isEmpty, !Self.isBuiltIn(id), let old = tag(id: id) else { return false }
        if let other = tag(named: newName), other.id != id { return false }
        guard !newName.hasPrefix(old.name + "/") else { return false }
        for index in tags.indices where tags[index].isSelfOrDescendant(of: old.name) {
            tags[index].name = newName + tags[index].name.dropFirst(old.name.count)
        }
        if let parent = Tag(id: id, name: newName, color: "").parentName, tag(named: parent) == nil {
            createTag(named: parent)
        }
        save()
        return true
    }

    /// 親のタグを変えられるか（自分や自分の子孫の下には入れない。同じ名前のタグが先にあるときも不可）
    func canMoveTag(_ id: UUID, under parentID: UUID?) -> Bool {
        guard !Self.isBuiltIn(id), let tag = tag(id: id) else { return false }
        var parentName: String?
        if let parentID {
            guard let parent = self.tag(id: parentID), !parent.isSelfOrDescendant(of: tag.name) else { return false }
            parentName = parent.name
        }
        guard tag.parentName != parentName else { return false }
        let newName = parentName.map { $0 + "/" + tag.leafName } ?? tag.leafName
        return self.tag(named: newName) == nil
    }

    /// 親のタグを変える（nil ならいちばん上へ）。子のタグもいっしょに移る。付けた項目はそのまま
    @discardableResult
    func moveTag(_ id: UUID, under parentID: UUID?) -> Bool {
        guard canMoveTag(id, under: parentID), let tag = tag(id: id) else { return false }
        let parentName = parentID.flatMap { self.tag(id: $0)?.name }
        return renameTag(id, to: parentName.map { $0 + "/" + tag.leafName } ?? tag.leafName)
    }

    func setColor(_ id: UUID, to color: String) {
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return }
        tags[index].color = color
        save()
    }

    /// タグを削除する。子のタグもいっしょに削除し、項目からも外す。
    func deleteTag(_ id: UUID) {
        guard !Self.isBuiltIn(id), let target = tag(id: id) else { return }
        let removed = Set(tags.filter { $0.isSelfOrDescendant(of: target.name) }.map(\.id))
        tags.removeAll { removed.contains($0.id) }
        for path in itemsByPath.keys {
            itemsByPath[path]?.tagIDs.subtract(removed)
            if itemsByPath[path]?.tagIDs.isEmpty == true { itemsByPath[path] = nil }
        }
        save()
    }

    // MARK: - 項目へのタグ付け

    func tags(for url: URL) -> [Tag] {
        guard let item = itemsByPath[Self.key(url)] else { return [] }
        return sortedTags.filter { item.tagIDs.contains($0.id) }
    }

    func hasTag(_ id: UUID, on url: URL) -> Bool {
        itemsByPath[Self.key(url)]?.tagIDs.contains(id) ?? false
    }

    func assign(_ id: UUID, to urls: [URL]) {
        guard tag(id: id) != nil else { return }
        for url in urls {
            let path = Self.key(url)
            var item = itemsByPath[path] ?? TaggedItem(path: path, bookmark: Self.bookmark(for: url), tagIDs: [])
            item.tagIDs.insert(id)
            itemsByPath[path] = item
        }
        save()
    }

    func unassign(_ id: UUID, from urls: [URL]) {
        for url in urls {
            let path = Self.key(url)
            itemsByPath[path]?.tagIDs.remove(id)
            if itemsByPath[path]?.tagIDs.isEmpty == true { itemsByPath[path] = nil }
        }
        save()
    }

    /// すべての項目に付いていれば外し、そうでなければ全部に付ける
    func toggle(_ id: UUID, on urls: [URL]) {
        if urls.allSatisfy({ hasTag(id, on: $0) }) {
            unassign(id, from: urls)
        } else {
            assign(id, to: urls)
        }
    }

    /// タグが付いている項目。子のタグが付いている項目も含める。見つからない項目は除く。
    func urls(taggedWith id: UUID, includingDescendants: Bool = true) -> [URL] {
        guard let target = tag(id: id) else { return [] }
        let ids = includingDescendants ? Set(tags.filter { $0.isSelfOrDescendant(of: target.name) }.map(\.id)) : [id]
        return itemsByPath.values
            .filter { !$0.tagIDs.isDisjoint(with: ids) }
            .map { URL(fileURLWithPath: $0.path) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    func count(for id: UUID) -> Int { urls(taggedWith: id).count }

    /// タグ別に並べるときの基準（付いているタグのうち、名前の順で最初のタグの名前）
    func sortKey(for url: URL) -> String? {
        tags(for: url).first?.name
    }

    /// フォルダのアイコンを塗る色（付いているタグのうち、名前の順で最初のもの）。
    /// 設定で色分けを切っているとき、またはタグが無いときは nil
    func folderColor(for url: URL) -> String? {
        guard Preferences.colorFoldersByTag else { return nil }
        // 「お気に入り」はよく使うフォルダの多くに付くので、色分けには使わない
        return tags(for: url).first { $0.id != Self.favoritesID }?.color
    }

    // MARK: - 移動・名前の変更への追従

    /// Macorn の中で項目を移動・改名したときに呼ぶ。中の項目のパスもいっしょに直す。
    func itemMoved(from old: URL, to new: URL) {
        let oldPath = Self.key(old)
        let newPath = Self.key(new)
        guard oldPath != newPath else { return }
        var changed = false
        for (path, item) in itemsByPath where path == oldPath || path.hasPrefix(oldPath + "/") {
            let moved = newPath + path.dropFirst(oldPath.count)
            itemsByPath[path] = nil
            itemsByPath[moved] = TaggedItem(path: moved, bookmark: Self.bookmark(for: URL(fileURLWithPath: moved)) ?? item.bookmark, tagIDs: item.tagIDs)
            changed = true
        }
        if changed { save() }
    }

    /// Finder などで移動・改名された項目を、ブックマークから探し直してパスを直す。
    func resolveMovedItems() async {
        let items = Array(itemsByPath.values)
        let moves = await Task.detached(priority: .utility) { () -> [(String, String)] in
            items.compactMap { item in
                guard !FileManager.default.fileExists(atPath: item.path), let bookmark = item.bookmark else { return nil }
                var stale = false
                guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &stale),
                      FileManager.default.fileExists(atPath: url.path) else { return nil }
                return (item.path, Self.key(url))
            }
        }.value
        for (old, new) in moves {
            itemMoved(from: URL(fileURLWithPath: old), to: URL(fileURLWithPath: new))
        }
    }

    /// 項目を引くときのキー。日本語の名前は「ダ」が「タ＋゛」に分かれて届くことがあるので、合成した形にそろえる
    nonisolated static func key(_ url: URL) -> String { key(url.standardizedFileURL.path) }
    nonisolated static func key(_ path: String) -> String { path.precomposedStringWithCanonicalMapping }

    private static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    // MARK: - 保存

    var library: TagLibrary {
        TagLibrary(tags: tags, items: Array(itemsByPath.values).sorted { $0.path < $1.path })
    }

    private func save(notify: Bool = true) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(library).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("タグを保存できませんでした: \(error.localizedDescription)")
        }
        if notify { NotificationCenter.default.post(name: .macornTagsChanged, object: self) }
    }
}

extension NSColor {
    /// #RRGGBB から作る。読めなければ灰色
    convenience init(hex: String) {
        let text = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt32(text, radix: 16) ?? 0x8E8E93
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    var hexString: String {
        let color = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X", Int(round(color.redComponent * 255)), Int(round(color.greenComponent * 255)), Int(round(color.blueComponent * 255)))
    }
}
