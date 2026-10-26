import Foundation
import Testing
@testable import Noxy

struct BulkRenameTests {
    private func names(_ names: [String], _ options: BulkRenameOptions, others: Set<String> = []) -> [BulkRenamePreview] {
        let items = names.map { (url: URL(fileURLWithPath: "/tmp/x/\($0)"), isDirectory: false) }
        return BulkRename.preview(items, options: options) { _ in others }
    }

    @Test func replaceKeepsExtension() {
        var options = BulkRenameOptions()
        options.find = "txt"
        options.replacement = "doc"
        #expect(names(["a_txt.txt"], options).map(\.newName) == ["a_doc.txt"])
        options.includeExtension = true
        #expect(names(["a_txt.txt"], options).map(\.newName) == ["a_doc.doc"])
    }

    @Test func replaceIgnoresCaseByDefault() {
        var options = BulkRenameOptions()
        options.find = "IMG"
        options.replacement = "photo"
        #expect(names(["img_1.jpg"], options).map(\.newName) == ["photo_1.jpg"])
        options.caseSensitive = true
        #expect(names(["img_1.jpg"], options).map(\.newName) == ["img_1.jpg"])
    }

    @Test func regexWithGroups() {
        var options = BulkRenameOptions()
        options.mode = .regex
        options.pattern = #"(\d+)-(.*)"#
        options.template = "$2-$1"
        #expect(names(["01-intro.md"], options).map(\.newName) == ["intro-01.md"])
    }

    @Test func invalidRegexIsReported() {
        var options = BulkRenameOptions()
        options.mode = .regex
        options.pattern = "("
        #expect(names(["a.txt"], options).first?.problem != nil)
    }

    @Test func sequenceNumbersInOrder() {
        var options = BulkRenameOptions()
        options.mode = .sequence
        options.prefix = "shot_"
        options.start = 9
        options.digits = 3
        #expect(names(["b.png", "a.png"], options).map(\.newName) == ["shot_009.png", "shot_010.png"])
    }

    @Test func changeCase() {
        var options = BulkRenameOptions()
        options.mode = .changeCase
        options.caseStyle = .upper
        #expect(names(["readme.md"], options).map(\.newName) == ["README.md"])
    }

    @Test func detectsDuplicatesAndClashes() {
        var options = BulkRenameOptions()
        options.find = "1"
        options.replacement = "2"
        let duplicates = names(["a1.txt", "a2.txt"], options)
        // a1→a2 は、a2 も変更対象なので問題ないが、a2→a2 と重なる
        #expect(duplicates.first?.problem != nil)

        options.find = "x"
        options.replacement = "y"
        let clash = names(["x.txt"], options, others: ["y.txt"])
        #expect(clash.first?.problem != nil)
    }
}

/// 実際にファイルを作って確かめる。
final class FileExtrasTests {
    private let root: URL
    private let fm = FileManager.default

    init() throws {
        root = fm.temporaryDirectory.appendingPathComponent("noxy-extras-\(UUID().uuidString)")
        try fm.createDirectory(at: root.appendingPathComponent("folder"), withIntermediateDirectories: true)
        try Data("A".utf8).write(to: root.appendingPathComponent("a.txt"))
        try Data("B".utf8).write(to: root.appendingPathComponent("b.txt"))
        try Data("F".utf8).write(to: root.appendingPathComponent("folder/inside.txt"))
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func url(_ name: String) -> URL { root.appendingPathComponent(name) }

    @Test func bulkRenameCanSwapNames() async throws {
        let manager = FileOperationManager()
        let results = await manager.bulkRename([(url("a.txt"), "b.txt"), (url("b.txt"), "a.txt")], window: nil)
        #expect(results.count == 2)
        #expect(try String(contentsOf: url("a.txt"), encoding: .utf8) == "B")
        #expect(try String(contentsOf: url("b.txt"), encoding: .utf8) == "A")
    }

    @Test func createsSymbolicLink() async throws {
        let manager = FileOperationManager()
        let links = await manager.makeSymbolicLinks(to: [url("a.txt")], window: nil)
        let link = try #require(links.first)
        #expect(link.lastPathComponent == "a のリンク.txt")
        #expect(try fm.destinationOfSymbolicLink(atPath: link.path) == url("a.txt").path)
    }

    @Test func compressAndExpandRoundTrip() async throws {
        let manager = FileOperationManager()
        let archive = try #require(await manager.compress([url("folder")], window: nil))
        #expect(archive.lastPathComponent == "folder.zip")
        try fm.removeItem(at: url("folder"))

        let expanded = try #require(await manager.expand(archive, window: nil))
        // 中身が1つのフォルダだけなので、そのフォルダがそのまま置かれる
        #expect(expanded.lastPathComponent == "folder")
        #expect(try String(contentsOf: url("folder/inside.txt"), encoding: .utf8) == "F")
    }

    @Test func compressesMultipleItems() async throws {
        let manager = FileOperationManager()
        let archive = try #require(await manager.compress([url("a.txt"), url("b.txt")], window: nil))
        #expect(archive.lastPathComponent == "アーカイブ.zip")
        let expanded = try #require(await manager.expand(archive, window: nil))
        #expect(fm.fileExists(atPath: expanded.appendingPathComponent("a.txt").path))
    }
}
