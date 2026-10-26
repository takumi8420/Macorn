import Foundation
import SQLite3

/// 開いたフォルダの履歴（要件 C-10〜C-12）。zoxide と同じく「よく開く・最近開いた」ほど点数を高くする。
/// 保存先は ~/Library/Application Support/noxy/history.sqlite。
final class FolderHistory {
    struct Entry: Equatable {
        var path: String
        var rank: Double
        var lastAccess: Date

        /// 最近開いたものほど重くする（zoxide の計算と同じ）
        func frecency(now: Date = Date()) -> Double {
            let age = now.timeIntervalSince(lastAccess)
            let weight: Double = switch age {
            case ..<3_600: 4
            case ..<86_400: 2
            case ..<604_800: 0.5
            default: 0.25
            }
            return rank * weight
        }
    }

    static let shared = FolderHistory(url: defaultURL)

    /// 点数の合計がこれを超えたら全体を減らし、使わなくなったフォルダを消していく
    static let maxTotalRank = 10_000.0

    nonisolated(unsafe) private var db: OpaquePointer?
    private var cache: [Entry]?

    private static var defaultURL: URL {
        if let path = ProcessInfo.processInfo.environment["NOXY_HISTORY_PATH"] {
            return URL(fileURLWithPath: path)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("noxy/history.sqlite")
    }

    init(url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            db = nil
            return
        }
        execute("""
            CREATE TABLE IF NOT EXISTS folders (
                path TEXT PRIMARY KEY,
                rank REAL NOT NULL,
                last_access REAL NOT NULL
            )
            """)
    }

    deinit {
        sqlite3_close(db)
    }

    func visit(_ url: URL, now: Date = Date()) {
        let path = url.standardizedFileURL.path
        run("""
            INSERT INTO folders (path, rank, last_access) VALUES (?, 1, ?)
            ON CONFLICT(path) DO UPDATE SET rank = rank + 1, last_access = excluded.last_access
            """, bind: [.text(path), .real(now.timeIntervalSince1970)])
        age()
        cache = nil
    }

    func entries() -> [Entry] {
        if let cache { return cache }
        var result: [Entry] = []
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT path, rank, last_access FROM folders ORDER BY rank DESC LIMIT 5000", -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let text = sqlite3_column_text(statement, 0) else { continue }
            result.append(Entry(
                path: String(cString: text),
                rank: sqlite3_column_double(statement, 1),
                lastAccess: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
            ))
        }
        cache = result
        return result
    }

    func remove(_ path: String) {
        run("DELETE FROM folders WHERE path = ?", bind: [.text(path)])
        cache = nil
    }

    func removeAll() {
        execute("DELETE FROM folders")
        cache = nil
    }

    /// 消えたフォルダを履歴から外す（要件 C-12）。
    func removeMissing() {
        for entry in entries() where !FileManager.default.fileExists(atPath: entry.path) {
            remove(entry.path)
        }
    }

    private func age() {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT SUM(rank) FROM folders", -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, sqlite3_column_double(statement, 0) > Self.maxTotalRank else { return }
        execute("UPDATE folders SET rank = rank * 0.9")
        execute("DELETE FROM folders WHERE rank < 1")
    }

    // MARK: - SQLite

    private enum Value {
        case text(String)
        case real(Double)
    }

    private func execute(_ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func run(_ sql: String, bind values: [Value]) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case .text(let text): sqlite3_bind_text(statement, position, text, -1, transient)
            case .real(let number): sqlite3_bind_double(statement, position, number)
            }
        }
        sqlite3_step(statement)
    }
}
