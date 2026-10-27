import AppKit

/// メニューバー。ショートカットは要件定義書 8章のとおり。
enum MainMenu {
    static func build() -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(submenu(appMenu()))
        mainMenu.addItem(submenu(fileMenu()))
        mainMenu.addItem(submenu(editMenu()))
        mainMenu.addItem(submenu(viewMenu()))
        mainMenu.addItem(submenu(goMenu()))

        let windowMenu = windowMenu()
        mainMenu.addItem(submenu(windowMenu))
        NSApp.windowsMenu = windowMenu

        let helpMenu = NSMenu(title: "ヘルプ")
        mainMenu.addItem(submenu(helpMenu))
        NSApp.helpMenu = helpMenu

        return mainMenu
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(
        _ title: String,
        _ action: Selector?,
        _ key: String = "",
        _ modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private static func key(_ functionKey: Int) -> String {
        String(Character(UnicodeScalar(UInt16(functionKey))!))
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Macorn")
        menu.addItem(item("Macorn について", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(item("アップデートを確認…", #selector(AppDelegate.checkForUpdates(_:))))
        menu.addItem(.separator())
        menu.addItem(item("設定…", #selector(AppDelegate.showSettings(_:)), ","))
        menu.addItem(item("コマンドラインツールをインストール…", #selector(AppDelegate.installCommandLineTool(_:))))
        menu.addItem(.separator())

        let services = NSMenu(title: "サービス")
        let servicesItem = NSMenuItem(title: "サービス", action: nil, keyEquivalent: "")
        servicesItem.submenu = services
        NSApp.servicesMenu = services
        menu.addItem(servicesItem)

        menu.addItem(.separator())
        menu.addItem(item("Macorn を隠す", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("ほかを隠す", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item("すべてを表示", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Macorn を終了", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "ファイル")
        menu.addItem(item("新規ウィンドウ", #selector(AppDelegate.newWindow(_:)), "n"))
        menu.addItem(item("新規タブ", #selector(NSResponder.newWindowForTab(_:)), "t"))
        menu.addItem(item("閉じたタブを開く", #selector(AppDelegate.reopenClosedTab(_:)), "t", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("新規フォルダ", #selector(FileBrowserViewController.newFolder(_:)), "n", [.command, .shift]))
        menu.addItem(item("新規ファイル", #selector(FileBrowserViewController.newFile(_:)), "n", [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item("開く", #selector(BrowserWindowController.openSelection(_:)), "o"))
        // Return は入力欄でも使うキーなので、メニューには割り当てない（一覧で Return を押すと名前の変更になる）
        menu.addItem(item("名前を変更", #selector(FileBrowserViewController.renameSelection(_:))))
        menu.addItem(item("一括で名前を変更…", #selector(FileBrowserViewController.bulkRename(_:))))
        menu.addItem(item("情報を見る", #selector(FileBrowserViewController.showInfo(_:)), "i"))
        menu.addItem(item("複製", #selector(FileBrowserViewController.duplicate(_:)), "d"))
        menu.addItem(item("シンボリックリンクを作成", #selector(FileBrowserViewController.makeSymbolicLink(_:))))
        menu.addItem(item("圧縮", #selector(FileBrowserViewController.compress(_:))))
        menu.addItem(item("展開", #selector(FileBrowserViewController.expandArchive(_:))))
        menu.addItem(item("クイックルック", #selector(FileBrowserViewController.toggleQuickLook(_:)), "y"))
        menu.addItem(.separator())
        menu.addItem(item("ゴミ箱に入れる", #selector(FileBrowserViewController.moveToTrash(_:)), key(NSBackspaceCharacter)))
        menu.addItem(item("すぐに削除…", #selector(FileBrowserViewController.deleteImmediately(_:)), key(NSBackspaceCharacter), [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item("ターミナルで開く", #selector(FileBrowserViewController.openInTerminal(_:)), "t", [.command, .option]))
        menu.addItem(item("エディタで開く", #selector(FileBrowserViewController.openInEditor(_:)), "e", [.command, .option]))
        menu.addItem(item("リポジトリのルートをエディタで開く", #selector(FileBrowserViewController.openRepositoryInEditor(_:))))
        menu.addItem(.separator())
        menu.addItem(item("反対側の画面へコピー", #selector(BrowserWindowController.copyToOtherPane(_:)), key(NSF5FunctionKey), []))
        menu.addItem(item("反対側の画面へ移動", #selector(BrowserWindowController.moveToOtherPane(_:)), key(NSF6FunctionKey), []))
        menu.addItem(.separator())
        menu.addItem(item("お気に入りに追加", #selector(BrowserWindowController.addToSidebar(_:)), "t", [.command, .control]))
        menu.addItem(item("タグを編集…", #selector(FileBrowserViewController.editTags(_:)), "g", [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item("閉じる", #selector(NSWindow.performClose(_:)), "w"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "編集")
        menu.addItem(item("取り消す", Selector(("undo:")), "z"))
        menu.addItem(item("やり直す", Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("カット", #selector(NSText.cut(_:)), "x"))
        menu.addItem(item("コピー", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("ペースト", #selector(NSText.paste(_:)), "v"))
        menu.addItem(item("ここに移動", #selector(FileBrowserViewController.moveHere(_:)), "v", [.command, .option]))
        menu.addItem(item("すべてを選択", #selector(NSResponder.selectAll(_:)), "a"))
        menu.addItem(item("絞り込み", #selector(FileBrowserViewController.beginFilter(_:)), "f"))
        menu.addItem(.separator())
        menu.addItem(item("パスをコピー", #selector(FileBrowserViewController.copyPath(_:)), "c", [.command, .option]))
        menu.addItem(item("パスをコピー（~ 形式）", #selector(FileBrowserViewController.copyTildePath(_:)), "c", [.command, .option, .shift]))
        menu.addItem(item("リポジトリからの相対パスをコピー", #selector(FileBrowserViewController.copyRelativePath(_:))))
        menu.addItem(item("シェル用にパスをコピー", #selector(FileBrowserViewController.copyShellQuotedPath(_:))))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "表示")
        menu.addItem(item("コマンドパレット…", #selector(BrowserWindowController.togglePalette(_:)), "k"))
        menu.addItem(.separator())
        menu.addItem(item("隠しファイルを表示", #selector(AppDelegate.toggleHiddenFiles(_:)), ".", [.command, .shift]))
        menu.addItem(item("サイドバーを表示", #selector(NSSplitViewController.toggleSidebar(_:)), "s", [.command, .option]))
        menu.addItem(submenu(sortMenu()))
        menu.addItem(.separator())
        menu.addItem(item("プレビューを拡大", #selector(FileBrowserViewController.zoomInPreview(_:)), "+"))
        // US キーボードでは ⌘= でも拡大できるようにする（メニューには出さない）
        // ショートカットの変更で別の項目として扱えるよう、名前を分けておく
        let zoomInAlternate = item("プレビューを拡大（⌘=）", #selector(FileBrowserViewController.zoomInPreview(_:)), "=")
        zoomInAlternate.isHidden = true
        zoomInAlternate.allowsKeyEquivalentWhenHidden = true
        menu.addItem(zoomInAlternate)
        menu.addItem(item("プレビューを縮小", #selector(FileBrowserViewController.zoomOutPreview(_:)), "-"))
        menu.addItem(item("プレビューを実際のサイズに", #selector(FileBrowserViewController.resetPreviewZoom(_:)), "0"))
        menu.addItem(item("プレビュー", #selector(FileBrowserViewController.toggleFilePreview(_:)), "p", [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item("2画面表示", #selector(BrowserWindowController.toggleSplit(_:)), "\\"))
        // Tab キーは一覧の中だけで効く（入力欄の Tab と区別するため、メニューには割り当てない）
        menu.addItem(item("もう一方の画面へ切り替え（Tab）", #selector(BrowserWindowController.switchPane(_:))))
        menu.addItem(item("反対側を同じフォルダにする", #selector(BrowserWindowController.syncOtherPane(_:)), "=", [.command, .option]))
        menu.addItem(item("左右のフォルダを入れ替え", #selector(BrowserWindowController.swapPanes(_:)), "u", [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item("フルスクリーンにする", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return menu
    }

    /// 表示 › 並び順（列の見出しをクリックするのと同じ。⌃⌘1〜5）
    private static func sortMenu() -> NSMenu {
        let menu = NSMenu(title: "並び順")
        let keys: [(String, FileSortKey)] = [("名前", .name), ("変更日", .dateModified), ("サイズ", .size), ("種類", .kind), ("タグ", .tags)]
        for (index, (title, key)) in keys.enumerated() {
            let sortItem = item(title, #selector(AppDelegate.sortBy(_:)), "\(index + 1)", [.command, .control])
            sortItem.representedObject = key.rawValue
            menu.addItem(sortItem)
        }
        menu.addItem(.separator())
        menu.addItem(item("降順にする", #selector(AppDelegate.toggleSortDirection(_:))))
        return menu
    }

    private static func goMenu() -> NSMenu {
        let menu = NSMenu(title: "移動")
        menu.addItem(item("戻る", #selector(BrowserWindowController.goBack(_:)), "["))
        menu.addItem(item("進む", #selector(BrowserWindowController.goForward(_:)), "]"))
        menu.addItem(item("親フォルダ", #selector(BrowserWindowController.goToParent(_:)), key(NSUpArrowFunctionKey)))
        menu.addItem(item("選択した項目を開く", #selector(BrowserWindowController.openSelection(_:)), key(NSDownArrowFunctionKey)))
        menu.addItem(item("左の画面で開く", #selector(BrowserWindowController.openInLeftPane(_:)), key(NSLeftArrowFunctionKey), [.command, .option]))
        menu.addItem(item("右の画面で開く", #selector(BrowserWindowController.openInRightPane(_:)), key(NSRightArrowFunctionKey), [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item("ホーム", #selector(BrowserWindowController.goToHome(_:)), "h", [.command, .shift]))
        menu.addItem(item("デスクトップ", #selector(BrowserWindowController.goToDesktop(_:)), "d", [.command, .shift]))
        menu.addItem(item("書類", #selector(BrowserWindowController.goToDocuments(_:)), "o", [.command, .shift]))
        menu.addItem(item("ダウンロード", #selector(BrowserWindowController.goToDownloads(_:)), "l", [.command, .option]))
        menu.addItem(item("アプリケーション", #selector(BrowserWindowController.goToApplications(_:)), "a", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("パスを入力…", #selector(BrowserWindowController.editPath(_:)), "l"))
        menu.addItem(item("フォルダへ移動…", #selector(BrowserWindowController.editPath(_:)), "g", [.command, .shift]))
        menu.addItem(item("サーバへ接続…", #selector(BrowserWindowController.connectToServer(_:))))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "ウインドウ")
        menu.addItem(item("しまう", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("拡大／縮小", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("すべてを手前に移動", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }
}
