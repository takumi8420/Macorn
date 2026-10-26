import Foundation
import Testing
@testable import Macorn

/// サイドバーの構成（セクションの順番・表示・タグのセクション、お気に入りのタグ）。
/// 普段の設定を汚さないよう、テスト用の保存先を使う。
final class SidebarStoreTests {
    private let suite = "macorn-sidebar-\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set([[String: String]](), forKey: "sidebarFavorites")
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suite)
    }

    @Test func sectionIDsRoundTrip() {
        let id = UUID()
        for section in [SidebarSection.favorites, .tags, .locations, .tag(id)] {
            #expect(SidebarSection(id: section.id) == section)
        }
        #expect(SidebarSection(id: "unknown") == nil)
    }

    @Test func reordersAndHidesSections() {
        let store = SidebarStore(defaults: defaults)
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
        let reloaded = SidebarStore(defaults: defaults)
        #expect(reloaded.visibleSections == [.locations, .tags])
        reloaded.resetSections()
        #expect(reloaded.visibleSections == SidebarSection.defaultOrder)
    }

    @Test func tagSectionsAndFavoriteTags() throws {
        let tag = try #require(TagStore.shared.createTag(named: "サイドバーのテスト-\(UUID().uuidString.prefix(6))"))
        defer { TagStore.shared.deleteTag(tag.id) }
        let store = SidebarStore(defaults: defaults)

        store.addTagSection(tag.id)
        #expect(store.visibleSections == [.favorites, .tag(tag.id), .tags, .locations])
        store.addFavoriteTag(tag.id)
        #expect(store.containsFavoriteTag(tag.id))
        #expect(store.favorites.last?.id == "tag:" + tag.id.uuidString)

        let reloaded = SidebarStore(defaults: defaults)
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

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set([[String: String]](), forKey: "sidebarFavorites")
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suite)
    }

    @Test func payloadRoundTrip() {
        let id = UUID()
        #expect(SidebarDragPayload(SidebarDragPayload.tag(id).string) == .tag(id))
        #expect(SidebarDragPayload(SidebarDragPayload.section(.locations).string) == .section(.locations))
        #expect(SidebarDragPayload("/Users/someone/file.txt") == nil)
    }

    @Test func movesSectionBeforeTarget() {
        let store = SidebarStore(defaults: defaults)
        store.moveSection(.locations, before: .favorites)
        #expect(store.visibleSections == [.locations, .favorites, .tags])
        store.moveSection(.locations, before: .tags)
        #expect(store.visibleSections == [.favorites, .locations, .tags])
    }

    @Test func dropsTagIntoSectionsAndFavorites() throws {
        let tag = try #require(TagStore.shared.createTag(named: "ドラッグのテスト-\(UUID().uuidString.prefix(6))"))
        defer { TagStore.shared.deleteTag(tag.id) }
        let store = SidebarStore(defaults: defaults)

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
