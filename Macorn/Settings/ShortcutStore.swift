import AppKit

/// ショートカット1つ分（キーと修飾キー）。
nonisolated struct KeyCombo: Codable, Equatable, Hashable, Sendable {
    var key: String
    var modifiers: UInt

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    init(key: String, flags: NSEvent.ModifierFlags) {
        self.key = key
        self.modifiers = flags.intersection([.command, .option, .shift, .control]).rawValue
    }

    var isEmpty: Bool { key.isEmpty }

    static let none = KeyCombo(key: "", flags: [])

    /// 「⇧⌘N」のような表記
    @MainActor var displayText: String {
        guard !key.isEmpty else { return "" }
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: key)
        item.keyEquivalentModifierMask = flags
        return CommandCatalog.shortcutText(for: item)
    }

    /// キー入力からショートカットを作る。修飾キーなしの文字キーは、入力と区別できないので受け付けない。
    @MainActor static func from(event: NSEvent) -> KeyCombo? {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        let special: [UInt16: Int] = [
            123: NSLeftArrowFunctionKey, 124: NSRightArrowFunctionKey, 125: NSDownArrowFunctionKey, 126: NSUpArrowFunctionKey,
            51: NSBackspaceCharacter, 96: NSF5FunctionKey, 97: NSF6FunctionKey, 98: NSF7FunctionKey, 100: NSF8FunctionKey,
            101: NSF9FunctionKey, 109: NSF10FunctionKey, 103: NSF11FunctionKey, 111: NSF12FunctionKey,
            122: NSF1FunctionKey, 120: NSF2FunctionKey, 99: NSF3FunctionKey, 118: NSF4FunctionKey,
        ]
        let key: String
        if let scalar = special[event.keyCode] {
            key = String(Character(UnicodeScalar(UInt16(scalar))!))
        } else if let base = event.characters(byApplyingModifiers: []), !base.isEmpty {
            key = base.lowercased()
        } else {
            return nil
        }
        let isFunctionKey = (NSF1FunctionKey...NSF12FunctionKey).contains(Int(key.unicodeScalars.first!.value))
        guard !flags.isEmpty || isFunctionKey else { return nil }
        return KeyCombo(key: key, flags: flags)
    }
}

/// ショートカットの変更（要件 K-01）。メニュー項目ごとに、変更したものだけを保存する。
enum ShortcutStore {
    private static let key = "shortcutOverrides"
    /// 元のショートカット（「初期設定に戻す」用）
    private static var defaults: [String: KeyCombo] = [:]

    static func identifier(for item: NSMenuItem) -> String? {
        guard let action = item.action else { return nil }
        return NSStringFromSelector(action) + "|" + item.title
    }

    static var overrides: [String: KeyCombo] {
        get {
            guard let data = AppDefaults.store.data(forKey: key) else { return [:] }
            return (try? JSONDecoder().decode([String: KeyCombo].self, from: data)) ?? [:]
        }
        set {
            AppDefaults.store.set(try? JSONEncoder().encode(newValue), forKey: key)
        }
    }

    /// メニューを作ったあとに呼ぶ。元のショートカットを覚えてから、変更を当てる。
    static func apply(to menu: NSMenu?) {
        let overrides = overrides
        forEachItem(in: menu) { item in
            guard let id = identifier(for: item) else { return }
            if defaults[id] == nil {
                defaults[id] = KeyCombo(key: item.keyEquivalent, flags: item.keyEquivalentModifierMask)
            }
            if let combo = overrides[id] ?? defaults[id] {
                item.keyEquivalent = combo.key
                item.keyEquivalentModifierMask = combo.flags
            }
        }
    }

    static func defaultCombo(for id: String) -> KeyCombo? { defaults[id] }

    static func set(_ combo: KeyCombo, for id: String) {
        var all = overrides
        all[id] = combo == defaults[id] ? nil : combo
        overrides = all
        apply(to: NSApp.mainMenu)
    }

    static func reset(_ id: String) {
        var all = overrides
        all[id] = nil
        overrides = all
        apply(to: NSApp.mainMenu)
    }

    static func resetAll() {
        overrides = [:]
        apply(to: NSApp.mainMenu)
    }

    /// 同じショートカットを使っているほかの項目（要件 K-01: 重なったら警告する）
    static func conflict(for combo: KeyCombo, excluding id: String, in menu: NSMenu? = NSApp.mainMenu) -> NSMenuItem? {
        guard !combo.isEmpty else { return nil }
        var found: NSMenuItem?
        forEachItem(in: menu) { item in
            guard found == nil, identifier(for: item) != id else { return }
            if KeyCombo(key: item.keyEquivalent, flags: item.keyEquivalentModifierMask) == combo { found = item }
        }
        return found
    }

    static func forEachItem(in menu: NSMenu?, _ body: (NSMenuItem) -> Void) {
        for item in menu?.items ?? [] {
            if let submenu = item.submenu {
                if submenu != NSApp.servicesMenu { forEachItem(in: submenu, body) }
            } else if !item.isSeparatorItem {
                body(item)
            }
        }
    }
}

/// コマンドラインツール `macorn`（要件 K-04）。ターミナルで `macorn .` と打つと、今いるフォルダを Macorn で開く。
enum CommandLineTool {
    static var script: String {
        let bundle = Bundle.main.bundleIdentifier ?? "dev.macorn.Macorn"
        return """
            #!/bin/sh
            # macorn: 指定したフォルダやファイル（省略時は今いるフォルダ）を Macorn で開く
            [ $# -eq 0 ] && set -- .
            for target in "$@"; do
              if [ -d "$target" ]; then
                open -b \(bundle) "$(cd "$target" && pwd -P)"
              else
                open -b \(bundle) "$(cd "$(dirname "$target")" && pwd -P)/$(basename "$target")"
              fi
            done

            """
    }

    /// /usr/local/bin に書けなければ ~/.local/bin に入れる（管理者のパスワードを求めないため）。
    static func installationDirectory() -> URL {
        let system = URL(fileURLWithPath: "/usr/local/bin")
        if FileManager.default.isWritableFile(atPath: system.path) { return system }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin")
    }

    @discardableResult
    static func install(to directory: URL = installationDirectory(), showResult: Bool = true) -> URL? {
        let target = directory.appendingPathComponent("macorn")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try script.write(to: target, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
        } catch {
            if showResult { NSAlert(error: error).runModal() }
            return nil
        }
        if showResult {
            let alert = NSAlert()
            alert.messageText = "コマンドラインツールをインストールしました"
            var text = "\(PathCompletion.abbreviate(target.path)) に入れました。ターミナルで `macorn .` と入力すると、今いるフォルダを Macorn で開けます。"
            if directory.path.hasSuffix(".local/bin") {
                text += "\n\n~/.local/bin が PATH に入っていない場合は、~/.zshrc に次の行を追加してください。\nexport PATH=\"$HOME/.local/bin:$PATH\""
            }
            alert.informativeText = text
            alert.runModal()
        }
        return target
    }
}
