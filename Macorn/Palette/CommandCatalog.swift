import AppKit

/// メニューの操作を、指定したウィンドウに対して実行する。
/// NSApp.sendAction はキーウインドウに送るため、パレットを閉じた直後などに確実に届けるにはこちらを使う。
enum ActionRouter {
    static func target(for action: Selector, in window: NSWindow?) -> AnyObject? {
        var responder: NSResponder? = window?.firstResponder
        while let current = responder {
            if current.responds(to: action) { return current }
            if let controller = current as? NSWindowController,
               let supplemental = controller.supplementalTarget(forAction: action, sender: nil) as AnyObject? {
                return supplemental
            }
            responder = current.nextResponder
        }
        if let controller = window?.windowController {
            if controller.responds(to: action) { return controller }
            if let supplemental = controller.supplementalTarget(forAction: action, sender: nil) as AnyObject? {
                return supplemental
            }
        }
        if let delegate = window?.delegate as AnyObject?, delegate.responds(to: action) { return delegate }
        return NSApp.target(forAction: action, to: nil, from: nil) as AnyObject?
    }

    static func isEnabled(_ action: Selector, in window: NSWindow?) -> Bool {
        guard let target = target(for: action, in: window) else { return false }
        if let validator = target as? NSMenuItemValidation {
            return validator.validateMenuItem(NSMenuItem(title: "", action: action, keyEquivalent: ""))
        }
        return true
    }

    @discardableResult
    static func send(_ action: Selector, in window: NSWindow?) -> Bool {
        guard let target = target(for: action, in: window), isEnabled(action, in: window) else { return false }
        _ = (target as? NSObject)?.perform(action, with: nil)
        return true
    }
}

/// コマンドパレットに出す操作（メニューのすべての項目）。
struct PaletteCommand {
    var title: String
    /// 「ファイル › 新規フォルダ」のようにメニューの場所を示す
    var menuPath: String
    var action: Selector
    var shortcut: String
    /// 英語名とローマ字（どちらでも探せるように）
    var searchAliases: [String]

    var id: String { NSStringFromSelector(action) + "|" + title }
}

enum CommandCatalog {
    /// 英語でも探せるようにする名前。セレクタ名で引く。
    private static let englishNames: [String: String] = [
        "newWindow:": "New Window",
        "newWindowForTab:": "New Tab",
        "reopenClosedTab:": "Reopen Closed Tab",
        "newFolder:": "New Folder",
        "newFile:": "New File",
        "openSelection:": "Open",
        "renameSelection:": "Rename",
        "duplicate:": "Duplicate",
        "toggleQuickLook:": "Quick Look Preview",
        "moveToTrash:": "Move to Trash Delete",
        "deleteImmediately:": "Delete Immediately",
        "copyToOtherPane:": "Copy to Other Pane",
        "moveToOtherPane:": "Move to Other Pane",
        "addToSidebar:": "Add to Favorites Sidebar Bookmark Star",
        "performClose:": "Close",
        "undo:": "Undo",
        "redo:": "Redo",
        "cut:": "Cut",
        "copy:": "Copy",
        "paste:": "Paste",
        "moveHere:": "Move Item Here",
        "selectAll:": "Select All",
        "toggleHiddenFiles:": "Show Hidden Files Dotfiles",
        "toggleSidebar:": "Toggle Sidebar",
        "toggleSplit:": "Split Dual Pane",
        "splitRight:": "Split Right Pane",
        "splitDown:": "Split Down Pane",
        "closePane:": "Close Pane",
        "switchPane:": "Switch Pane",
        "syncOtherPane:": "Sync Other Pane Same Folder",
        "swapPanes:": "Swap Panes",
        "toggleFullScreen:": "Full Screen",
        "goBack:": "Back",
        "goForward:": "Forward",
        "goToParent:": "Enclosing Folder Parent Up",
        "openInLeftPane:": "Open in Left Pane",
        "openInRightPane:": "Open in Right Pane",
        "goToHome:": "Home",
        "goToDesktop:": "Desktop",
        "goToDocuments:": "Documents",
        "goToDownloads:": "Downloads",
        "goToApplications:": "Applications",
        "editPath:": "Go to Folder Path",
        "connectToServer:": "Connect to Server",
        "openInTerminal:": "Open in Terminal",
        "openInEditor:": "Open in Editor",
        "openRepositoryInEditor:": "Open Repository Root in Editor",
        "copyPath:": "Copy Path",
        "beginFilter:": "Filter Find Search",
        "editTags:": "Edit Tags Label",
        "zoomInPreview:": "Zoom In Preview",
        "zoomOutPreview:": "Zoom Out Preview",
        "resetPreviewZoom:": "Actual Size Reset Zoom Preview",
        "sortBy:": "Sort By Order",
        "toggleSortDirection:": "Sort Descending Ascending Reverse",
        "toggleFilePreview:": "Preview Markdown HTML",
        "toggleFavoriteFolder:": "Favorite Star Bookmark",
        "bulkRename:": "Batch Rename Multiple",
        "makeSymbolicLink:": "Make Symbolic Link Symlink Alias",
        "compress:": "Compress Zip Archive",
        "expandArchive:": "Expand Unzip Extract Archive",
        "showInfo:": "Get Info Inspector Properties",
        "copyTildePath:": "Copy Path with Tilde",
        "copyRelativePath:": "Copy Relative Path from Git Root",
        "showChanges:": "Show Changes Git Diff",
        "copyShellQuotedPath:": "Copy Shell Quoted Path",
        "showSettings:": "Settings Preferences",
        "terminate:": "Quit",
        "hide:": "Hide",
        "performMiniaturize:": "Minimize",
        "performZoom:": "Zoom",
    ]

    /// パレットに出さない操作（パレット自身など）
    private static let excluded: Set<String> = ["togglePalette:", "orderFrontStandardAboutPanel:", "arrangeInFront:", "unhideAllApplications:", "hideOtherApplications:"]

    static func commands(menu: NSMenu? = NSApp.mainMenu, window: NSWindow?) -> [PaletteCommand] {
        var result: [PaletteCommand] = []
        collect(menu, path: [], window: window, into: &result)
        return result
    }

    private static func collect(_ menu: NSMenu?, path: [String], window: NSWindow?, into result: inout [PaletteCommand]) {
        for item in menu?.items ?? [] {
            if item.isSeparatorItem || item.isHidden { continue }
            if let submenu = item.submenu {
                // サービスメニューとウインドウ一覧は出さない
                if submenu == NSApp.servicesMenu { continue }
                let title = path.isEmpty ? submenu.title : item.title
                collect(submenu, path: path + [title], window: window, into: &result)
                continue
            }
            guard let action = item.action else { continue }
            let name = NSStringFromSelector(action)
            guard !excluded.contains(name), name != "makeKeyAndOrderFront:" else { continue }
            guard ActionRouter.isEnabled(action, in: window) else { continue }

            let title = item.title.replacingOccurrences(of: "…", with: "")
            var aliases = [Romaji.transcribe(title)]
            if let english = englishNames[name] { aliases.append(english) }
            result.append(PaletteCommand(
                title: title,
                menuPath: path.joined(separator: " › "),
                action: action,
                shortcut: shortcutText(for: item),
                searchAliases: aliases
            ))
        }
    }

    /// メニューのショートカットを「⇧⌘N」のような表記にする。
    static func shortcutText(for item: NSMenuItem) -> String {
        guard !item.keyEquivalent.isEmpty else { return "" }
        let flags = item.keyEquivalentModifierMask
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        let key = item.keyEquivalent
        let scalar = key.unicodeScalars.first.map { Int($0.value) } ?? 0
        switch scalar {
        case NSUpArrowFunctionKey: text += "↑"
        case NSDownArrowFunctionKey: text += "↓"
        case NSLeftArrowFunctionKey: text += "←"
        case NSRightArrowFunctionKey: text += "→"
        case NSBackspaceCharacter: text += "⌫"
        case NSF5FunctionKey: text += "F5"
        case NSF6FunctionKey: text += "F6"
        case 13: text += "↩"
        default: text += key.uppercased()
        }
        return text
    }
}
