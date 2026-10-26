import Foundation

/// コピーの進み具合と中止の指示。コピー中の別スレッドと画面の両方から触るため、ロックで守る。
nonisolated final class TransferProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var finishedBytes: Int64 = 0
    private var currentFileBytes: Int64 = 0
    private var cancelled = false
    private var name = ""

    var completedBytes: Int64 { lock.withLock { finishedBytes + currentFileBytes } }
    var isCancelled: Bool { lock.withLock { cancelled } }
    var currentName: String { lock.withLock { name } }

    func cancel() { lock.withLock { cancelled = true } }

    func begin(name: String) {
        lock.withLock {
            self.name = name
            currentFileBytes = 0
        }
    }

    func updateCurrentFile(bytes: Int64) { lock.withLock { currentFileBytes = bytes } }

    func finishCurrentFile() {
        lock.withLock {
            finishedBytes += currentFileBytes
            currentFileBytes = 0
        }
    }

    func addFinished(bytes: Int64) { lock.withLock { finishedBytes += bytes } }
}

/// ファイル・フォルダのコピーと移動の実処理。
nonisolated enum FileTransfer {
    /// copyfile(3) でメタデータごとコピーする。失敗・中止したときは途中までのコピーを消す。
    static func copyItem(at source: URL, to destination: URL, progress: TransferProgress) throws {
        // 既存のものを上書きしないよう、コピー先は必ず存在しない場所にする
        guard !FileNaming.itemExists(destination) else {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: destination.path])
        }
        guard let state = copyfile_state_alloc() else { throw CocoaError(.fileWriteUnknown) }
        defer { copyfile_state_free(state) }

        let callback: copyfile_callback_t = copyfileProgressCallback
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(callback, to: UnsafeRawPointer.self))
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), Unmanaged.passUnretained(progress).toOpaque())

        let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_NOFOLLOW_SRC)
        let result = copyfile(source.path, destination.path, state, flags)
        let code = errno
        progress.finishCurrentFile()

        if result != 0 || progress.isCancelled {
            try? FileManager.default.removeItem(at: destination)
            if progress.isCancelled { throw CancellationError() }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

    /// 移動。同じボリューム内なら名前の付け替えだけで済ませ、別ボリュームなら
    /// 「コピーが完了してから元を消す」順で行う（要件 9.2: 途中で失敗しても元は失われない）。
    static func moveItem(at source: URL, to destination: URL, sameVolume: Bool, progress: TransferProgress) throws {
        guard !FileNaming.itemExists(destination) else {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: destination.path])
        }
        if sameVolume {
            do {
                try FileManager.default.moveItem(at: source, to: destination)
                return
            } catch let error as NSError where (error.userInfo[NSUnderlyingErrorKey] as? NSError)?.code == Int(EXDEV) {
                // 同じボリュームに見えて実は別だった場合は、コピーで続ける
            }
        }
        try copyItem(at: source, to: destination, progress: progress)
        try FileManager.default.removeItem(at: source)
    }

    /// 合計サイズ（進み具合の表示用）。フォルダは中身をすべて数える。
    static func totalSize(of urls: [URL]) -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .totalFileSizeKey, .fileSizeKey]
        func size(_ values: URLResourceValues?) -> Int64 {
            Int64(values?.totalFileSize ?? values?.fileSize ?? 0)
        }
        var total: Int64 = 0
        for url in urls {
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isDirectory == true, values?.isSymbolicLink != true else {
                total += size(values)
                continue
            }
            let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: Array(keys),
                options: [],
                errorHandler: { _, _ in true }
            )
            while let child = enumerator?.nextObject() as? URL {
                let childValues = try? child.resourceValues(forKeys: keys)
                if childValues?.isRegularFile == true { total += size(childValues) }
            }
        }
        return total
    }

    #if DEBUG
    static let debugDelayMicroseconds: UInt32 =
        UInt32(ProcessInfo.processInfo.environment["NOXY_DEBUG_COPY_DELAY_US"] ?? "") ?? 0
    #endif

    static func isSameVolume(_ a: URL, _ b: URL) -> Bool {
        let first = try? a.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        let second = try? b.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        guard let first, let second else { return false }
        return first.isEqual(second)
    }

    static func isSameFile(_ a: URL, _ b: URL) -> Bool {
        let first = try? a.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        let second = try? b.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        guard let first, let second else { return false }
        return first.isEqual(second)
    }

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }
}

private nonisolated func copyfileProgressCallback(
    _ what: Int32,
    _ stage: Int32,
    _ state: copyfile_state_t?,
    _ source: UnsafePointer<CChar>?,
    _ destination: UnsafePointer<CChar>?,
    _ context: UnsafeMutableRawPointer?
) -> Int32 {
    guard let context else { return COPYFILE_CONTINUE }
    let progress = Unmanaged<TransferProgress>.fromOpaque(context).takeUnretainedValue()

    if stage == COPYFILE_ERR { return COPYFILE_QUIT }

    #if DEBUG
    // 自動テスト用: 進み具合の表示と中止を確かめるため、わざと遅くする
    if FileTransfer.debugDelayMicroseconds > 0, what == COPYFILE_RECURSE_FILE, stage == COPYFILE_FINISH {
        usleep(FileTransfer.debugDelayMicroseconds)
    }
    #endif

    switch (what, stage) {
    case (COPYFILE_RECURSE_FILE, COPYFILE_START):
        if let source {
            progress.begin(name: (String(cString: source) as NSString).lastPathComponent)
        }
    case (COPYFILE_COPY_DATA, COPYFILE_PROGRESS):
        var copied: off_t = 0
        copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied)
        progress.updateCurrentFile(bytes: Int64(copied))
    case (COPYFILE_RECURSE_FILE, COPYFILE_FINISH):
        progress.finishCurrentFile()
    default:
        break
    }
    return progress.isCancelled ? COPYFILE_QUIT : COPYFILE_CONTINUE
}
