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
        #expect(store.rootTags.map(\.name) == ["お気に入り", "仕事"])
        #expect(store.children(of: store.tag(named: "仕事")!).map(\.name) == ["仕事/案件A"])
        // 同じ名前（大文字・小文字の違いも）なら作らずに既存のものを返す
        #expect(store.createTag(named: "仕事/案件a")?.id == child.id)
        #expect(store.createTag(named: " / ") == nil)
    }

    @Test func movesTagUnderAnotherParent() throws {
        let store = TagStore(fileURL: fileURL)
        let work = try #require(store.createTag(named: "仕事"))
        let a = try #require(store.createTag(named: "案件A"))
        let sub = try #require(store.createTag(named: "案件A/資料"))
        store.assign(sub.id, to: [url("doc")])

        // 子のタグもいっしょに移り、付けた項目はそのまま
        #expect(store.moveTag(a.id, under: work.id))
        #expect(store.tag(id: a.id)?.name == "仕事/案件A")
        #expect(store.tag(id: sub.id)?.name == "仕事/案件A/資料")
        #expect(store.urls(taggedWith: work.id) == [url("doc")])

        // 自分や子孫の下には入れない
        #expect(!store.canMoveTag(work.id, under: sub.id))
        #expect(!store.canMoveTag(a.id, under: a.id))
        // 今の親と同じなら何もしない
        #expect(!store.canMoveTag(a.id, under: work.id))

        // いちばん上へ戻す
        #expect(store.moveTag(a.id, under: nil))
        #expect(store.tag(id: sub.id)?.name == "案件A/資料")

        // 移した先に同じ名前があれば不可
        _ = try #require(store.createTag(named: "仕事/案件A"))
        #expect(!store.canMoveTag(a.id, under: work.id))
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

    @Test func reordersTagsManually() throws {
        let store = TagStore(fileURL: fileURL)
        let a = try #require(store.createTag(named: "A"))
        let b = try #require(store.createTag(named: "B"))
        let c = try #require(store.createTag(named: "C"))
        #expect(store.rootTags.map(\.name) == ["お気に入り", "A", "B", "C"])

        // 同じ親の中で並べ替える（index は今の並びでの位置。自分より後ろなら、その前に入る）
        #expect(store.moveTag(c.id, under: nil, at: 0))
        #expect(store.rootTags.map(\.name) == ["C", "お気に入り", "A", "B"])
        #expect(store.moveTag(c.id, under: nil, at: 4))
        #expect(store.rootTags.map(\.name) == ["お気に入り", "A", "B", "C"])

        // ほかの親の下の、指定の位置へ入れる
        let child = try #require(store.createTag(named: "A/子"))
        #expect(store.moveTag(b.id, under: a.id, at: 0))
        #expect(store.children(of: store.tag(id: a.id)!).map(\.leafName) == ["B", "子"])
        #expect(store.sortedTags.map(\.name) == ["お気に入り", "A", "A/B", "A/子", "C"])
        _ = child

        // 並び順は保存され、次に開いたときも同じ
        let reloaded = TagStore(fileURL: fileURL)
        #expect(reloaded.sortedTags.map(\.name) == ["お気に入り", "A", "A/B", "A/子", "C"])
        _ = c
    }

    @Test func oldLibrariesStartInNameOrder() throws {
        // 並び順を持たない以前のファイルは、今まで見えていた名前の順で始める
        let library = TagLibrary(tags: [Tag(id: UUID(), name: "仕事", color: "#000000"), Tag(id: UUID(), name: "個人", color: "#000000")], items: [])
        try JSONEncoder().encode(library).write(to: fileURL)
        let store = TagStore(fileURL: fileURL)
        #expect(store.rootTags.map(\.name) == ["個人", "仕事", "お気に入り"])
    }

    @Test func childTagImpliesParentTag() throws {
        let store = TagStore(fileURL: fileURL)
        let child = try #require(store.createTag(named: "仕事/案件A"))
        let parent = try #require(store.tag(named: "仕事"))
        store.assign(child.id, to: [url("project")])

        // 子のタグが付いていれば、親のタグも付いているとみなす（保存は子だけ）
        #expect(store.tags(for: url("project")).map(\.name) == ["仕事", "仕事/案件A"])
        #expect(store.explicitTags(for: url("project")).map(\.name) == ["仕事/案件A"])
        #expect(store.hasTag(parent.id, on: url("project")))
        #expect(store.urls(taggedWith: parent.id) == [url("project")])

        // タグを移すと、親も合わせて変わる
        let other = try #require(store.createTag(named: "個人"))
        store.moveTag(child.id, under: other.id)
        #expect(store.tags(for: url("project")).map(\.name) == ["個人", "個人/案件A"])
        #expect(!store.hasTag(parent.id, on: url("project")))

        // 親のタグを外すと、子のタグも外れる
        store.unassign(other.id, from: [url("project")])
        #expect(store.tags(for: url("project")).isEmpty)
    }

    @Test func favoritesTagIsBuiltIn() throws {
        let store = TagStore(fileURL: fileURL)
        let favorites = try #require(store.tag(id: TagStore.favoritesID))
        #expect(favorites.name == "お気に入り")
        // 名前の変更・削除・ほかのタグの下への移動はできない
        #expect(!store.renameTag(favorites.id, to: "好き"))
        store.deleteTag(favorites.id)
        #expect(store.tag(id: TagStore.favoritesID) != nil)
        let work = try #require(store.createTag(named: "仕事"))
        #expect(!store.canMoveTag(favorites.id, under: work.id))
        // ふつうのタグと同じように付け外しでき、フォルダの色分けには使わない
        store.assign(favorites.id, to: [url("project")])
        #expect(store.hasTag(favorites.id, on: url("project")))
        #expect(store.folderColor(for: url("project")) == nil || !Preferences.colorFoldersByTag)
        store.assign(work.id, to: [url("project")])
        #expect(store.folderColor(for: url("project")) == work.color || !Preferences.colorFoldersByTag)
    }

    @Test func adoptsExistingFavoritesTag() throws {
        // 以前に自分で「お気に入り」というタグを作っていたら、それを「お気に入り」のタグにする（付けた項目もそのまま）
        let oldID = UUID()
        let library = TagLibrary(
            tags: [Tag(id: oldID, name: "お気に入り", color: "#0A84FF")],
            items: [TaggedItem(path: TagStore.key(url("b.txt")), bookmark: nil, tagIDs: [oldID])]
        )
        try JSONEncoder().encode(library).write(to: fileURL)
        let store = TagStore(fileURL: fileURL)
        #expect(store.tags.count == 1)
        #expect(store.tag(id: TagStore.favoritesID)?.color == "#0A84FF")
        #expect(store.hasTag(TagStore.favoritesID, on: url("b.txt")))
    }

    @Test func deletingRemovesChildrenAndAssignments() throws {
        let store = TagStore(fileURL: fileURL)
        let child = try #require(store.createTag(named: "仕事/案件A"))
        let parent = try #require(store.tag(named: "仕事"))
        store.assign(child.id, to: [url("b.txt")])
        store.deleteTag(parent.id)
        #expect(store.tags.map(\.id) == [TagStore.favoritesID])
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
