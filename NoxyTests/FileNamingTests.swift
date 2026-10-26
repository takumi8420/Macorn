import Foundation
import Testing
@testable import Noxy

struct FileNamingTests {
    private let folder = URL(fileURLWithPath: "/tmp/x")

    private func existing(_ names: Set<String>) -> (URL) -> Bool {
        { names.contains($0.lastPathComponent) }
    }

    @Test func numberedKeepsNameWhenFree() {
        let url = FileNaming.uniqueURL(for: folder.appendingPathComponent("a.txt"), isDirectory: false, style: .numbered, exists: existing([]))
        #expect(url.lastPathComponent == "a.txt")
    }

    @Test func numberedAddsNumberBeforeExtension() {
        let url = FileNaming.uniqueURL(
            for: folder.appendingPathComponent("a.txt"), isDirectory: false, style: .numbered,
            exists: existing(["a.txt", "a 2.txt"])
        )
        #expect(url.lastPathComponent == "a 3.txt")
    }

    @Test func copyStyle() {
        let first = FileNaming.uniqueURL(for: folder.appendingPathComponent("a.txt"), isDirectory: false, style: .copy, exists: existing(["a.txt"]))
        #expect(first.lastPathComponent == "a のコピー.txt")
        let second = FileNaming.uniqueURL(
            for: folder.appendingPathComponent("a.txt"), isDirectory: false, style: .copy,
            exists: existing(["a.txt", "a のコピー.txt"])
        )
        #expect(second.lastPathComponent == "a のコピー 2.txt")
    }

    @Test func duplicatingACopyAddsNumber() {
        let url = FileNaming.uniqueURL(
            for: folder.appendingPathComponent("a のコピー.txt"), isDirectory: false, style: .copy,
            exists: existing(["a.txt", "a のコピー.txt"])
        )
        #expect(url.lastPathComponent == "a のコピー 2.txt")
        let third = FileNaming.uniqueURL(
            for: folder.appendingPathComponent("a のコピー 2.txt"), isDirectory: false, style: .copy,
            exists: existing(["a.txt", "a のコピー.txt", "a のコピー 2.txt"])
        )
        #expect(third.lastPathComponent == "a のコピー 3.txt")
    }

    @Test func foldersHaveNoExtension() {
        let url = FileNaming.uniqueURL(
            for: folder.appendingPathComponent("v1.2"), isDirectory: true, style: .numbered,
            exists: existing(["v1.2"])
        )
        #expect(url.lastPathComponent == "v1.2 2")
    }

    @Test func dotfilesHaveNoExtension() {
        #expect(FileNaming.split(".zshrc", isDirectory: false) == (".zshrc", ""))
        #expect(FileNaming.split("archive.tar.gz", isDirectory: false) == ("archive.tar", "gz"))
    }

    @Test func editableRangeStopsBeforeExtension() {
        #expect(FileNaming.editableRange(for: "README.md", isDirectory: false) == NSRange(location: 0, length: 6))
        #expect(FileNaming.editableRange(for: "src.old", isDirectory: true) == NSRange(location: 0, length: 7))
        #expect(FileNaming.editableRange(for: "日本語.txt", isDirectory: false) == NSRange(location: 0, length: 3))
    }

    @Test func validation() {
        #expect(FileNaming.validationError(for: "ok.txt") == nil)
        #expect(FileNaming.validationError(for: "  ") != nil)
        #expect(FileNaming.validationError(for: "a/b") != nil)
        #expect(FileNaming.validationError(for: "..") != nil)
        #expect(FileNaming.validationError(for: String(repeating: "あ", count: 100)) != nil)
    }
}
