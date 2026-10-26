import Foundation
import Testing
@testable import Noxy

struct FileSortTests {
    private func entry(_ name: String, folder: Bool = false, size: Int64? = nil, date: TimeInterval = 0, kind: String = "") -> FileEntry {
        FileEntry(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            name: name,
            isFolder: folder,
            isPackage: false,
            isHidden: false,
            isSymbolicLink: false,
            size: folder ? nil : size,
            dateModified: Date(timeIntervalSince1970: date),
            kind: kind
        )
    }

    @Test func namesSortNaturally() {
        let entries = [entry("file10"), entry("file2"), entry("File1")]
        let sorted = FileSort(key: .name).sorted(entries).map(\.name)
        #expect(sorted == ["File1", "file2", "file10"])
    }

    @Test func descendingByName() {
        let entries = [entry("a"), entry("c"), entry("b")]
        #expect(FileSort(key: .name, ascending: false).sorted(entries).map(\.name) == ["c", "b", "a"])
    }

    @Test func foldersAreSmallestBySize() {
        let entries = [entry("big", size: 100), entry("dir", folder: true), entry("small", size: 1)]
        #expect(FileSort(key: .size).sorted(entries).map(\.name) == ["dir", "small", "big"])
    }

    @Test func tiesFallBackToName() {
        let entries = [entry("b", date: 5), entry("a", date: 5), entry("c", date: 1)]
        #expect(FileSort(key: .dateModified).sorted(entries).map(\.name) == ["c", "a", "b"])
        #expect(FileSort(key: .dateModified, ascending: false).sorted(entries).map(\.name) == ["a", "b", "c"])
    }

    @Test func roundTripsThroughSortDescriptor() {
        let sort = FileSort(key: .kind, ascending: false)
        #expect(FileSort(descriptor: sort.descriptor) == sort)
        #expect(FileSort(descriptor: NSSortDescriptor(key: "unknown", ascending: true)) == nil)
    }
}
