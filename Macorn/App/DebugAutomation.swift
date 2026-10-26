#if DEBUG
import AppKit
import Quartz

/// 開発用: 環境変数で操作手順を渡すと、自動で操作しながらウィンドウの画像を保存する。
/// 画面収録の許可なしで見た目を確認するためのもの（Release ビルドには含まれない）。
///
///   MACORN_DEBUG_STEPS="go:/tmp;wait:1;snap:list;parent;snap:parent"
///   MACORN_DEBUG_OUT=/path/to/dir
///
/// 手順: go:<パス> / parent / back / forward / hidden / editpath:<入力> / tab:<補完前の入力>
///       expand / select:<名前> / newtab / wait:<秒> / snap:<名前> / quit
enum DebugAutomation {
    static func runIfRequested(controllers: @escaping () -> [BrowserWindowController]) {
        let env = ProcessInfo.processInfo.environment
        guard let script = env["MACORN_DEBUG_STEPS"], let out = env["MACORN_DEBUG_OUT"] else { return }
        let steps = script.split(separator: ";").map(String.init)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            for step in steps {
                await run(step, outDir: URL(fileURLWithPath: out), controllers: controllers)
                try? await Task.sleep(for: .milliseconds(600))
            }
        }
    }

    private static func run(_ step: String, outDir: URL, controllers: () -> [BrowserWindowController]) async {
        let parts = step.split(separator: ":", maxSplits: 1).map(String.init)
        let command = parts[0]
        let argument = parts.count > 1 ? parts[1] : ""
        guard let controller = controllers().first(where: { $0.window?.isKeyWindow == true }) ?? controllers().first else {
            print("[debug] no window")
            return
        }
        let browser = controller.browser
        print("[debug] step \(step)")

        switch command {
        case "go": browser.navigate(to: URL(fileURLWithPath: argument))
        case "parent": browser.goToParent()
        case "back": browser.goBack()
        case "forward": browser.goForward()
        case "hidden": Preferences.showHiddenFiles.toggle()
        case "editpath": browser.beginEditingPath()
        case "type":
            if let editor = controller.window?.firstResponder as? NSTextView {
                editor.string = argument
            }
        case "tab":
            if let editor = controller.window?.firstResponder as? NSTextView {
                editor.doCommand(by: #selector(NSResponder.insertTab(_:)))
                print("[debug] field=\(editor.string)")
            }
        case "enter":
            if let editor = controller.window?.firstResponder as? NSTextView {
                editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
            }
        case "expand": browser.debugExpandFirstFolder()
        case "select": browser.debugSelect(name: argument)
        case "open": browser.openSelection()
        case "newtab": controller.newWindowForTab(nil)
        case "wait": try? await Task.sleep(for: .seconds(Double(argument) ?? 1))
        case "snap": snapshot(controller.window, to: outDir.appendingPathComponent("\(argument).png"))
        case "sidebar":
            let store = SidebarStore.shared
            print("[debug] favorites=\(store.favorites.map(\.name)) volumes=\(store.volumes.map(\.name))")
            if let split = controller.contentViewController as? NSSplitViewController,
               let sidebarView = split.splitViewItems.first?.viewController.view {
                print("[debug] sidebar frame=\(sidebarView.frame) collapsed=\(split.splitViewItems[0].isCollapsed)")
                if let table = sidebarView.firstDescendant(of: NSTableView.self) {
                    print("[debug] sidebar rows=\(table.numberOfRows) selected=\(table.selectedRow) tableFrame=\(table.frame)")
                } else {
                    print("[debug] sidebar has no table")
                }
                snapshotView(sidebarView, to: outDir.appendingPathComponent("sidebar.png"))
            }
        case "state":
            let s = browser.state
            print("[debug] state path=\(s.currentURL.path) items=\(s.itemCount) selected=\(s.selectedCount) back=\(s.history.canGoBack) forward=\(s.history.canGoForward) editing=\(s.isEditingPath) error=\(s.error?.message ?? "-") key=\(controller.window?.isKeyWindow == true) active=\(NSApp.isActive) windows=\(controllers().count) title=\(controller.window?.title ?? "")")
        case "mkfile":
            // 外部での変更を再現する（監視による自動反映の確認用）
            FileManager.default.createFile(atPath: browser.state.currentURL.appendingPathComponent(argument).path, contents: Data())
        case "action":
            // メニューと同じ経路（ファーストレスポンダから順に探す）で操作を送る
            perform(NSSelectorFromString(argument), in: controller)
        case "key":
            sendKey(argument, to: controller)
        case "conflict":
            let choices: [String: FileOperationManager.ConflictChoice] = ["keepBoth": .keepBoth, "replace": .replace, "skip": .skip, "stop": .stop]
            FileOperationManager.shared.debugConflictChoice = choices[argument]
        case "confirmdelete":
            FileOperationManager.shared.debugConfirmDeletion = argument == "true"
        case "ls":
            let path = argument.hasPrefix("/") ? argument : browser.state.currentURL.appendingPathComponent(argument).path
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).filter { $0 != ".DS_Store" }.sorted()
            print("[debug] ls \((path as NSString).lastPathComponent): \(names)")
        case "selected":
            print("[debug] selected=\(browser.selectedNodes.map(\.entry.name)) firstResponder=\(type(of: controller.window?.firstResponder as Any))")
        case "clip":
            print("[debug] clip=\(FileClipboard.fileURLs.map(\.lastPathComponent)) cut=\(FileClipboard.isCut)")
        case "panel":
            print("[debug] panel visible=\(OperationsPanelController.shared.isPanelVisible) running=\(OperationsPanelController.shared.store.operations.count)")
        case "snappanel":
            if let panel = NSApp.windows.first(where: { $0.title == "ファイル操作" && $0.isVisible }) {
                snapshot(panel, to: outDir.appendingPathComponent("\(argument).png"))
            }
        case "ql":
            let visible = QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
            let current = visible ? (QLPreviewPanel.shared()?.currentPreviewItem as? NSURL)?.lastPathComponent ?? "-" : "-"
            print("[debug] quicklook visible=\(visible) current=\(current) controller=\(String(describing: QLPreviewPanel.shared()?.dataSource)) selected=\(browser.selectedNodes.map(\.entry.name)) fr=\(String(describing: controller.window?.firstResponder))")
        case "cancelall":
            OperationsPanelController.shared.store.operations.forEach { $0.cancel() }
        case "progress":
            for operation in OperationsPanelController.shared.store.operations {
                print("[debug] progress \(operation.title) \(operation.completedBytes)/\(operation.totalBytes) \(operation.currentName)")
            }
        case "palette":
            PaletteController.shared.open(for: controller, query: argument)
        case "snappalette":
            if let panel = NSApp.windows.first(where: { $0 is PalettePanel && $0.isVisible }) {
                snapshot(panel, to: outDir.appendingPathComponent("\(argument).png"))
            }
        case "snapsheet":
            if let sheet = controller.window?.attachedSheet {
                snapshot(sheet, to: outDir.appendingPathComponent("\(argument).png"))
            } else {
                print("[debug] no sheet")
            }
        case "closesheet":
            if let sheet = controller.window?.attachedSheet { controller.window?.endSheet(sheet) }
        case "snapinfo":
            if let panel = NSApp.windows.first(where: { $0.title.hasSuffix("の情報") && $0.isVisible }) {
                snapshot(panel, to: outDir.appendingPathComponent("\(argument).png"))
            }
        case "selectall":
            browser.outlineView.selectAll(nil)
        case "ptype":
            PaletteController.shared.model?.query = argument
        case "pdown":
            PaletteController.shared.model?.moveSelection(by: Int(argument) ?? 1)
        case "pitems":
            let model = PaletteController.shared.model
            let items = model?.items.prefix(Int(argument) ?? 6).map { "\($0.title) [\($0.detail)]" } ?? []
            print("[debug] palette query=\(model?.query ?? "-") hidden=\(Preferences.showHiddenFiles) visible=\(PaletteController.shared.isVisible) mode=\(String(describing: model?.mode)) selected=\(model?.selectedIndex ?? -1) items=\(items)")
        case "penter":
            var flags: NSEvent.ModifierFlags = []
            if argument.contains("cmd") { flags.insert(.command) }
            if argument.contains("opt") { flags.insert(.option) }
            if argument.contains("shift") { flags.insert(.shift) }
            PaletteController.shared.execute(modifiers: flags)
        case "pastebuffer":
            print("[debug] pasteboard=\(NSPasteboard.general.string(forType: .string) ?? "-")")
        case "git":
            print("[debug] git branch=\(browser.state.gitBranch ?? "-") changes=\(browser.state.gitChangeCount) statuses=\(browser.selectedNodes.map { "\($0.entry.name)=\(String(describing: browser.gitSnapshot?.status(for: $0.url)))" })")
        case "filter":
            browser.setFilter(argument)
        case "vim":
            Preferences.vimKeyBindings = argument == "on"
        case "sizes":
            let rows = (0..<browser.outlineView.numberOfRows).compactMap { browser.outlineView.item(atRow: $0) as? FileNode }
            print("[debug] rows=\(rows.map { "\($0.entry.name)=\($0.entry.size.map(String.init) ?? "-")" }) filtering=\(browser.state.isFiltering) text=\(browser.state.filterText) visible=\(browser.state.visibleCount)/\(browser.state.itemCount)")
        case "tagcreate":
            TagStore.shared.createTag(named: argument)
        case "tagassign":
            if let tag = TagStore.shared.tag(named: argument) { TagStore.shared.assign(tag.id, to: browser.selectedURLs) }
        case "tagview":
            if let tag = TagStore.shared.tag(named: argument) { browser.navigate(to: TagLocation.url(for: tag.id)) }
        case "tags":
            let store = TagStore.shared
            print("[debug] tags=\(store.sortedTags.map { "\($0.name)(\(store.count(for: $0.id)))" }) selected=\(browser.selectedNodes.map { "\($0.entry.name):\(store.tags(for: $0.url).map(\.name))" })")
        case "paths":
            print("[debug] selectedPaths=\(browser.selectedNodes.map(\.url.path))")
        case "snappopover":
            if let window = browser.tagPopover?.contentViewController?.view.window {
                print("[debug] popover shown=\(browser.tagPopover?.isShown ?? false)")
                snapshot(window, to: outDir.appendingPathComponent("\(argument).png"))
            } else {
                print("[debug] no popover")
            }
        case "favs":
            print("[debug] favorites=\(SidebarStore.shared.favorites.map { $0.name + ($0.isMissing ? "(missing)" : "") })")
        case "favrename":
            let parts = argument.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2, let item = SidebarStore.shared.favorites.first(where: { $0.url.lastPathComponent == parts[0] }) {
                SidebarStore.shared.renameFavorite(item.url, to: parts[1])
            }
        case "toolbar":
            controller.window?.toolbar?.validateVisibleItems()
            let star = controller.window?.toolbar?.items.first { $0.itemIdentifier == .favorite }
            print("[debug] star=\(star?.label ?? "-")")
        case "pane":
            let panes = controller.panes
            print("[debug] pane split=\(panes.isSplit) active=\(panes.activeIndex) paths=\(panes.panes.map(\.state.currentURL.lastPathComponent)) selected=\(panes.panes.map { $0.selectedNodes.map(\.entry.name) }) title=\(controller.window?.title ?? "")")
        case "columns":
            for pane in controller.panes.panes {
                let outline = pane.outlineView
                print("[debug] columns \(outline.tableColumns.map { "\($0.identifier.rawValue)=\(Int($0.width))\($0.isHidden ? "(hidden)" : "")" }) outline=\(Int(outline.frame.width)) clip=\(Int(outline.enclosingScrollView?.contentView.bounds.width ?? 0))")
            }
        case "activate":
            controller.panes.setActive(index: Int(argument) ?? 0, focus: true)
        case "width":
            if let window = controller.window, let width = Double(argument) {
                var frame = window.frame
                frame.size.width = width
                window.setFrame(frame, display: true)
            }
        case "focus":
            browser.focusList()
        case "quit": NSApp.terminate(nil)
        default: print("[debug] unknown step \(step)")
        }
    }

    private static func perform(_ action: Selector, in controller: BrowserWindowController) {
        guard let window = controller.window else { return }
        var responder: NSResponder? = window.firstResponder
        var target: AnyObject?
        while let current = responder, target == nil {
            if current.responds(to: action) {
                target = current
            } else if let windowController = current as? NSWindowController,
                      let supplemental = windowController.supplementalTarget(forAction: action, sender: nil) as AnyObject? {
                target = supplemental
            }
            responder = current.nextResponder
        }
        if target == nil, controller.responds(to: action) { target = controller }
        if target == nil { target = NSApp.target(forAction: action, to: nil, from: nil) as AnyObject? }
        guard let target else {
            print("[debug] no target for \(action)")
            return
        }
        let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
        if let validator = target as? NSMenuItemValidation, !validator.validateMenuItem(item) {
            print("[debug] \(action) is disabled")
            return
        }
        _ = (target as? NSObject)?.perform(action, with: nil)
    }

    /// 例: "return", "space", "cmd+delete", "cmd+opt+delete", "cmd+shift+n"
    private static func sendKey(_ spec: String, to controller: BrowserWindowController) {
        guard let window = controller.window else { return }
        var parts = spec.split(separator: "+").map(String.init)
        let keyName = parts.removeLast()
        var flags: NSEvent.ModifierFlags = []
        for part in parts {
            switch part {
            case "cmd": flags.insert(.command)
            case "shift": flags.insert(.shift)
            case "opt": flags.insert(.option)
            case "ctrl": flags.insert(.control)
            default: break
            }
        }
        let keys: [String: (UInt16, String)] = [
            "return": (36, "\r"), "space": (49, " "), "escape": (53, "\u{1b}"), "tab": (48, "\t"),
            "delete": (51, "\u{8}"), "down": (125, String(Character(UnicodeScalar(UInt16(NSDownArrowFunctionKey))!))),
            "up": (126, String(Character(UnicodeScalar(UInt16(NSUpArrowFunctionKey))!))),
            "left": (123, String(Character(UnicodeScalar(UInt16(NSLeftArrowFunctionKey))!))),
            "right": (124, String(Character(UnicodeScalar(UInt16(NSRightArrowFunctionKey))!))),
            "slash": (44, "/"), "j": (38, "j"), "k": (40, "k"), "g": (5, "g"), "G": (5, "G"), "h": (4, "h"), "l": (37, "l"),
            "f5": (96, String(Character(UnicodeScalar(UInt16(NSF5FunctionKey))!))),
            "f6": (97, String(Character(UnicodeScalar(UInt16(NSF6FunctionKey))!))),
        ]
        let (code, characters) = keys[keyName] ?? (0, keyName)
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code
        ) else { return }
        if flags.contains(.command) || keyName.hasPrefix("f") && keyName.count <= 3 {
            // シェルから起動したアプリは前面にならずキーウインドウがないため、
            // メニューから同じショートカットの項目を探して、その操作をこのウインドウに送る
            guard let item = findMenuItem(in: NSApp.mainMenu, key: characters.lowercased(), modifiers: flags),
                  let action = item.action else {
                print("[debug] key \(spec): no menu item")
                return
            }
            print("[debug] key \(spec) -> \(item.title)")
            perform(action, in: controller)
        } else {
            window.firstResponder?.keyDown(with: event)
        }
    }

    private static func findMenuItem(in menu: NSMenu?, key: String, modifiers: NSEvent.ModifierFlags) -> NSMenuItem? {
        for item in menu?.items ?? [] {
            if let submenu = item.submenu, let found = findMenuItem(in: submenu, key: key, modifiers: modifiers) {
                return found
            }
            let mask = item.keyEquivalentModifierMask.intersection([.command, .shift, .option, .control])
            if item.keyEquivalent.lowercased() == key, mask == modifiers { return item }
        }
        return nil
    }

    private static func snapshot(_ window: NSWindow?, to url: URL) {
        guard let view = window?.contentView?.superview else { return }
        snapshotView(view, to: url)
    }

    private static func snapshotView(_ view: NSView, to url: URL) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("[debug] saved \(url.path)")
    }
}

extension FileBrowserViewController {
    func debugExpandFirstFolder() {
        guard let outline = view.firstDescendant(of: NSOutlineView.self) else { return }
        for row in 0..<outline.numberOfRows {
            if let node = outline.item(atRow: row) as? FileNode, node.entry.isFolder {
                outline.expandItem(node)
                return
            }
        }
    }

    func debugSelect(name: String) {
        guard let outline = view.firstDescendant(of: NSOutlineView.self) else { return }
        for row in 0..<outline.numberOfRows {
            if let node = outline.item(atRow: row) as? FileNode, node.entry.name == name {
                outline.selectRowIndexes([row], byExtendingSelection: false)
                return
            }
        }
    }
}

private extension NSView {
    func firstDescendant<T: NSView>(of type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T { return match }
            if let match = subview.firstDescendant(of: type) { return match }
        }
        return nil
    }
}
#endif
