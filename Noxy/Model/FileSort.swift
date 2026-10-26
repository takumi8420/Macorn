import Foundation

nonisolated enum FileSortKey: String, CaseIterable, Sendable {
    case name
    case dateModified
    case size
    case kind
}

/// 並び順。アプリ全体で1つの設定を共有する（要件 V-08）。
nonisolated struct FileSort: Equatable, Sendable {
    var key: FileSortKey = .name
    var ascending = true

    var descriptor: NSSortDescriptor {
        NSSortDescriptor(key: key.rawValue, ascending: ascending)
    }

    init(key: FileSortKey = .name, ascending: Bool = true) {
        self.key = key
        self.ascending = ascending
    }

    init?(descriptor: NSSortDescriptor) {
        guard let rawKey = descriptor.key, let key = FileSortKey(rawValue: rawKey) else { return nil }
        self.init(key: key, ascending: descriptor.ascending)
    }

    func sorted(_ entries: [FileEntry]) -> [FileEntry] {
        entries.sorted(by: areInIncreasingOrder)
    }

    func areInIncreasingOrder(_ a: FileEntry, _ b: FileEntry) -> Bool {
        let result = compare(a, b)
        if result == .orderedSame {
            // 同じ値どうしは、いつも名前の昇順で並べる
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        return ascending ? result == .orderedAscending : result == .orderedDescending
    }

    private func compare(_ a: FileEntry, _ b: FileEntry) -> ComparisonResult {
        switch key {
        case .name:
            return a.name.localizedStandardCompare(b.name)
        case .dateModified:
            return Self.compare(a.dateModified ?? .distantPast, b.dateModified ?? .distantPast)
        case .size:
            // フォルダ（サイズなし）はファイルより小さいものとして扱う
            return Self.compare(a.size ?? -1, b.size ?? -1)
        case .kind:
            return a.kind.localizedStandardCompare(b.kind)
        }
    }

    private static func compare<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
    }
}
