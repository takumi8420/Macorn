import Foundation
import Testing
@testable import Macorn

/// サイドバーの構成（セクションの順番・表示・タグのセクション、お気に入りのタグ）。
/// 普段の設定を汚さないよう、テスト用の保存先を使う。
final class SidebarStoreTests {
    private let suite = "macorn-sidebar-\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let tagsURL = FileManager.default.temporaryDirectory.appendingPathComponent("macorn-sidebar-tags-\(UUID().uuidString).json")
    private let tags: TagStore

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set([[String: String]](), forKey: "sidebarFavorites")
        tags = TagStore(fileURL: tagsURL)
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: tagsURL)
    }

    @Test func sectionIDsRoundTrip() {
        let id = UUID()
        for section in [SidebarSection.favorites, .tags, .locations, .tag(id), .custom(id)] {
            #expect(SidebarSection(id: section.id) == section)
        }
        #expect(SidebarSection(id: "unknown") == nil)
    }

    @Test func reordersAndHidesSections() {
        let store = SidebarStore(defaults: defaults, tags: tags)
        #expect(store.visibleSections == [.favorites, .tags, .locations])
        store.moveSection(.locations, by: -1)
        #expect(store.visibleSections == [.favorites, .locations, .tags])
        // 2つ以上動かすときも、間の順番は保ったままずらす
        store.moveSection(.tags, by: -2)
        #expect(store.visibleSections == [.tags, .favorites, .locations])
        store.moveSection(.tags, by: 2)
        #expect(store.visibleSections == [.favorites, .locations, .tags])
        store.setSection(.favorites, hidden: true)
        #expect(store.visibleSections == [.locations, .tags])

        // 保存され、次に開いたときも同じ
        let reloaded = SidebarStore(defaults: defaults, tags: tags)
        #expect(reloaded.visibleSections == [.locations, .tags])
        reloaded.resetSections()
        #expect(reloaded.visibleSections == SidebarSection.defaultOrder)
    }

    @Test func tagSectionsAndFavoriteTags() throws {
        let tag = try #require(tags.createTag(named: "サイドバーのテスト"))
        let store = SidebarStore(defaults: defaults, tags: tags)

        store.addTagSection(tag.id)
        #expect(store.visibleSections == [.favorites, .tag(tag.id), .tags, .locations])
        store.addFavoriteTag(tag.id)
        #expect(store.containsFavoriteTag(tag.id))
        #expect(store.favorites.last?.id == "tag:" + tag.id.uuidString)

        let reloaded = SidebarStore(defaults: defaults, tags: tags)
        #expect(reloaded.containsTagSection(tag.id))
        #expect(reloaded.containsFavoriteTag(tag.id))

        reloaded.removeTagSection(tag.id)
        reloaded.removeFavoriteTag(tag.id)
        #expect(!reloaded.containsTagSection(tag.id))
        #expect(!reloaded.containsFavoriteTag(tag.id))
    }
}

/// ドラッグ＆ドロップでの構成の変更
final class SidebarDragTests {
    private let suite = "macorn-sidebar-drag-\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let tagsURL = FileManager.default.temporaryDirectory.appendingPathComponent("macorn-sidebar-tags-\(UUID().uuidString).json")
    private let tags: TagStore

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set([[String: String]](), forKey: "sidebarFavorites")
        tags = TagStore(fileURL: tagsURL)
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: tagsURL)
    }

    @Test func payloadRoundTrip() {
        let id = UUID()
        #expect(SidebarDragPayload(SidebarDragPayload.tag(id).string) == .tag(id))
        #expect(SidebarDragPayload(SidebarDragPayload.section(.locations).string) == .section(.locations))
        #expect(SidebarDragPayload("/Users/someone/file.txt") == nil)
    }

    @Test func movesSectionBeforeTarget() {
        let store = SidebarStore(defaults: defaults, tags: tags)
        store.moveSection(.locations, before: .favorites)
        #expect(store.visibleSections == [.locations, .favorites, .tags])
        store.moveSection(.locations, before: .tags)
        #expect(store.visibleSections == [.favorites, .locations, .tags])
    }

    @Test func dropsTagIntoSectionsAndFavorites() throws {
        let tag = try #require(tags.createTag(named: "ドラッグのテスト"))
        let store = SidebarStore(defaults: defaults, tags: tags)

        // 「場所」の見出しに置くと、その前にタグのセクションができる。もう一度置くと位置だけ変わる
        store.addTagSection(tag.id, before: .locations)
        #expect(store.visibleSections == [.favorites, .tags, .tag(tag.id), .locations])
        store.addTagSection(tag.id, before: .favorites)
        #expect(store.visibleSections == [.tag(tag.id), .favorites, .tags, .locations])

        // お気に入りの好きな位置に入れる。もう一度入れると動かすだけ
        store.addFavorite(FileManager.default.temporaryDirectory)
        store.addFavoriteTag(tag.id, at: 0)
        #expect(store.favorites.first?.tagID == tag.id)
        store.addFavoriteTag(tag.id, at: 2)
        #expect(store.favorites.last?.tagID == tag.id)
        #expect(store.favorites.count == 2)
    }
}

/// お気に入り（「お気に入り」のタグ）と、自分で作るセクション
final class SidebarPlacementTests {
    private let suite = "macorn-sidebar-place-\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("macorn-sidebar-place-\(UUID().uuidString)")
    private let tags: TagStore

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set([[String: String]](), forKey: "sidebarFavorites")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("a"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("b"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: folder.appendingPathComponent("note.txt"))
        tags = TagStore(fileURL: folder.appendingPathComponent("tags.json"))
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: folder)
    }

    private func url(_ name: String) -> URL { folder.appendingPathComponent(name) }

    @Test func favoritesFollowTheFavoritesTag() {
        let store = SidebarStore(defaults: defaults, tags: tags)
        // お気に入りに入れると「お気に入り」のタグが付く（ファイルも入れられる）
        store.addFavorite(url("a"))
        store.addFavorite(url("note.txt"), at: 0)
        #expect(store.favorites.map(\.name) == ["note.txt", "a"])
        #expect(tags.hasTag(TagStore.favoritesID, on: url("a")))

        // ほかの画面でタグを付け外しすると、お気に入りにも反映する
        tags.assign(TagStore.favoritesID, to: [url("b")])
        #expect(store.favorites.map(\.name) == ["note.txt", "a", "b"])
        tags.unassign(TagStore.favoritesID, from: [url("note.txt")])
        #expect(store.favorites.map(\.name) == ["a", "b"])

        // お気に入りから外すとタグも外れる
        store.removeFavorite(url("a"))
        #expect(!tags.hasTag(TagStore.favoritesID, on: url("a")))

        // 移動・改名されたら、同じ位置のまま入れ替える
        store.renameFavorite(url("b"), to: "ビー")
        tags.itemMoved(from: url("b"), to: url("c"))
        #expect(store.favorites.map(\.url.lastPathComponent) == ["c"])
        #expect(store.favorites.first?.name == "ビー")
    }

    @Test func migratesOldFavoritesOnce() {
        defaults.set([["path": url("a").path]], forKey: "sidebarFavorites")
        _ = SidebarStore(defaults: defaults, tags: tags)
        #expect(tags.hasTag(TagStore.favoritesID, on: url("a")))
        // 2回目以降は、タグを外したものを付け直さない
        tags.unassign(TagStore.favoritesID, from: [url("a")])
        let reloaded = SidebarStore(defaults: defaults, tags: tags)
        #expect(reloaded.favorites.isEmpty)
    }

    @Test func customSectionsHoldTagsAndItemsWithoutTagging() throws {
        let store = SidebarStore(defaults: defaults, tags: tags)
        let work = try #require(tags.createTag(named: "仕事"))
        let section = try #require(store.createSection(named: "プロジェクト", before: .tags))
        #expect(store.visibleSections == [.favorites, section, .tags, .locations])

        // フォルダを置いても、タグは付かない
        store.placeURL(url("a"), in: section)
        #expect(store.items(in: section).map(\.name) == ["a"])
        #expect(tags.tags(for: url("a")).isEmpty)

        // 1つのタグは1か所だけ: お気に入りに置いたタグをセクションへ置くと移る
        store.addFavoriteTag(work.id)
        store.placeTag(work.id, in: section, at: 0)
        #expect(!store.containsFavoriteTag(work.id))
        #expect(store.items(in: section).map(\.name) == ["仕事", "a"])
        #expect(store.placement(ofTag: work.id) == section)

        // 保存され、次に開いたときも同じ
        guard case .custom(let id) = section else { return }
        store.renameSection(id, to: "案件")
        let reloaded = SidebarStore(defaults: defaults, tags: tags)
        #expect(reloaded.customSection(id)?.name == "案件")
        #expect(reloaded.items(in: section).map(\.name) == ["仕事", "a"])

        // セクションを削除しても、項目やタグはそのまま
        reloaded.deleteSection(id)
        #expect(reloaded.visibleSections == [.favorites, .tags, .locations])
        #expect(tags.tag(id: work.id) != nil)
    }

    @Test func movesBetweenFavoritesAndSections() throws {
        let store = SidebarStore(defaults: defaults, tags: tags)
        let section = try #require(store.createSection(named: "置き場"))
        store.addFavorite(url("a"))
        // お気に入り → セクション（移動）: お気に入りのタグは外れる
        store.placeURL(url("a"), in: section)
        store.removeItem(id: url("a").standardizedFileURL.path, from: .favorites)
        #expect(store.favorites.isEmpty)
        #expect(!tags.hasTag(TagStore.favoritesID, on: url("a")))
        #expect(store.items(in: section).count == 1)
    }
}
