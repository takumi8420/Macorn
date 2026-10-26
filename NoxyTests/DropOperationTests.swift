import AppKit
import Testing
@testable import Noxy

/// ドラッグ＆ドロップでコピーと移動のどちらにするか（Finder と同じ決め方）。
struct DropOperationTests {
    private let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("noxy-a.txt")
    private let otherFolder = URL(fileURLWithPath: NSHomeDirectory())
    private let all: NSDragOperation = [.copy, .move, .link, .generic]

    private func operation(_ mask: NSDragOperation, _ urls: [URL], _ folder: URL) -> NSDragOperation {
        FileBrowserViewController.dropOperation(mask: mask, urls: urls, folder: folder)
    }

    @Test func optionMeansCopy() {
        #expect(operation(.copy, [file], otherFolder) == .copy)
    }

    @Test func commandMeansMove() {
        #expect(operation(.generic, [file], otherFolder) == .move)
    }

    @Test func noModifierOnDifferentVolumeCopies() {
        // 存在しないボリューム扱いの URL は「別のボリューム」としてコピーになる
        let elsewhere = URL(fileURLWithPath: "/Volumes/does-not-exist/x")
        #expect(operation(all, [file], elsewhere) == .copy)
    }

    @Test func cannotDropIntoItself() {
        let folder = URL(fileURLWithPath: "/tmp/project")
        #expect(operation(all, [folder], folder) == [])
        #expect(operation(all, [folder], folder.appendingPathComponent("src")) == [])
    }

    @Test func movingIntoSameFolderIsRejected() {
        #expect(operation(.generic, [file], file.deletingLastPathComponent()) == [])
        #expect(operation(.copy, [file], file.deletingLastPathComponent()) == .copy)
    }
}
