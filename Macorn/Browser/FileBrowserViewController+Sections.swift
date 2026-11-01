import AppKit

/// 右クリックのメニューの「パスをコピー」と「セクションに置く」。
/// セクションはサイドバーの見た目だけのまとまりなので、置いても項目には何も付かない。
extension FileBrowserViewController {
    // MARK: - パスのコピー

    /// 「パスをコピー」（選択中の項目。なければ表示中のフォルダ。⌥⌘C と同じ）
    func pathCopyMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "パスをコピー", action: #selector(copyPath(_:)), keyEquivalent: "")
        item.target = self
        return item
    }

    /// 「ほかの形式でパスをコピー」（~ 形式・リポジトリからの相対パス・シェル用）
    func pathCopyFormatsMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "ほかの形式でパスをコピー", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (title, action) in [
            ("~ 形式（~/…）", #selector(copyTildePath(_:))),
            ("リポジトリからの相対パス", #selector(copyRelativePath(_:))),
            ("シェル用（空白などを囲む）", #selector(copyShellQuotedPath(_:))),
        ] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self
            submenu.addItem(entry)
        }
        item.submenu = submenu
        return item
    }

    // MARK: - セクションに置く

    /// 「セクションに置く」：自分で作ったセクションの一覧（置いてあれば印）と、新しいセクションを作って置く項目
    func sectionMenuItem(for urls: [URL]) -> NSMenuItem {
        let item = NSMenuItem(title: "セクションに置く", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let store = SidebarStore.shared
        // サブセクションは「親 › 子」の名前で、親のすぐ後ろに出す
        for section in store.customSectionsInOrder {
            let entry = NSMenuItem(title: store.displayPath(ofSection: section.id), action: #selector(toggleSectionPlacement(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = SectionPlacement(urls: urls, sectionID: section.id)
            let placed = urls.filter { Self.isPlaced($0, in: section) }.count
            entry.state = placed == urls.count ? .on : placed > 0 ? .mixed : .off
            submenu.addItem(entry)
        }
        if !store.customSections.isEmpty { submenu.addItem(.separator()) }
        let create = NSMenuItem(title: "新しいセクションを作って置く…", action: #selector(placeInNewSection(_:)), keyEquivalent: "")
        create.target = self
        create.representedObject = SectionPlacement(urls: urls, sectionID: nil)
        submenu.addItem(create)
        item.submenu = submenu
        return item
    }

    /// 選んだセクションに置く。すべて置いてあれば外す
    @objc func toggleSectionPlacement(_ sender: NSMenuItem) {
        guard let placement = sender.representedObject as? SectionPlacement, let id = placement.sectionID else { return }
        Self.togglePlacement(placement.urls, in: id, store: SidebarStore.shared)
    }

    /// urls を自分で作ったセクションに置く。すべて置いてあれば外す（メニューの印の付け外しと同じ）
    static func togglePlacement(_ urls: [URL], in id: UUID, store: SidebarStore) {
        guard let section = store.customSection(id) else { return }
        if urls.allSatisfy({ isPlaced($0, in: section) }) {
            for url in urls {
                store.removeItem(id: url.standardizedFileURL.path, from: .custom(id))
            }
        } else {
            for url in urls where !isPlaced(url, in: section) {
                store.placeURL(url, in: .custom(id))
            }
        }
    }

    /// 名前を聞いて新しいセクションを作り、そこに置く
    @objc func placeInNewSection(_ sender: NSMenuItem) {
        guard let placement = sender.representedObject as? SectionPlacement else { return }
        SidebarPrompts.createSection(placing: placement.urls, in: SidebarStore.shared)
    }

    static func isPlaced(_ url: URL, in section: CustomSidebarSection) -> Bool {
        let path = url.standardizedFileURL.path
        return section.items.contains { $0.tagID == nil && $0.url.standardizedFileURL.path == path }
    }
}

/// メニューの項目に持たせる、置くものと置き先
final class SectionPlacement: NSObject {
    let urls: [URL]
    let sectionID: UUID?

    init(urls: [URL], sectionID: UUID?) {
        self.urls = urls
        self.sectionID = sectionID
    }
}
