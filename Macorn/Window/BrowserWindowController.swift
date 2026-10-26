import AppKit
import SwiftUI

protocol BrowserWindowControllerDelegate: AnyObject {
    func windowControllerRequestsNewTab(_ controller: BrowserWindowController, url: URL)
    func windowControllerDidClose(_ controller: BrowserWindowController)
}

extension NSToolbarItem.Identifier {
    static let back = NSToolbarItem.Identifier("macorn.back")
    static let forward = NSToolbarItem.Identifier("macorn.forward")
    static let parent = NSToolbarItem.Identifier("macorn.parent")
    static let split = NSToolbarItem.Identifier("macorn.split")
    static let favorite = NSToolbarItem.Identifier("macorn.favorite")
}

/// 1つのウィンドウ（= 1つのタブ）。サイドバーと、1つまたは2つの画面を並べる。
final class BrowserWindowController: NSWindowController {
    static let tabbingIdentifier = "macorn.browser"

    let panes: PaneContainerViewController
    weak var appDelegate: BrowserWindowControllerDelegate?
    private let textUndoManager = UndoManager()

    /// 操作対象の画面（2画面のときは、最後にクリック・フォーカスした側）
    var browser: FileBrowserViewController { panes.activePane }

    convenience init(url: URL) {
        self.init(layout: PaneLayout(paths: [url.path]))
    }

    init(layout: PaneLayout) {
        panes = PaneContainerViewController(layout: layout)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 560, height: 320)
        window.tabbingIdentifier = Self.tabbingIdentifier
        window.tabbingMode = .automatic
        window.isRestorable = false
        window.toolbarStyle = .unified

        super.init(window: window)

        panes.setPaneDelegate(self)
        panes.onActivePaneChanged = { [weak self] in
            guard let self else { return }
            updateTitle(for: browser.state.currentURL)
        }
        window.delegate = self

        let sidebar = SidebarViewController(window: panes.model) { [weak self] url in
            // ファイル（タグのセクションの項目など）なら、その場所へ移動して選ぶ
            if url.isFileURL, FileManager.default.fileExists(atPath: url.path), !FileTransfer.isDirectory(url) {
                self?.browser.navigate(to: url.deletingLastPathComponent(), selecting: url)
            } else {
                self?.browser.navigate(to: url)
            }
        }

        let splitViewController = NSSplitViewController()
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 160
        sidebarItem.maximumThickness = 320
        sidebarItem.canCollapse = true
        let contentItem = NSSplitViewItem(viewController: panes)
        contentItem.minimumThickness = 360
        splitViewController.addSplitViewItem(sidebarItem)
        splitViewController.addSplitViewItem(contentItem)

        window.contentViewController = splitViewController
        // contentViewController を設定するとウィンドウが中身の大きさに縮むので、元に戻す
        window.setContentSize(NSSize(width: 1000, height: 640))

        let toolbar = NSToolbar(identifier: "macorn.browserToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar

        updateTitle(for: browser.state.currentURL)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateTitle(for url: URL) {
        guard let window else { return }
        window.title = TagLocation.displayName(for: url)
        window.representedURL = url.isFileURL ? url : nil
        window.toolbar?.validateVisibleItems()
    }

    // MARK: - メニュー・ツールバーの操作

    @objc func goBack(_ sender: Any?) { browser.goBack() }
    @objc func goForward(_ sender: Any?) { browser.goForward() }
    @objc func goToParent(_ sender: Any?) { browser.goToParent() }
    @objc func openSelection(_ sender: Any?) { browser.openSelection() }
    @objc func editPath(_ sender: Any?) { browser.beginEditingPath() }

    @objc func goToHome(_ sender: Any?) { go(to: FileManager.default.homeDirectoryForCurrentUser) }
    @objc func goToDesktop(_ sender: Any?) { go(toDirectory: .desktopDirectory) }
    @objc func goToDocuments(_ sender: Any?) { go(toDirectory: .documentDirectory) }
    @objc func goToDownloads(_ sender: Any?) { go(toDirectory: .downloadsDirectory) }
    @objc func goToApplications(_ sender: Any?) { go(to: URL(fileURLWithPath: "/Applications")) }

    /// ⌃⌘T: 選択中のフォルダ（なければ表示中のフォルダ）をお気に入りに入れる。すべて入っていれば外す
    @objc func addToSidebar(_ sender: Any?) {
        toggleFavorites(favoriteTargets)
    }

    /// ツールバーの ★: 表示中のフォルダをお気に入りに入れる・外す
    @objc func toggleFavoriteFolder(_ sender: Any?) {
        toggleFavorites([browser.state.currentURL])
    }

    /// お気に入りの対象: 選択中の項目（フォルダもファイルも）。何も選んでいなければ表示中のフォルダ
    private var favoriteTargets: [URL] {
        let selected = browser.selectedNodes
        if selected.isEmpty {
            return browser.state.currentURL.isFileURL ? [browser.state.currentURL] : []
        }
        return selected.map(\.url)
    }

    private func toggleFavorites(_ urls: [URL]) {
        let store = SidebarStore.shared
        guard !urls.isEmpty else { return }
        if urls.allSatisfy(store.containsFavorite) {
            urls.forEach { store.removeFavorite($0.standardizedFileURL) }
        } else {
            urls.forEach { store.addFavorite($0) }
        }
        window?.toolbar?.validateVisibleItems()
    }

    // MARK: コマンドパレット（要件 5章）

    @objc func togglePalette(_ sender: Any?) {
        PaletteController.shared.toggle(for: self)
    }

    /// Finder の ⌘K「サーバへ接続」は、パレットに ⌘K を使うためメニューとパレットから開く。
    @objc func connectToServer(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "サーバへ接続"
        alert.informativeText = "サーバのアドレスを入力してください（例: smb://server/share、afp://、nfs://）"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "smb://"
        field.stringValue = AppDefaults.store.string(forKey: "lastServerAddress") ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "接続")
        alert.addButton(withTitle: "キャンセル")
        alert.window.initialFirstResponder = field
        guard let window else { return }
        alert.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated {
                guard response == .alertFirstButtonReturn,
                      let url = URL(string: field.stringValue.trimmingCharacters(in: .whitespaces)),
                      url.scheme != nil else { return }
                AppDefaults.store.set(url.absoluteString, forKey: "lastServerAddress")
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: 2画面（要件 4章）

    @objc func toggleSplit(_ sender: Any?) { panes.toggleSplit() }
    @objc func switchPane(_ sender: Any?) { panes.switchActivePane() }
    @objc func copyToOtherPane(_ sender: Any?) { panes.transferSelectionToOtherPane(mode: .copy) }
    @objc func moveToOtherPane(_ sender: Any?) { panes.transferSelectionToOtherPane(mode: .move) }
    @objc func syncOtherPane(_ sender: Any?) { panes.syncOtherPane() }
    @objc func swapPanes(_ sender: Any?) { panes.swapPanes() }
    @objc func openInLeftPane(_ sender: Any?) { panes.openSelectionInPane(index: 0) }
    @objc func openInRightPane(_ sender: Any?) { panes.openSelectionInPane(index: 1) }

    /// サイドバーなどにフォーカスがあっても、ファイル操作のメニューが操作対象の画面に届くようにする。
    override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
        if browser.responds(to: action) { return browser }
        return super.supplementalTarget(forAction: action, sender: sender)
    }

    override func newWindowForTab(_ sender: Any?) {
        appDelegate?.windowControllerRequestsNewTab(self, url: browser.state.currentURL)
    }

    private func go(toDirectory directory: FileManager.SearchPathDirectory) {
        guard let url = FileManager.default.urls(for: directory, in: .userDomainMask).first else { return }
        go(to: url)
    }

    private func go(to url: URL) {
        browser.navigate(to: url)
    }

    private func isEnabled(_ action: Selector?) -> Bool {
        switch action {
        case #selector(goBack(_:)): browser.state.history.canGoBack
        case #selector(goForward(_:)): browser.state.history.canGoForward
        case #selector(goToParent(_:)): browser.canGoToParent
        case #selector(openSelection(_:)): browser.state.selectedCount > 0
        case #selector(addToSidebar(_:)):
            !favoriteTargets.isEmpty
        case #selector(toggleFavoriteFolder(_:)):
            browser.state.currentURL.isFileURL
        case #selector(copyToOtherPane(_:)), #selector(moveToOtherPane(_:)):
            panes.isSplit && !browser.selectedNodes.isEmpty && !(window?.firstResponder is NSText)
        case #selector(switchPane(_:)), #selector(syncOtherPane(_:)), #selector(swapPanes(_:)):
            panes.isSplit
        default: true
        }
    }
}

// MARK: - 有効・無効の切り替え

extension BrowserWindowController: NSMenuItemValidation, NSToolbarItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleSplit(_:)) {
            menuItem.state = panes.isSplit ? .on : .off
        }
        if menuItem.action == #selector(addToSidebar(_:)) {
            let targets = favoriteTargets
            menuItem.title = !targets.isEmpty && targets.allSatisfy(SidebarStore.shared.containsFavorite) ? "お気に入りから外す" : "お気に入りに追加"
        }
        return isEnabled(menuItem.action)
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        if item.itemIdentifier == .favorite {
            // 表示中のフォルダがお気に入りなら塗りつぶしの ★ にする
            let isFavorite = SidebarStore.shared.containsFavorite(browser.state.currentURL)
            item.image = NSImage(systemSymbolName: isFavorite ? "star.fill" : "star", accessibilityDescription: "お気に入り")
            item.label = isFavorite ? "お気に入りから外す" : "お気に入りに追加"
            item.toolTip = item.label
        }
        return isEnabled(item.action)
    }
}

// MARK: - FileBrowserDelegate

extension BrowserWindowController: FileBrowserDelegate {
    func browser(_ browser: FileBrowserViewController, didNavigateTo url: URL) {
        // タイトルは操作対象の画面のフォルダにする
        if browser === self.browser { updateTitle(for: url) }
    }

    func browser(_ browser: FileBrowserViewController, openInNewTab url: URL) {
        appDelegate?.windowControllerRequestsNewTab(self, url: url)
    }
}

// MARK: - NSWindowDelegate

extension BrowserWindowController: NSWindowDelegate {
    /// ウィンドウに戻ってきたら、ターミナルでの git 操作などを反映する
    func windowDidBecomeKey(_ notification: Notification) {
        panes.panes.forEach { $0.refreshGitStatus() }
    }

    func windowWillClose(_ notification: Notification) {
        panes.panes.forEach { $0.tearDown() }
        appDelegate?.windowControllerDidClose(self)
    }

    /// ファイル操作の取り消しはアプリ全体で1つ。文字の入力中だけは入力欄の取り消しを使う。
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        if window.firstResponder is NSText { return textUndoManager }
        return FileOperationManager.shared.undoManager
    }
}

// MARK: - NSToolbarDelegate

extension BrowserWindowController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .back, .forward, .parent, .flexibleSpace, .favorite, .split]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .back:
            makeItem(itemIdentifier, label: "戻る", symbol: "chevron.left", action: #selector(goBack(_:)))
        case .forward:
            makeItem(itemIdentifier, label: "進む", symbol: "chevron.right", action: #selector(goForward(_:)))
        case .parent:
            makeItem(itemIdentifier, label: "親フォルダ", symbol: "arrow.up", action: #selector(goToParent(_:)))
        case .favorite:
            makeItem(itemIdentifier, label: "お気に入り", symbol: "star", action: #selector(toggleFavoriteFolder(_:)))
        case .split:
            makeItem(itemIdentifier, label: "2画面表示（⌘\\）", symbol: "rectangle.split.2x1", action: #selector(toggleSplit(_:)))
        default:
            nil
        }
    }

    private func makeItem(_ identifier: NSToolbarItem.Identifier, label: String, symbol: String, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.action = action
        item.target = self
        item.isBordered = true
        item.autovalidates = true
        return item
    }
}
