import CoreServices
import Foundation

/// フォルダ以下の変更を FSEvents で監視する（要件 9.1: 外部の変更を1秒以内に反映）。
/// 変更のあったフォルダのパスを、メインスレッドで handler に渡す。
final class DirectoryWatcher {
    nonisolated(unsafe) private var stream: FSEventStreamRef?
    private let handler: ([String]) -> Void

    init(url: URL, latency: TimeInterval = 0.3, handler: @escaping ([String]) -> Void) {
        self.handler = handler

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot
        )
        guard let stream = FSEventStreamCreate(
            nil,
            directoryWatcherCallback,
            &context,
            [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else { return }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    fileprivate func deliver(_ paths: [String]) {
        handler(paths)
    }

    func stop() {
        guard let stream else { return }
        Self.release(stream)
        self.stream = nil
    }

    deinit {
        if let stream { Self.release(stream) }
    }

    private nonisolated static func release(_ stream: FSEventStreamRef) {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}

private nonisolated func directoryWatcherCallback(
    _ stream: ConstFSEventStreamRef,
    _ info: UnsafeMutableRawPointer?,
    _ count: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ flags: UnsafePointer<FSEventStreamEventFlags>,
    _ ids: UnsafePointer<FSEventStreamEventId>
) {
    guard let info else { return }
    let array = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as NSArray
    let paths = array.compactMap { $0 as? String }
    let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
    // ストリームはメインキューで動かしているので、ここはメインスレッド
    MainActor.assumeIsolated {
        watcher.deliver(paths)
    }
}
