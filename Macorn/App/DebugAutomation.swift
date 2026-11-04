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
        case "sbdrop":
            // sbdrop:<ドラッグするもの>><置き先の行 ID か root>><何番目か（-1 は行の上）>[>copy]
            let parts = argument.components(separatedBy: ">")
            if parts.count >= 3, let split = controller.contentViewController as? NSSplitViewController,
               let sidebar = split.splitViewItems.first?.viewController as? SidebarViewController {
                print("[debug] sbdrop \(argument) → \(sidebar.debugDrop(drag: parts[0], onto: parts[1], index: Int(parts[2]) ?? -1, copy: parts.count > 3))")
            }
        case "sbhover":
            // sbhover:<ドラッグするもの>><カーソルを置く行 ID>><行の中の高さ 0〜1>[>copy]
            let parts = argument.components(separatedBy: ">")
            if parts.count >= 3, let split = controller.contentViewController as? NSSplitViewController,
               let sidebar = split.splitViewItems.first?.viewController as? SidebarViewController {
                print("[debug] sbhover \(argument) → \(sidebar.debugHoverDrop(drag: parts[0], onto: parts[1], fraction: CGFloat(Double(parts[2]) ?? 0.5), copy: parts.count > 3))")
            }
        case "mksection":
            SidebarStore.shared.createSection(named: argument)
        case "mksub":
            // mksub:<親のセクションの名前>><サブセクションの名前>
            let parts = argument.components(separatedBy: ">")
            if parts.count == 2, let parent = SidebarStore.shared.customSections.first(where: { $0.name == parts[0] }) {
                SidebarStore.shared.createSubsection(named: parts[1], in: parent.id)
            }
        case "sbrows":
            if let split = controller.contentViewController as? NSSplitViewController,
               let sidebar = split.splitViewItems.first?.viewController as? SidebarViewController {
                print("[debug] sbrows \(sidebar.debugRows())")
            }
        case "windows":
            // 開いている全ウィンドウ・タブのフォルダと選択（ほかのアプリから開いたときの確認用）
            for (index, other) in controllers().enumerated() {
                let names = other.browser.selectedURLs.map(\.lastPathComponent).joined(separator: ",")
                print("[debug] window \(index) path=\(other.browser.state.currentURL.path) selected=\(names) preview=\(other.browser.isFilePreviewVisible)")
            }
        case "tabinfo":
            // タブの並びと、各タブの「×」が画面に載っているか
            let group = controller.window?.tabGroup?.windows ?? []
            for (index, window) in group.enumerated() {
                let button = window.tab.accessoryView
                let frame = button.flatMap { $0.window == nil ? nil : $0.convert($0.bounds, to: nil) }
                print("[debug] tab \(index) title=\(window.title) selected=\(window == window.tabGroup?.selectedWindow) closeButton=\(button is TabCloseButton) onScreen=\(frame.map { NSStringFromRect($0) } ?? "no")")
            }
            print("[debug] tabbar visible=\(controller.window?.tabGroup?.isTabBarVisible == true) count=\(group.count)")
        case "tooltips":
            // ウィンドウ中のボタン（ツールバー・タブ・パスバーなど）と、カーソルを乗せたときの説明
            func walk(_ view: NSView, depth: Int) {
                if view is NSButton || view.toolTip != nil || view.accessibilityRole() == .button {
                    let frame = NSStringFromRect(view.convert(view.bounds, to: nil))
                    let label = view.accessibilityLabel() ?? (view as? NSButton)?.title ?? ""
                    print("[debug] button \(type(of: view)) label=\(label) tip=\(view.toolTip ?? "nil") frame=\(frame) hidden=\(view.isHiddenOrHasHiddenAncestor)")
                }
                view.subviews.forEach { walk($0, depth: depth + 1) }
            }
            if let root = controller.window?.contentView?.superview { walk(root, depth: 0) }
        case "toolbarclick":
            // ツールバーのボタン（短い名前で指定）を押す
            // 短い名前でも識別子（macorn.terminal など）でも指定できる
            let item = controller.window?.toolbar?.items.first { $0.label == argument || $0.itemIdentifier.rawValue == argument }
            controller.window?.toolbar?.validateVisibleItems()
            if let button = item?.view as? NSButton {
                button.performClick(nil)
            } else if let item, item.isEnabled, let action = item.action {
                NSApp.sendAction(action, to: item.target, from: item)
            } else {
                print("[debug] toolbarclick \(argument) not found")
            }
        case "tabclose":
            // 指定した番号のタブの「×」を押す
            let group = controller.window?.tabGroup?.windows ?? []
            if let index = Int(argument), group.indices.contains(index) {
                (group[index].tab.accessoryView as? TabCloseButton)?.closeTab()
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
        case "clickpath":
            // パスバーを1回クリックする。引数は横の位置（0〜1。1 に近いほど右）
            if let bar = browser.pathBarHost, let window = bar.window {
                let fraction = CGFloat(Double(argument) ?? 0.9)
                let point = bar.convert(NSPoint(x: bar.bounds.width * fraction, y: bar.bounds.midY), to: nil)
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                      windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                        window.sendEvent(event)
                    }
                }
            }
        case "addmenu":
            // サイドバーの「＋ 追加」のメニューの中身を書き出す。引数に項目名（「>」で下の階層）を渡すと、それを選ぶ
            if let split = controller.contentViewController as? NSSplitViewController,
               let sidebar = split.splitViewItems.first?.viewController as? SidebarViewController {
                let menu = sidebar.makeAddMenu()
                func dump(_ menu: NSMenu, _ indent: String) {
                    for entry in menu.items {
                        if entry.isSeparatorItem { print("[debug] addmenu \(indent)---"); continue }
                        print("[debug] addmenu \(indent)\(entry.title)\(entry.isEnabled ? "" : " (無効)")")
                        if let sub = entry.submenu { dump(sub, indent + "  ") }
                    }
                }
                if argument.isEmpty {
                    dump(menu, "")
                } else {
                    var current: NSMenu? = menu
                    var target: NSMenuItem?
                    for name in argument.split(separator: ">").map(String.init) {
                        target = current?.items.first { $0.title == name }
                        current = target?.submenu
                    }
                    if let target, let owner = target.menu, let index = owner.items.firstIndex(of: target) {
                        owner.performActionForItem(at: index)
                    } else {
                        print("[debug] addmenu 見つからない: \(argument)")
                    }
                }
            }
        case "sectionmenu", "sectionmenudo":
            // 「sectionmenu:名前」でセクションの「…」のメニューを書き出す。「sectionmenudo:名前>項目」でその項目を選ぶ
            if let split = controller.contentViewController as? NSSplitViewController,
               let sidebar = split.splitViewItems.first?.viewController as? SidebarViewController {
                let parts = argument.split(separator: ">", maxSplits: 1).map(String.init)
                guard let (menu, hasButton) = sidebar.debugSectionMenu(named: parts[0]) else {
                    print("[debug] sectionmenu 見つからない: \(parts[0])"); break
                }
                if command == "sectionmenu" {
                    print("[debug] sectionmenu \(parts[0]) button=\(hasButton)")
                    for entry in menu.items {
                        print("[debug] sectionmenu   " + (entry.isSeparatorItem ? "---" : entry.title + (entry.isEnabled ? "" : " (無効)")))
                    }
                } else if parts.count > 1, let index = menu.items.firstIndex(where: { $0.title == parts[1] }) {
                    menu.performActionForItem(at: index)
                } else {
                    print("[debug] sectionmenu 項目が見つからない: \(argument)")
                }
            }
        case "sbhoverrow":
            if let split = controller.contentViewController as? NSSplitViewController,
               let sidebar = split.splitViewItems.first?.viewController as? SidebarViewController {
                print("[debug] sbhover " + sidebar.debugHover(row: Int(argument) ?? 0))
            }
        case "closepanebutton":
            // N 番目の画面のパスバーの「×」を押したのと同じ
            let all = controller.panes.panes
            if let index = Int(argument), all.indices.contains(index) { all[index].onClosePane?() }
        case "clickwindow":
            // ウィンドウの中身の決まった位置を1回クリックする（アプリ全体の経路で送るので、クリックの見張りにも届く）。
            // 引数は「横,縦」の割合（0〜1。左下が 0,0）か「pathbar,横」。実際のマウスは動かさない
            // 「pathbar,横」ならパスバーの中（入力中は入力欄の上）を押す
            let onPathBar = argument.hasPrefix("pathbar")
            if let window = controller.window, let content = onPathBar ? browser.pathBarHost : window.contentView {
                let parts = argument.split(separator: ",").compactMap { Double($0) }
                let fx = CGFloat(parts.first ?? 0.5)
                let fy = CGFloat(onPathBar ? 0.5 : (parts.count > 1 ? parts[1] : 0.5))
                let point = content.convert(NSPoint(x: content.bounds.width * fx, y: content.bounds.height * fy), to: nil)
                func mouse(_ type: NSEvent.EventType) -> NSEvent? {
                    NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
                }
                // 一覧は押したあと離すまで待つので、離す操作を先に積んでから押す
                if let up = mouse(.leftMouseUp) { NSApp.postEvent(up, atStart: false) }
                if let down = mouse(.leftMouseDown) { NSApp.sendEvent(down) }
            }
        case "updatecheck":
            // 新しい版の確認（引数は確かめる先の URL）。結果を書き出し、アラートをシートで出す（snapsheet で撮る）
            let url = URL(string: argument) ?? UpdateChecker.feedURL
            Task {
                let result = await UpdateChecker.fetch(from: url)
                print("[debug] updatecheck current=\(UpdateChecker.currentVersion) result=\(result)")
                UpdateChecker.present(result, manual: false, in: controller.window)
            }
        case "updateinstall":
            // 自動更新の入れ替え（引数は version.json の URL。版の比較は飛ばす）。用意できたら Macorn を終えて入れ替え、開き直す
            Task {
                do {
                    let url = URL(string: argument) ?? UpdateChecker.feedURL
                    let data = url.isFileURL ? try Data(contentsOf: url) : try await URLSession.shared.data(from: url).0
                    let info = try JSONDecoder().decode(ReleaseInfo.self, from: data)
                    print("[debug] updateinstall team=\(UpdateInstaller.ownTeamIdentifier ?? "nil") canInstall=\(UpdateInstaller.canInstall) to=\(UpdateInstaller.destination.path)")
                    let staged = try await UpdateInstaller.prepare(info) { print("[debug] updateinstall progress=\($0)") }
                    print("[debug] updateinstall staged=\(staged.path)")
                    UpdateInstaller.relaunch(replacing: UpdateInstaller.destination, with: staged)
                } catch {
                    print("[debug] updateinstall error=\(error.localizedDescription)")
                }
            }
        case "settings":
            // 設定ウィンドウを開く（キーにしない）。引数はタブ（general / integration など）
            let tabs: [String: SettingsTab] = ["general": .general, "integration": .integration, "sidebar": .sidebar,
                                               "tags": .tags, "shortcuts": .shortcuts, "history": .history]
            SettingsNavigation.shared.tab = tabs[argument] ?? .general
            SettingsWindowController.shared.window?.orderFront(nil)
        case "snapsettings":
            snapshot(SettingsWindowController.shared.window, to: outDir.appendingPathComponent("\(argument).png"))
        case "closesettings":
            SettingsWindowController.shared.window?.orderOut(nil)
        case "fileapp":
            // 種類ごとの既定のアプリの切り替え（設定と同じ処理）。引数は <種類>:on|off（例 pdf:on）
            let parts = argument.split(separator: ":").map(String.init)
            if parts.count == 2, let kind = PreviewFileKind(rawValue: parts[0]) {
                Task {
                    do { try await DefaultFileApps.setOpensFiles(parts[1] == "on", kind: kind) } catch { print("[debug] fileapp error \(error)") }
                    print("[debug] fileapp \(kind.rawValue) opens=\(DefaultFileApps.opensFiles(of: kind))")
                }
            }
        case "fileviewer":
            // 「Finder に表示」の行き先の切り替え（設定の切り替えと同じ処理）
            SystemFileViewer.setRevealsFiles(argument == "on")
            print("[debug] fileviewer revealsFiles=\(SystemFileViewer.revealsFiles)")
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
        case "maxstate":
            print("[debug] max=\(browser.isPreviewMaximized) listCollapsed=\(browser.isListCollapsed) button=\(browser.filePreview.isMaximizedAppearance) preview=\(Int(browser.filePreview.view.frame.width))/\(Int(browser.contentSplit.bounds.width)) panes=\(controller.panes.panes.map { Int($0.view.frame.width) }) sidebar=\((controller.window?.contentViewController as? NSSplitViewController)?.splitViewItems.first?.isCollapsed ?? false) first=\(controller.window?.firstResponder.map { String(describing: type(of: $0)) } ?? "-")")
        case "listcollapse":
            // プレビューの左上の「一覧を畳む」を押したときと同じ
            browser.filePreview.onCollapseList?()
        case "previewmax":
            // プレビューの「最大化」・畳んでいるときの「一覧を表示」を押したときと同じ
            browser.filePreview.onToggleMaximize?()
        case "splitviews":
            // 一覧とプレビューの分割の中の部品と位置（境目の線が残っていないかの確認用）
            let split = browser.contentSplit
            let parts = split.subviews.map { "\(type(of: $0))\($0.isHidden ? "(hidden)" : "") x=\(Int($0.frame.minX)) w=\(Int($0.frame.width))" }
            print("[debug] split width=\(Int(split.bounds.width)) arranged=\(split.arrangedSubviews.count) subviews=\(parts) sublayers=\(split.layer?.sublayers?.map { "\(type(of: $0)) x=\(Int($0.frame.minX)) w=\(Int($0.frame.width))" } ?? [])")
        case "listdrag":
            // 一覧とプレビューの境目を指定の位置へ動かす（ドラッグの代わり。0 で左端へ）
            browser.contentSplit.setPosition(CGFloat(Double(argument) ?? 0), ofDividerAt: 0)
        case "closepreview":
            // プレビューの「×」を押したときと同じ
            browser.filePreview.onClose?()
        case "mdstate":
            let preview = browser.filePreview
            print("[debug] md visible=\(browser.isFilePreviewVisible) file=\(preview.fileURL?.lastPathComponent ?? "-") html=\(preview.lastHTMLLength) width=\(Int(preview.view.frame.width))/\(Int(browser.contentSplit.bounds.width))")
        case "snapmd":
            await withCheckedContinuation { continuation in
                browser.filePreview.debugSnapshot(to: outDir.appendingPathComponent("\(argument).png")) {
                    continuation.resume()
                }
            }
            print("[debug] saved md \(argument)")
        case "zoom":
            print("[debug] zoom=\(String(format: "%.2f", browser.filePreview.zoom)) canZoom=\(browser.filePreview.canZoom) saved=\(Preferences.previewZoom)")
        case "qlstate":
            print("[debug] \(browser.filePreview.debugQuickLookState) kind=\(browser.filePreview.kind)")
        case "scripts":
            browser.filePreview.debugToggleScripts()
            print("[debug] scripts=\(browser.filePreview.scriptsEnabled) kind=\(browser.filePreview.kind)")
        case "append":
            let parts = argument.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2, let handle = FileHandle(forWritingAtPath: browser.state.currentURL.appendingPathComponent(parts[0]).path) {
                handle.seekToEndOfFile()
                handle.write(Data(("\n" + parts[1] + "\n").utf8))
                try? handle.close()
            }
        case "accent":
            Theme.shared.accentHex = argument == "system" ? nil : argument
        case "appearance":
            Theme.shared.appearance = Theme.Appearance(rawValue: argument) ?? .system
        case "tagmenu":
            // 右クリックの「タグ」メニューの行を、メニューを閉じずに続けて押したときと同じ動きをさせる
            let menu = browser.tagMenuItem(for: browser.selectedURLs).submenu
            let views = menu?.items.compactMap { $0.view as? TagCheckboxMenuView } ?? []
            views.forEach { $0.debugToggle() }
            print("[debug] tagmenu rows=\(views.count) states=\(views.map(\.debugState.rawValue))")
        case "changes":
            // 表示中のリポジトリの変更のウィンドウを、キーにせずに開く
            if let root = browser.gitSnapshot?.root ?? GitRepository.root(containing: browser.state.currentURL) {
                ChangesWindowController.show(root: root, activate: false)
            }
        case "filediff":
            // 一覧で選んでいる項目の差分を、キーにせずに開く
            if let snapshot = browser.gitSnapshot, let node = browser.selectedNodes.first,
               let relative = FileBrowserViewController.diffPath(of: node, in: snapshot) {
                ChangesWindowController.show(root: snapshot.root, selecting: relative, activate: false)
            } else {
                print("[debug] filediff unavailable")
            }
        case "terminal":
            // 内蔵ターミナルを出す（キーにはしない）
            controller.workspace.showTerminal(in: browser.state.currentURL)
        case "termtype":
            controller.workspace.terminal.debugSend(argument)
        case "termdump":
            let terminal = controller.workspace.terminal.emulator
            print("[debug] term visible=\(controller.workspace.isTerminalVisible) running=\(controller.workspace.terminal.isRunning) size=\(terminal.columns)x\(terminal.rows) cursor=\(terminal.cursorX),\(terminal.cursorY) alt=\(terminal.isAlternateScreen) dir=\(terminal.reportedDirectory ?? "-")")
            for (index, line) in terminal.screenText.enumerated() where !line.isEmpty { print("[debug] term \(index): \(line)") }
            print("[debug] term layout \(controller.workspace.terminal.debugLayout)")
        case "termkey":
            // キーボードから打ったのと同じ経路（keyDown → 日本語入力の仕組み）で文字を送る。最後に Return
            let view = controller.workspace.terminal.terminalView!
            let window = view.window
            for character in argument + "\r" {
                let text = String(character)
                let keyCode: UInt16 = text == "\r" ? 36 : 0
                if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                windowNumber: window?.windowNumber ?? 0, context: nil,
                                                characters: text, charactersIgnoringModifiers: text,
                                                isARepeat: false, keyCode: keyCode) {
                    view.keyDown(with: event)
                }
            }
        case "termstate":
            controller.window?.toolbar?.validateVisibleItems()
            let item = controller.window?.toolbar?.items.first { $0.itemIdentifier == .terminal }
            print("[debug] term visible=\(controller.workspace.isTerminalVisible) toolbar=\(item?.toolTip ?? "-")")
        case "termbutton":
            // 右上のツールバーのターミナルのボタンを押したのと同じ
            ActionRouter.send(#selector(BrowserWindowController.toggleTerminalPanel(_:)), in: controller.window)
            print("[debug] term button visible=\(controller.workspace.isTerminalVisible) paneState=\(controller.panes.panes.map(\.state.isTerminalVisible))")
        case "termpos":
            // termpos:bottom|left|right
            if let position = TerminalPosition(rawValue: argument) { controller.workspace.move(to: position) }
            let split = controller.workspace.splitView
            print("[debug] term pos=\(controller.workspace.position) vertical=\(split.isVertical) visible=\(controller.workspace.isTerminalVisible) running=\(controller.workspace.terminal.isRunning) frames=\(split.arrangedSubviews.map { "\($0.frame)" }) termFrame=\(controller.workspace.terminal.view.frame)")
        case "termhide":
            controller.workspace.hideTerminal()
        case "gitinfo":
            print("[debug] git name=\(browser.state.gitRepositoryName ?? "-") branch=\(browser.state.gitBranch ?? "-") web=\(browser.state.gitRemoteWebURL?.absoluteString ?? "-") service=\(browser.state.gitRemoteServiceName ?? "-")")
        case "changeselect":
            ChangesWindowController.open.first?.model.select(argument)
        case "changesinfo":
            if let model = ChangesWindowController.open.first?.model {
                print("[debug] changes branch=\(model.branch ?? "-") files=\(model.changes.map { "\($0.status.badge):\($0.path)" }) selected=\(model.selectedPath ?? "-") hunks=\(model.diff?.hunks.count ?? -1) +\(model.diff?.addedCount ?? 0) -\(model.diff?.removedCount ?? 0) binary=\(model.diff?.isBinary ?? false)")
            }
        case "snapchanges":
            if let window = ChangesWindowController.open.first?.window {
                snapshot(window, to: outDir.appendingPathComponent("\(argument).png"))
            }
        case "closechanges":
            ChangesWindowController.open.forEach { $0.close() }
        case "dividerhit":
            // 区切り線の近くを押したとき、区切り線が反応するか（-14〜+6 ポイント）
            if let content = controller.window?.contentView {
                for split in content.allDescendants(of: NSSplitView.self) where !split.isHidden {
                    let visible = split.arrangedSubviews.filter { !$0.isHidden }
                    guard visible.count > 1 else { continue }
                    for index in 0..<(visible.count - 1) {
                        let a = visible[index].frame
                        let center = split.isVertical ? NSPoint(x: a.maxX + split.dividerThickness / 2, y: split.bounds.midY)
                                                      : NSPoint(x: split.bounds.midX, y: a.maxY + split.dividerThickness / 2)
                        let hits = (-14...6).map { offset -> String in
                            let local = split.isVertical ? NSPoint(x: center.x + CGFloat(offset), y: center.y) : NSPoint(x: center.x, y: center.y + CGFloat(offset))
                            let point = split.superview!.convert(local, from: split)
                            return split.hitTest(point) === split ? "■" : "·"
                        }.joined()
                        print("[debug] divider \(type(of: split)) vertical=\(split.isVertical) #\(index) \(hits)")
                    }
                }
            }
        case "dragstate": browser.debugDragState(argument)
        case "dragstuck": browser.outlineView.debugMarkDragEntered()
        case "listinfo": print("[debug] list \(browser.debugListInfo())")
        case "repolink":
            // repolink: 一覧の名前の欄で「持ち主/リポジトリ」の押せる範囲（ウィンドウの座標）
            for cell in browser.view.allDescendants(of: FileCellView.self) {
                guard let field = cell.textField, field.stringValue.hasPrefix(argument), let rect = cell.repositoryLinkRect() else { continue }
                print("[debug] repolink \(field.stringValue) rect=\(field.convert(rect, to: nil)) field=\(field.convert(field.bounds, to: nil))")
            }
        case "scrollbottom": browser.debugScrollToBottom()
        case "splitinfo":
            let split = browser.contentSplit
            print("[debug] split bounds=\(split.bounds) subviews=\(split.subviews.map { "\(type(of: $0)) \($0.frame) hidden=\($0.isHidden)" }) arranged=\(split.arrangedSubviews.count)")
        case "closepopover":
            browser.tagPopover?.performClose(nil)
        case "popover":
            print("[debug] popover shown=\(browser.tagPopover?.isShown ?? false)")
        case "sections":
            print("[debug] sections=\(SidebarStore.shared.visibleSections.map(\.title)) favorites=\(SidebarStore.shared.favorites.map { $0.tagID != nil ? "#" + $0.name : $0.name })")
        case "tagsection":
            if let tag = TagStore.shared.tag(named: argument) { SidebarStore.shared.addTagSection(tag.id) }
        case "favtag":
            if let tag = TagStore.shared.tag(named: argument) { SidebarStore.shared.addFavoriteTag(tag.id) }
        case "movesection":
            let parts = argument.split(separator: "=").map(String.init)
            if parts.count == 2, let section = SidebarSection(id: parts[0]), let delta = Int(parts[1]) {
                SidebarStore.shared.moveSection(section, by: delta)
            }
        case "hidesection":
            if let section = SidebarSection(id: argument) { SidebarStore.shared.setSection(section, hidden: true) }
        case "resetsections":
            SidebarStore.shared.resetSections()
        case "favs":
            print("[debug] favorites=\(SidebarStore.shared.favorites.map { $0.name + ($0.isMissing ? "(missing)" : "") })")
        case "favrename":
            let parts = argument.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2, let item = SidebarStore.shared.favorites.first(where: { $0.url.lastPathComponent == parts[0] }) {
                SidebarStore.shared.renameFavorite(item.url, to: parts[1])
            }
        case "toolbarclick":
            // ツールバーのボタンを押す。引数は識別子（macorn.terminal など）
            if let item = controller.window?.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == argument }) {
                controller.window?.toolbar?.validateVisibleItems()
                print("[debug] toolbarclick \(argument) enabled=\(item.isEnabled)")
                if item.isEnabled, let action = item.action { NSApp.sendAction(action, to: item.target, from: item) }
            } else {
                print("[debug] toolbarclick \(argument) not found")
            }
        case "toolbar":
            controller.window?.toolbar?.validateVisibleItems()
            print("[debug] toolbar=\(controller.window?.toolbar?.items.map(\.itemIdentifier.rawValue) ?? [])")
        case "pane":
            let panes = controller.panes
            print("[debug] pane split=\(panes.isSplit) active=\(panes.activeIndex) paths=\(panes.panes.map(\.state.currentURL.lastPathComponent)) selected=\(panes.panes.map { $0.selectedNodes.map(\.entry.name) }) title=\(controller.window?.title ?? "")")
        case "columns":
            for pane in controller.panes.panes {
                let outline = pane.outlineView
                print("[debug] columns \(outline.tableColumns.map { "\($0.identifier.rawValue)=\(Int($0.width))\($0.isHidden ? "(hidden)" : "")" }) outline=\(Int(outline.frame.width)) clip=\(Int(outline.enclosingScrollView?.contentView.bounds.width ?? 0))")
            }
        case "split":
            // 操作対象の画面を分ける（right / down）
            controller.panes.split(argument == "down" ? .down : .right, focusNew: true)
        case "closepane":
            controller.panes.closeActivePane()
        case "panelayout":
            // 画面の並び（入れ子）と各画面の大きさを書き出す
            let layout = controller.panes.layout
            if let data = try? JSONEncoder().encode(layout.tree), let text = String(data: data, encoding: .utf8) {
                print("[debug] panelayout active=\(layout.activeIndex) tree=\(text)")
            }
            for pane in controller.panes.panes {
                let frame = pane.view.convert(pane.view.bounds, to: nil)
                print("[debug] panelayout \(pane.state.currentURL.lastPathComponent) frame=\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height)) active=\(pane.state.isActive) hidden=\(pane.view.isHiddenOrHasHiddenAncestor || pane.view.frame.width < 1)")
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
        case "winsize":
            // winsize:1280x720 ― ウィンドウの大きさを変えて画面の中央へ（宣伝用の撮影）
            let size = argument.split(separator: "x").compactMap { Double($0) }
            if size.count == 2, let window = controller.window {
                window.setFrame(NSRect(x: 0, y: 0, width: size[0], height: size[1]), display: true)
                window.center()
            }
        case "shot":
            // shot:<名前> ― 撮影の合図を標準エラーに出し、2秒待つ。外の撮影スクリプトがこの間に撮る。
            // 「SHOT 名前 倍率 本体=番号:x,y,w,h 重なり=番号:x,y,w,h;…」（座標は画面の左下が原点）
            guard let main = controller.window else { break }
            func describe(_ window: NSWindow) -> String {
                let f = window.frame
                return "\(window.windowNumber):\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width)),\(Int(f.height))"
            }
            let windows = NSApp.windows.filter { $0 !== main && $0.isVisible && $0.windowNumber > 0 && $0.frame.intersects(main.frame) }
            // パレット・ポップオーバーは、見えていないデスクトップのウィンドウを撮ると後ろまで写るので、中身を描いて重ねる
            let overlays: [NSWindow] = []
            var images: [String] = []
            for (index, popover) in windows.enumerated() {
                guard let view = popover.contentView else { continue }
                let path = outDir.appendingPathComponent("\(argument)_overlay\(index).png").path
                snapshotOpaque(view, to: URL(fileURLWithPath: path))
                let rect = popover.convertToScreen(view.convert(view.bounds, to: nil))
                images.append("\(path)|\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))")
            }
            // Web の表示（Markdown・HTML のプレビュー）は、見えていないデスクトップのウィンドウを撮ると空になるので、別に撮って重ねる
            if browser.isFilePreviewVisible, let web = browser.filePreview.debugVisibleWebView, web.window === main {
                let path = outDir.appendingPathComponent("\(argument)_web.png").path
                await withCheckedContinuation { continuation in
                    browser.filePreview.debugSnapshot(to: URL(fileURLWithPath: path)) { continuation.resume() }
                }
                let rect = main.convertToScreen(web.convert(web.bounds, to: nil))
                images.append("\(path)|\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))")
            }
            let line = "SHOT \(argument) \(main.backingScaleFactor) main=\(describe(main)) overlays=\(overlays.map(describe).joined(separator: ";")) images=\(images.joined(separator: ";"))\n"
            FileHandle.standardError.write(Data(line.utf8))
            try? await Task.sleep(for: .seconds(2))
        case "quit": NSApp.terminate(nil)
        default: print("[debug] unknown step \(step)")
        }
    }

    /// 画面の部品を、背景（ウィンドウの色・角丸）を敷いて 2 倍の解像度で PNG にする（半透明の背景は写らないため）
    private static func snapshotOpaque(_ view: NSView, to url: URL) {
        let size = view.bounds.size
        guard size.width > 0, size.height > 0, let cached = view.bitmapImageRepForCachingDisplay(in: view.bounds),
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        view.cacheDisplay(in: view.bounds, to: cached)
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 10, yRadius: 10).fill()
        }
        cached.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func perform(_ action: Selector, in controller: BrowserWindowController, sender: Any? = nil) {
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
        _ = (target as? NSObject)?.perform(action, with: sender)
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
            "plus": (24, "+"), "equal": (24, "="), "minus": (27, "-"),
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
            perform(action, in: controller, sender: item)
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

extension FileBrowserViewController {
    /// dragstate:begin / end … この一覧からドラッグを始めた・終えたことにする
    func debugDragState(_ argument: String) {
        if argument == "begin" {
            isDragSourceActive = true
        } else {
            isDragSourceActive = false
            dragDidFinish()
        }
    }

    /// listinfo … 行数・選択・スクロールの位置
    func debugListInfo() -> String {
        let selected = outlineView.selectedRowIndexes.map { $0 }
        return "rows=\(outlineView.numberOfRows) selected=\(selected) scrollY=\(Int(scrollView.contentView.bounds.origin.y)) expandOK=\(outlineView.delegate?.outlineView?(outlineView, shouldExpandItem: outlineView.item(atRow: 0) as Any) ?? true)"
    }

    /// scrollbottom … 一覧のいちばん下までスクロールする
    func debugScrollToBottom() {
        outlineView.scrollRowToVisible(outlineView.numberOfRows - 1)
    }
}

private extension NSView {
    func allDescendants<T: NSView>(of type: T.Type) -> [T] {
        subviews.flatMap { view -> [T] in
            let own: [T] = (view as? T).map { [$0] } ?? []
            return own + view.allDescendants(of: type)
        }
    }

    func firstDescendant<T: NSView>(of type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T { return match }
            if let match = subview.firstDescendant(of: type) { return match }
        }
        return nil
    }
}
#endif
