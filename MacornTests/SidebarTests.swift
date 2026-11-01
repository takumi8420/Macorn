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

    /// 一覧の右クリック「セクションに置く」：置いていなければ置き、すべて置いてあれば外す
    @Test func togglesPlacementFromListMenu() throws {
        let store = SidebarStore(defaults: defaults, tags: tags, createsDefaultSection: false)
        let section = try #require(store.createSection(named: "案件"))
        guard case .custom(let id) = section else { Issue.record("自分で作ったセクションではない"); return }
        let a = URL(fileURLWithPath: "/tmp/macorn-a"), b = URL(fileURLWithPath: "/tmp/macorn-b/")

        FileBrowserViewController.togglePlacement([a], in: id, store: store)
        #expect(FileBrowserViewController.isPlaced(a, in: try #require(store.customSection(id))))

        // 一部だけ置いてあるときは、足りないものを置く（重ねて置かない）
        FileBrowserViewController.togglePlacement([a, b], in: id, store: store)
        var placed = try #require(store.customSection(id))
        #expect(placed.items.count == 2)
        #expect(FileBrowserViewController.isPlaced(b, in: placed))

        // すべて置いてあれば外す
        FileBrowserViewController.togglePlacement([a, b], in: id, store: store)
        placed = try #require(store.customSection(id))
        #expect(placed.items.isEmpty)
    }

    /// サブセクション：作る・入れ子にする・外に出す・削除する。保存して読み直しても同じ
    @Test func subsections() throws {
        let store = SidebarStore(defaults: defaults, tags: tags, createsDefaultSection: false)
        guard case .custom(let project)? = store.createSection(named: "案件"),
              case .custom(let docs)? = store.createSection(named: "資料") else { Issue.record("セクションを作れない"); return }
        let active = try #require(store.createSubsection(named: "進行中", in: project))
        let client = try #require(store.createSubsection(named: "A社", in: active))
        #expect(store.isSubsection(active))
        #expect(store.displayPath(ofSection: client) == "案件 › 進行中 › A社")
        #expect(store.customSectionsInOrder.map(\.name) == ["案件", "進行中", "A社", "資料"])
        // サブセクションはいちばん上の並びには出ない
        #expect(!store.sections.contains(.custom(active)))

        // 中にフォルダを置ける
        let folder = URL(fileURLWithPath: "/tmp/macorn-sub")
        store.placeURL(folder, in: .custom(client))
        #expect(store.customSection(client)?.items.map(\.url.path) == [folder.path])

        // 自分の中・自分のサブセクションの中へは入れられない
        #expect(!store.canNestSection(project, in: client))
        #expect(!store.canNestSection(project, in: project))

        // いちばん上のセクションを、ほかのセクションの中へ入れる
        store.nestSection(docs, in: project, at: 0)
        #expect(store.customSection(docs)?.parentID == project)
        #expect(!store.sections.contains(.custom(docs)))
        #expect(store.customSection(project)?.items.compactMap(\.sectionID) == [docs, active])

        // 保存して読み直しても同じ
        let reloaded = SidebarStore(defaults: defaults, tags: tags, createsDefaultSection: false)
        #expect(reloaded.customSectionsInOrder.map(\.name) == ["案件", "資料", "進行中", "A社"])
        #expect(reloaded.customSection(client)?.items.map(\.url.path) == [folder.path])

        // 外に出すと、いちばん上の並びの最後に入る
        store.unnestSection(active, before: nil)
        #expect(store.sections.last == .custom(active))
        #expect(store.customSection(active)?.parentID == nil)
        #expect(store.customSection(project)?.items.compactMap(\.sectionID) == [docs])

        // 削除すると、中のサブセクションも消える
        store.deleteSection(active)
        #expect(store.customSection(active) == nil)
        #expect(store.customSection(client) == nil)
    }

    @Test func sectionIDsRoundTrip() {
        let id = UUID()
        for section in [SidebarSection.favorites, .tags, .locations, .tag(id), .custom(id)] {
            #expect(SidebarSection(id: section.id) == section)
        }
        #expect(SidebarSection(id: "unknown") == nil)
    }

    @Test func reordersAndHidesSections() {
        let store = SidebarStore(defaults: defaults, tags: tags, createsDefaultSection: false)
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
        let reloaded = SidebarStore(defaults: defaults, tags: tags, createsDefaultSection: false)
        #expect(reloaded.visibleSections == [.locations, .tags])
        reloaded.resetSections()
        #expect(reloaded.visibleSections == SidebarSection.defaultOrder)
    }

    @Test func tagSectionsAndFavoriteTags() throws {
        let tag = try #require(tags.createTag(named: "サイドバーのテスト"))
        let store = SidebarStore(defaults: defaults, tags: tags, createsDefaultSection: false)

        store.addTagSection(tag.id)
        #expect(store.visibleSections == [.favorites, .tag(tag.id), .tags, .locations])
        store.addFavoriteTag(tag.id)
        #expect(store.containsFavoriteTag(tag.id))
        #expect(store.favorites.last?.id == "tag:" + tag.id.uuidString)

        let reloaded = SidebarStore(defaults: defaults, tags: tags, createsDefaultSection: false)
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
        let store = SidebarStore(defaults: defaults, tags: tags, createsDefaultSection: false)
        store.moveSection(.locations, before: .favorites)
        #expect(store.visibleSections == [.locations, .favorites, .tags])
        store.moveSection(.locations, before: .tags)
        #expect(store.visibleSections == [.favorites, .locations, .tags])
    }

    @Test func dropsTagIntoSectionsAndFavorites() throws {
        let tag = try #require(tags.createTag(named: "ドラッグのテスト"))
        let store = SidebarStore(defaults: defaults, tags: tags, createsDefaultSection: false)

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
        let store = SidebarStore(defaults: defaults, tags: tags, createsDefaultSection: false)
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

    @Test func createsDefaultSectionOnce() throws {
        let store = SidebarStore(defaults: defaults, tags: tags)
        let section = try #require(store.customSections.first)
        #expect(store.customSections.count == 1)
        #expect(section.name == SidebarStore.defaultSectionName)
        // お気に入りのすぐ下に置く
        #expect(store.visibleSections == [.favorites, .custom(section.id), .tags, .locations])
        // 次に開いても増えず、削除したら作り直さない
        #expect(SidebarStore(defaults: defaults, tags: tags).customSections.count == 1)
        store.deleteSection(section.id)
        #expect(SidebarStore(defaults: defaults, tags: tags).customSections.isEmpty)
    }

    @Test func migratesOldFavoritesOnce() {
        defaults.set([["path": url("a").path]], forKey: "sidebarFavorites")
        _ = SidebarStore(defaults: defaults, tags: tags, createsDefaultSection: false)
        #expect(tags.hasTag(TagStore.favoritesID, on: url("a")))
        // 2回目以降は、タグを外したものを付け直さない
        tags.unassign(TagStore.favoritesID, from: [url("a")])
        let reloaded = SidebarStore(defaults: defaults, tags: tags, createsDefaultSection: false)
        #expect(reloaded.favorites.isEmpty)
    }

    @Test func customSectionsHoldTagsAndItemsWithoutTagging() throws {
        let store = SidebarStore(defaults: defaults, tags: tags, createsDefaultSection: false)
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
        let reloaded = SidebarStore(defaults: defaults, tags: tags, createsDefaultSection: false)
        #expect(reloaded.customSection(id)?.name == "案件")
        #expect(reloaded.items(in: section).map(\.name) == ["仕事", "a"])

        // セクションを削除しても、項目やタグはそのまま
        reloaded.deleteSection(id)
        #expect(reloaded.visibleSections == [.favorites, .tags, .locations])
        #expect(tags.tag(id: work.id) != nil)
    }

    @Test func movesBetweenFavoritesAndSections() throws {
        let store = SidebarStore(defaults: defaults, tags: tags, createsDefaultSection: false)
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
