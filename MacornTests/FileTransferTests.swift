import Foundation
import Testing
@testable import Macorn

/// 実際に一時フォルダでコピー・移動して確かめる。
final class FileTransferTests {
    private let root: URL
    private let fm = FileManager.default

    init() throws {
        root = fm.temporaryDirectory.appendingPathComponent("macorn-transfer-\(UUID().uuidString)")
        try fm.createDirectory(at: root.appendingPathComponent("src/nested"), withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: root.appendingPathComponent("src/a.txt"))
        try Data(repeating: 7, count: 300_000).write(to: root.appendingPathComponent("src/nested/b.bin"))
        try fm.createDirectory(at: root.appendingPathComponent("dest"), withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func url(_ path: String) -> URL { root.appendingPathComponent(path) }

    @Test func copiesFileWithContents() throws {
        let progress = TransferProgress()
        try FileTransfer.copyItem(at: url("src/a.txt"), to: url("dest/a.txt"), progress: progress)
        #expect(try String(contentsOf: url("dest/a.txt"), encoding: .utf8) == "hello")
        #expect(fm.fileExists(atPath: url("src/a.txt").path))
    }

    @Test func copiesFolderRecursivelyAndReportsProgress() throws {
        let progress = TransferProgress()
        try FileTransfer.copyItem(at: url("src"), to: url("dest/src"), progress: progress)
        #expect(fm.fileExists(atPath: url("dest/src/nested/b.bin").path))
        #expect(progress.completedBytes >= 300_000)
    }

    @Test func refusesToOverwrite() throws {
        try Data("old".utf8).write(to: url("dest/a.txt"))
        #expect(throws: (any Error).self) {
            try FileTransfer.copyItem(at: self.url("src/a.txt"), to: self.url("dest/a.txt"), progress: TransferProgress())
        }
        #expect(try String(contentsOf: url("dest/a.txt"), encoding: .utf8) == "old")
    }

    @Test func cancelledCopyLeavesNothingBehind() throws {
        let progress = TransferProgress()
        progress.cancel()
        #expect(throws: CancellationError.self) {
            try FileTransfer.copyItem(at: self.url("src"), to: self.url("dest/src"), progress: progress)
        }
        #expect(!fm.fileExists(atPath: url("dest/src").path))
        #expect(fm.fileExists(atPath: url("src/nested/b.bin").path))
    }

    @Test func movesWithinVolume() throws {
        try FileTransfer.moveItem(at: url("src"), to: url("dest/moved"), sameVolume: true, progress: TransferProgress())
        #expect(!fm.fileExists(atPath: url("src").path))
        #expect(fm.fileExists(atPath: url("dest/moved/a.txt").path))
    }

    @Test func moveByCopyDeletesSourceOnlyAfterSuccess() throws {
        try FileTransfer.moveItem(at: url("src"), to: url("dest/moved"), sameVolume: false, progress: TransferProgress())
        #expect(!fm.fileExists(atPath: url("src").path))
        #expect(fm.fileExists(atPath: url("dest/moved/nested/b.bin").path))
    }

    @Test func totalSizeCountsNestedFiles() {
        #expect(FileTransfer.totalSize(of: [url("src")]) == 300_005)
    }

    @Test func detectsSameVolumeAndSameFile() {
        #expect(FileTransfer.isSameVolume(url("src"), url("dest")))
        #expect(FileTransfer.isSameFile(url("src/a.txt"), url("src/a.txt")))
        #expect(!FileTransfer.isSameFile(url("src/a.txt"), url("src/nested")))
    }
}
