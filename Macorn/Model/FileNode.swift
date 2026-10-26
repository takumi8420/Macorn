import AppKit

/// リスト表示の1行。フォルダを展開したときの中身も持つ。
/// NSOutlineView は行をオブジェクトの同一性で覚えるため、再読み込みしても同じパスなら同じオブジェクトを使い回す。
final class FileNode {
    private(set) var entry: FileEntry
    weak var parent: FileNode?
    /// nil = まだ読み込んでいない
    var children: [FileNode]?

    private var cachedIcon: NSImage?
    private var cachedTintedIcon: (color: String, image: NSImage)?

    init(entry: FileEntry, parent: FileNode? = nil) {
        self.entry = entry
        self.parent = parent
    }

    var url: URL { entry.url }
    var path: String { entry.path }

    var icon: NSImage {
        if let cachedIcon { return cachedIcon }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 16, height: 16)
        cachedIcon = image
        return image
    }

    /// タグの色で塗ったアイコン（フォルダの色分け）。色が無ければふつうのアイコン
    func icon(tintedWith color: String?) -> NSImage {
        guard let color else { return icon }
        if let cachedTintedIcon, cachedTintedIcon.color == color { return cachedTintedIcon.image }
        let image = Self.tint(icon, with: NSColor(hex: color))
        cachedTintedIcon = (color, image)
        return image
    }

    /// アイコンの陰影は残したまま、色だけを置き換える（Finder の色付きフォルダと同じ見え方）
    static func tint(_ icon: NSImage, with color: NSColor) -> NSImage {
        let size = icon.size
        return NSImage(size: size, flipped: false) { rect in
            icon.draw(in: rect)
            color.setFill()
            rect.fill(using: .color)
            // 塗った色を、元のアイコンの形で切り抜く
            icon.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
    }

    /// 裏で計算したフォルダの合計サイズを入れる
    func setFolderSize(_ size: Int64) {
        entry.size = size
    }

    func update(_ entry: FileEntry) {
        if entry.isFolder != self.entry.isFolder || entry.isPackage != self.entry.isPackage {
            cachedIcon = nil
        }
        self.entry = entry
    }

    /// 読み込んだ中身を反映する。同じパスの子は使い回す。
    func setChildren(_ entries: [FileEntry], sort: FileSort) {
        var existing: [String: FileNode] = [:]
        for child in children ?? [] {
            existing[child.path] = child
        }
        // 計算済みのフォルダサイズがあれば入れておく（並べ替えにも使う）
        let entries = entries.map { entry in
            guard entry.isFolder || entry.isPackage, entry.size == nil, Preferences.calculateFolderSizes,
                  let size = FolderSizeService.shared.cachedSize(for: entry.url) else { return entry }
            var sized = entry
            sized.size = size
            return sized
        }
        children = sort.sorted(entries).map { entry in
            if let node = existing[entry.path] {
                node.update(entry)
                return node
            }
            return FileNode(entry: entry, parent: self)
        }
    }

    /// 読み込み済みの子孫も含めて並べ替える。
    func resort(_ sort: FileSort) {
        guard var children else { return }
        children.sort { sort.areInIncreasingOrder($0.entry, $1.entry) }
        self.children = children
        children.forEach { $0.resort(sort) }
    }

    /// 中身を読み込み済みのフォルダ（自分を含む）。
    func loadedFolders() -> [FileNode] {
        guard let children else { return [] }
        return [self] + children.flatMap { $0.loadedFolders() }
    }

    var treeRoot: FileNode {
        var node = self
        while let parent = node.parent { node = parent }
        return node
    }
}
