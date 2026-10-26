import Foundation
import Testing
import AppKit
@testable import Macorn

/// Macorn だけのタグ（保存・階層・付け外し・移動への追従）。
final class TagStoreTests {
    private let folder: URL
    private let fileURL: URL
    private let fm = FileManager.default

    init() throws {
        folder = fm.temporaryDirectory.appendingPathComponent("macorn-tags-\(UUID().uuidString)")
        try fm.createDirectory(at: folder.appendingPathComponent("project/src"), withIntermediateDirectories: true)
        try Data("a".utf8).write(to: folder.appendingPathComponent("project/a.txt"))
        try Data("b".utf8).write(to: folder.appendingPathComponent("b.txt"))
        fileURL = folder.appendingPathComponent("tags.json")
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    private func url(_ path: String) -> URL { folder.appendingPathComponent(path) }

    @Test func createsHierarchyWithParents() throws {
        let store = TagStore(fileURL: fileURL)
        let child = try #require(store.createTag(named: " 仕事 / 案件A "))
        #expect(child.name == "仕事/案件A")
        #expect(child.leafName == "案件A")
        #expect(child.depth == 1)
        #expect(store.tag(named: "仕事") != nil)
        #expect(store.rootTags.map(\.name) == ["仕事"])
        #expect(store.children(of: store.tag(named: "仕事")!).map(\.name) == ["仕事/案件A"])
        // 同じ名前（大文字・小文字の違いも）なら作らずに既存のものを返す
        #expect(store.createTag(named: "仕事/案件a")?.id == child.id)
        #expect(store.createTag(named: " / ") == nil)
    }

    @Test func assignsAndToggles() throws {
        let store = TagStore(fileURL: fileURL)
        let tag = try #require(store.createTag(named: "重要"))
        store.assign(tag.id, to: [url("project"), url("b.txt")])
        #expect(store.tags(for: url("project")).map(\.name) == ["重要"])
        #expect(store.urls(taggedWith: tag.id).count == 2)

        // 一部にだけ付いているときの toggle は「全部に付ける」
        store.unassign(tag.id, from: [url("b.txt")])
        store.toggle(tag.id, on: [url("project"), url("b.txt")])
        #expect(store.hasTag(tag.id, on: url("b.txt")))
        // 全部に付いていれば外す
        store.toggle(tag.id, on: [url("project"), url("b.txt")])
        #expect(store.urls(taggedWith: tag.id).isEmpty)
    }

    @Test func parentTagIncludesChildItems() throws {
        let store = TagStore(fileURL: fileURL)
        let child = try #require(store.createTag(named: "仕事/案件A"))
        let parent = try #require(store.tag(named: "仕事"))
        store.assign(child.id, to: [url("project/a.txt")])
        #expect(store.urls(taggedWith: parent.id).map(\.lastPathComponent) == ["a.txt"])
        #expect(store.count(for: child.id) == 1)
    }

    @Test func renamingMovesChildren() throws {
        let store = TagStore(fileURL: fileURL)
        let child = try #require(store.createTag(named: "仕事/案件A"))
        let parent = try #require(store.tag(named: "仕事"))
        #expect(store.renameTag(parent.id, to: "業務"))
        #expect(store.tag(id: child.id)?.name == "業務/案件A")
        // 既にある名前・自分の下の階層には変えられない
        let other = try #require(store.createTag(named: "個人"))
        #expect(!store.renameTag(other.id, to: "業務"))
        #expect(!store.renameTag(parent.id, to: "業務/案件A/中"))
    }

    @Test func deletingRemovesChildrenAndAssignments() throws {
        let store = TagStore(fileURL: fileURL)
        let child = try #require(store.createTag(named: "仕事/案件A"))
        let parent = try #require(store.tag(named: "仕事"))
        store.assign(child.id, to: [url("b.txt")])
        store.deleteTag(parent.id)
        #expect(store.tags.isEmpty)
        #expect(store.tags(for: url("b.txt")).isEmpty)
    }

    @Test func followsMovesInsideMacorn() throws {
        let store = TagStore(fileURL: fileURL)
        let tag = try #require(store.createTag(named: "重要"))
        store.assign(tag.id, to: [url("project"), url("project/a.txt")])
        try fm.moveItem(at: url("project"), to: url("renamed"))
        store.itemMoved(from: url("project"), to: url("renamed"))
        #expect(store.hasTag(tag.id, on: url("renamed")))
        #expect(store.hasTag(tag.id, on: url("renamed/a.txt")))
        #expect(!store.hasTag(tag.id, on: url("project")))
    }

    @Test func findsItemsMovedOutsideMacorn() async throws {
        let store = TagStore(fileURL: fileURL)
        let tag = try #require(store.createTag(named: "重要"))
        store.assign(tag.id, to: [url("b.txt")])
        // Finder で移動したのと同じ（Macorn は知らない）
        try fm.moveItem(at: url("b.txt"), to: url("project/b-moved.txt"))
        await store.resolveMovedItems()
        #expect(store.hasTag(tag.id, on: url("project/b-moved.txt")))
    }

    @Test func persistsToFile() throws {
        let store = TagStore(fileURL: fileURL)
        let tag = try #require(store.createTag(named: "仕事", color: "#123456"))
        store.assign(tag.id, to: [url("b.txt")])

        let reloaded = TagStore(fileURL: fileURL)
        #expect(reloaded.tag(named: "仕事")?.color == "#123456")
        #expect(reloaded.hasTag(tag.id, on: url("b.txt")))
    }

    @Test func tagLocationRoundTrip() {
        let id = UUID()
        let location = TagLocation.url(for: id)
        #expect(TagLocation.tagID(from: location) == id)
        #expect(TagLocation.tagID(from: URL(fileURLWithPath: "/tmp")) == nil)
        #expect(TagLocation.location(from: TagLocation.savedString(for: location)) == location)
        #expect(TagLocation.location(from: "/tmp").path == "/tmp")
    }

    @Test func japaneseNamesMatchRegardlessOfNormalization() throws {
        let store = TagStore(fileURL: fileURL)
        let tag = try #require(store.createTag(named: "重要"))
        let composed = "ダウンロード".precomposedStringWithCanonicalMapping
        let decomposed = "ダウンロード".decomposedStringWithCanonicalMapping
        #expect(composed != decomposed.unicodeScalars.map(String.init).joined() || composed.unicodeScalars.count != decomposed.unicodeScalars.count)
        store.assign(tag.id, to: [URL(fileURLWithPath: "/tmp/" + decomposed)])
        #expect(store.hasTag(tag.id, on: URL(fileURLWithPath: "/tmp/" + composed)))
    }

    @Test func folderColorFollowsFirstTag() throws {
        let store = TagStore(fileURL: fileURL)
        let work = try #require(store.createTag(named: "仕事", color: "#0A84FF"))
        let important = try #require(store.createTag(named: "重要", color: "#FF5F57"))
        store.assign(important.id, to: [url("project")])
        store.assign(work.id, to: [url("project")])
        // 名前の順で最初のタグの色（「仕事」が「重要」より先）
        #expect(store.folderColor(for: url("project")) == "#0A84FF")
        #expect(store.folderColor(for: url("b.txt")) == nil)
    }

    @Test func tintKeepsIconSize() {
        let icon = NSWorkspace.shared.icon(forFile: NSTemporaryDirectory())
        icon.size = NSSize(width: 16, height: 16)
        #expect(FileNode.tint(icon, with: .systemRed).size == icon.size)
    }

    @Test func colorHexRoundTrip() {
        #expect(NSColor(hex: "#0A84FF").hexString == "#0A84FF")
    }
}
