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
