import Foundation

/// フォルダの合計サイズを裏で計算する（要件 V-09）。
/// 一度計算したサイズは覚えておき、中身が変わったらそのフォルダと親フォルダの分を捨てる。
final class FolderSizeService {
    static let shared = FolderSizeService()
    /// 同時に計算するフォルダの数（ディスクを占有しないように抑える）
    static let maxConcurrent = 2

    private var cache: [String: Int64] = [:]
    private var queue: [(url: URL, owner: ObjectIdentifier, completion: (URL, Int64) -> Void)] = []
    private var running = 0
    private var cancelledOwners = Set<ObjectIdentifier>()

    func cachedSize(for url: URL) -> Int64? {
        cache[url.standardizedFileURL.path]
    }

    /// まだ計算していないフォルダの計算を頼む。owner ごとにまとめて取り消せる。
    func request(_ urls: [URL], owner: AnyObject, completion: @escaping (URL, Int64) -> Void) {
        let id = ObjectIdentifier(owner)
        cancelledOwners.remove(id)
        let queued = Set(queue.map(\.url.path))
        for url in urls where cache[url.standardizedFileURL.path] == nil && !queued.contains(url.path) {
            queue.append((url, id, completion))
        }
        startNext()
    }

    /// 移動したときなど、もう要らなくなった計算をやめる。
    func cancel(owner: AnyObject) {
        let id = ObjectIdentifier(owner)
        queue.removeAll { $0.owner == id }
        cancelledOwners.insert(id)
    }

    /// path の中身が変わったときに呼ぶ。そのフォルダと親フォルダのサイズを捨てる。
    func invalidate(path: String) {
        var current = path
        while true {
            cache[current] = nil
            guard current != "/", !current.isEmpty else { break }
            current = (current as NSString).deletingLastPathComponent
        }
    }

    private func startNext() {
        while running < Self.maxConcurrent, !queue.isEmpty {
            let job = queue.removeFirst()
            running += 1
            let url = job.url
            Task {
                let size = await Task.detached(priority: .utility) {
                    FileTransfer.totalSize(of: [url])
                }.value
                running -= 1
                cache[job.url.standardizedFileURL.path] = size
                if !cancelledOwners.contains(job.owner) {
                    job.completion(job.url, size)
                }
                startNext()
            }
        }
    }
}
