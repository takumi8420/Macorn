import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [BrowserWindowController] = []
    private var closedTabs: [URL] = []
    private var isTerminating = false

    private var homeURL: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// ユニットテストの実行中は、ウィンドウを開かず前回の状態も上書きしない。
    private let isRunningTests = NSClassFromString("XCTestCase") != nil
        || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 旧名 noxy の設定・履歴を引き継ぐ（メニューのショートカットの変更も含むので、メニューを作る前に行う）
        if !isRunningTests && !DebugFlags.isAutomating { LegacyMigration.runIfNeeded() }
        Theme.shared.apply()
        NSApp.mainMenu = MainMenu.build()
        ShortcutStore.apply(to: NSApp.mainMenu)
        guard !isRunningTests else { return }
        // 自動操作では前回のウィンドウを開かない（利用者のフォルダを映さず、毎回同じ状態から始めるため）
        if DebugFlags.isAutomating || !restoreSession() {
            openWindow(at: homeURL)
        }
        // DMG の中などから開いたら「アプリケーション」へ移すかを尋ねる（移すなら開き直すので、ほかは何もしない）
        if AppMover.offerIfNeeded() { return }
        if !DebugFlags.isAutomating {
            NSApp.activate()
            UpdateChecker.checkOnLaunch()
        }
        #if DEBUG
        DebugAutomation.runIfRequested { [weak self] in self?.controllers ?? [] }
        #endif
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openWindow(at: homeURL) }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        // テストと自動操作では、利用者の前回のウィンドウを上書きしない
        guard !isRunningTests, !DebugFlags.isAutomating else { return }
        saveSession()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - ウィンドウとタブ

    @discardableResult
    private func openWindow(at url: URL, frame: NSRect? = nil) -> BrowserWindowController {
        openWindow(layout: PaneLayout(paths: [url.path]), frame: frame)
    }

    @discardableResult
    private func openWindow(layout: PaneLayout, frame: NSRect? = nil) -> BrowserWindowController {
        let controller = makeController(layout: layout)
        guard let window = controller.window else { return controller }
        if let frame {
            window.setFrame(frame, display: false)
        } else if let keyWindow = NSApp.keyWindow {
            window.setFrameTopLeftPoint(keyWindow.cascadeTopLeft(from: NSPoint(x: keyWindow.frame.minX, y: keyWindow.frame.maxY)))
        } else {
            window.center()
        }
        controller.showWindow(nil)
        return controller
    }

    @discardableResult
    private func openTab(at url: URL, besides host: BrowserWindowController) -> BrowserWindowController {
        let controller = makeController(url: url)
        guard let hostWindow = host.window, let window = controller.window else { return controller }
        hostWindow.addTabbedWindow(window, ordered: .above)
        window.makeKeyAndOrderFront(nil)
        return controller
    }

    /// ほかのアプリから渡されたフォルダを、今のウィンドウの新しいタブ（ウィンドウがなければ新しいウィンドウ）で開く。
    /// そのフォルダをすでに表示しているタブがあれば、新しいタブは作らずにそれを前に出す
    private func openFromOutside(_ folder: URL) -> BrowserWindowController {
        let wanted = FileBrowserViewController.comparablePath(folder)
        if let existing = controllers.first(where: { FileBrowserViewController.comparablePath($0.browser.state.currentURL) == wanted }) {
            existing.window?.makeKeyAndOrderFront(nil)
            return existing
        }
        if let host = keyController ?? controllers.last {
            return openTab(at: folder, besides: host)
        }
        return openWindow(at: folder)
    }

    private func makeController(url: URL) -> BrowserWindowController {
        makeController(layout: PaneLayout(paths: [url.path]))
    }

    private func makeController(layout: PaneLayout) -> BrowserWindowController {
        let controller = BrowserWindowController(layout: layout)
        controller.appDelegate = self
        controllers.append(controller)
        return controller
    }

    private var keyController: BrowserWindowController? {
        controllers.first { $0.window?.isKeyWindow == true }
            ?? controllers.first { $0.window?.isMainWindow == true }
    }

    @objc func newWindow(_ sender: Any?) {
        openWindow(at: homeURL)
    }

    @objc func reopenClosedTab(_ sender: Any?) {
        guard let url = closedTabs.popLast() else { return }
        if let host = keyController {
            openTab(at: url, besides: host)
        } else {
            openWindow(at: url)
        }
    }

    @objc func toggleHiddenFiles(_ sender: Any?) {
        Preferences.showHiddenFiles.toggle()
    }

    /// 表示 › 並び順。同じ基準をもう一度選ぶと、昇順・降順を入れ替える
    @objc func sortBy(_ sender: Any?) {
        guard let raw = (sender as? NSMenuItem)?.representedObject as? String, let key = FileSortKey(rawValue: raw) else { return }
        let current = Preferences.sort
        Preferences.sort = FileSort(key: key, ascending: current.key == key ? !current.ascending : true)
    }

    @objc func toggleSortDirection(_ sender: Any?) {
        var sort = Preferences.sort
        sort.ascending.toggle()
        Preferences.sort = sort
    }

    @objc func checkForUpdates(_ sender: Any?) {
        UpdateChecker.checkManually()
    }

    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.show()
    }

    // MARK: - ほかのアプリやコマンドラインから開く（要件 K-04: `macorn .`）

    /// フォルダはその中を開き、ファイルは入っているフォルダを開いて選ぶ。
    /// 設定で Macorn をフォルダの既定のアプリ・「Finder に表示」の行き先にしたときも、この経路で届く。
    /// 同じフォルダのファイルは1つのタブにまとめて、全部を選ぶ。
    func application(_ application: NSApplication, open urls: [URL]) {
        var folders: [URL] = []
        var filesByFolder: [URL: [URL]] = [:]
        for url in urls where url.isFileURL {
            if FileTransfer.isDirectory(url) && url.pathExtension != "app" {
                folders.append(url)
            } else {
                let folder = url.deletingLastPathComponent().standardizedFileURL
                if filesByFolder[folder] == nil { folders.append(folder) }
                filesByFolder[folder, default: []].append(url)
            }
        }
        for folder in folders {
            let controller = openFromOutside(folder)
            if let files = filesByFolder[folder] {
                // 1つのプレビューできるファイルなら、プレビューを切っていても出す（Macorn で「開いた」ので）
                if files.count == 1, FilePreviewController.kind(for: files[0]) != nil {
                    controller.browser.pinnedPreviewURL = files[0]
                }
                controller.browser.navigate(to: folder, selectingAll: files)
            }
        }
        // 自動操作ではほかのアプリでの入力を奪わない
        if !DebugFlags.isAutomating { NSApp.activate() }
    }

    @objc func installCommandLineTool(_ sender: Any?) {
        CommandLineTool.install()
    }

    // MARK: - 前回のウィンドウ・タブの復元（要件 N-09）

    private struct SavedWindow: Codable {
        var frame: String
        /// タブごとの画面構成（2画面の左右のフォルダ・操作対象の側）
        var tabs: [PaneLayout]
        var selectedIndex: Int
    }

    private static let sessionKey = "savedWindows.v2"

    private func saveSession() {
        var saved: [SavedWindow] = []
        var seen = Set<ObjectIdentifier>()
        // 奥のウィンドウから順に保存し、復元時に最前面のウィンドウが一番上に来るようにする
        for window in NSApp.orderedWindows.reversed() {
            guard window.windowController is BrowserWindowController,
                  !seen.contains(ObjectIdentifier(window)) else { continue }
            let group = window.tabGroup?.windows ?? [window]
            group.forEach { seen.insert(ObjectIdentifier($0)) }
            let tabs = group.compactMap { ($0.windowController as? BrowserWindowController)?.panes.layout }
            guard !tabs.isEmpty else { continue }
            let selected = window.tabGroup?.selectedWindow.flatMap { group.firstIndex(of: $0) } ?? 0
            saved.append(SavedWindow(frame: NSStringFromRect(window.frame), tabs: tabs, selectedIndex: selected))
        }
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: Self.sessionKey)
        }
    }

    private func restoreSession() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: Self.sessionKey),
              let saved = try? JSONDecoder().decode([SavedWindow].self, from: data) else { return false }

        var restoredAny = false
        for savedWindow in saved {
            // 消えたフォルダは除く。画面が1つも残らないタブは開かない
            let layouts: [PaneLayout] = savedWindow.tabs.compactMap { $0.pruned(keeping: TagLocation.exists) }
            guard let first = layouts.first else { continue }

            let host = openWindow(layout: first, frame: NSRectFromString(savedWindow.frame))
            var tabControllers = [host]
            for layout in layouts.dropFirst() {
                let controller = makeController(layout: layout)
                if let hostWindow = host.window, let window = controller.window {
                    hostWindow.addTabbedWindow(window, ordered: .above)
                    tabControllers.append(controller)
                }
            }
            let index = min(max(savedWindow.selectedIndex, 0), tabControllers.count - 1)
            tabControllers[index].window?.makeKeyAndOrderFront(nil)
            restoredAny = true
        }
        return restoredAny
    }
}

// MARK: - BrowserWindowControllerDelegate

extension AppDelegate: BrowserWindowControllerDelegate {
    func windowControllerRequestsNewTab(_ controller: BrowserWindowController, url: URL) {
        openTab(at: url, besides: controller)
    }

    func windowControllerDidClose(_ controller: BrowserWindowController) {
        controllers.removeAll { $0 === controller }
        if !isTerminating {
            closedTabs.append(controller.browser.state.currentURL)
        }
    }
}

// MARK: - メニューの有効・無効

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleHiddenFiles(_:)):
            menuItem.state = Preferences.showHiddenFiles ? .on : .off
            return true
        case #selector(reopenClosedTab(_:)):
            return !closedTabs.isEmpty
        case #selector(sortBy(_:)):
            menuItem.state = (menuItem.representedObject as? String) == Preferences.sort.key.rawValue ? .on : .off
            return true
        case #selector(toggleSortDirection(_:)):
            menuItem.state = Preferences.sort.ascending ? .off : .on
            return true
        default:
            return true
        }
    }
}
