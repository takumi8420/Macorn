import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// 全体で効くキー（ほかのアプリが前面のときも受け取る）。キーの位置（keyCode）と修飾キーで決める
nonisolated struct GlobalHotKey: Codable, Equatable, Sendable {
    var keyCode: UInt16
    var modifiers: UInt
    /// 「⌘G」のような表記（記録したときに作る）
    var display: String

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    init(keyCode: UInt16, flags: NSEvent.ModifierFlags, display: String) {
        self.keyCode = keyCode
        self.modifiers = flags.intersection(Self.relevantFlags).rawValue
        self.display = display
    }

    static let relevantFlags: NSEvent.ModifierFlags = [.command, .option, .shift, .control]

    /// 既定は ⌘G（Go。ファイルを選ぶ画面では使わないキー）
    static let defaultKey = GlobalHotKey(keyCode: UInt16(kVK_ANSI_G), flags: .command, display: "⌘G")

    /// 押されたキーがこのキーか（修飾キーは過不足なく同じとき）
    func matches(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        keyCode == self.keyCode && flags.intersection(Self.relevantFlags) == self.flags
    }

    /// 設定画面でのキー入力から作る。⌘・⌥・⌃ のどれかと一緒に押したものだけ受け付ける（文字の入力と区別するため）
    @MainActor static func from(event: NSEvent) -> GlobalHotKey? {
        let flags = event.modifierFlags.intersection(relevantFlags)
        guard !flags.intersection([.command, .option, .control]).isEmpty,
              let combo = KeyCombo.from(event: event) else { return nil }
        return GlobalHotKey(keyCode: event.keyCode, flags: flags, display: combo.displayText)
    }
}

/// ほかのアプリの「開く」「保存」の画面（macOS のファイルを選ぶ画面）を、Macorn で開いているフォルダへ移す。
/// macOS はこの画面をほかのアプリに置き換えさせないので、Default Folder X と同じく、
/// 画面が前面のときに決めたキーを押すと「フォルダへ移動」（⇧⌘G）にパスを打ち込む形にする。
/// キーの横取りとキー入力の送り込みに、アクセシビリティの許可が要る。
enum FilePanelJump {
    private static let enabledKey = "filePanelJumpEnabled"
    private static let hotKeyKey = "filePanelJumpHotKey"
    /// 自分で送ったキー入力の印（キーの横取りで自分の入力を拾わないため）
    nonisolated static let syntheticMarker: Int64 = 0x4D43524E

    /// 機能を使うか。初めはオフ（アクセシビリティの許可が要るため）
    static var isEnabled: Bool {
        get { AppDefaults.store.bool(forKey: enabledKey) }
        set {
            AppDefaults.store.set(newValue, forKey: enabledKey)
            update()
        }
    }

    static var hotKey: GlobalHotKey {
        get {
            guard let data = AppDefaults.store.data(forKey: hotKeyKey),
                  let key = try? JSONDecoder().decode(GlobalHotKey.self, from: data) else { return .defaultKey }
            return key
        }
        set {
            AppDefaults.store.set(try? JSONEncoder().encode(newValue), forKey: hotKeyKey)
            update()
        }
    }

    // MARK: 許可

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// macOS の許可の確認を出し、システム設定のアクセシビリティを開く
    static func requestTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary // kAXTrustedCheckOptionPrompt
        if !AXIsProcessTrustedWithOptions(options),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: キーの横取り

    private static var tap: CFMachPort?
    private static var tapSource: CFRunLoopSource?
    private static var activationObserver: NSObjectProtocol?

    /// 起動時に呼ぶ。許可はあとから付くこともあるので、Macorn が前面に来るたびに付け直す
    static func start() {
        update()
        guard activationObserver == nil else { return }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { if isEnabled && tap == nil { update() } }
        }
    }

    /// 設定に合わせて、キーの横取りを付け外しする
    static func update() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        }
        tap = nil
        tapSource = nil
        guard isEnabled, isTrusted else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: tapCallback, userInfo: nil) else { return }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        tapSource = source
    }

    /// 横取りしたキー入力を見る。決めたキーで、前面がファイルを選ぶ画面のときだけ受け取り、ほかはそのまま通す
    private static let tapCallback: CGEventTapCallBack = { _, type, event, _ in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            MainActor.assumeIsolated { if let tap = FilePanelJump.tap { CGEvent.tapEnable(tap: tap, enable: true) } }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown,
              event.getIntegerValueField(.eventSourceUserData) != FilePanelJump.syntheticMarker else {
            return Unmanaged.passUnretained(event)
        }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        // キーの横取りはメインのランループに付けているので、ここはメインスレッドで動く
        let consumed = MainActor.assumeIsolated { FilePanelJump.handleKey(keyCode: keyCode, flags: flags) }
        return consumed ? nil : Unmanaged.passUnretained(event)
    }

    /// 決めたキーで、前面がほかのアプリのファイルを選ぶ画面なら受け取って移す（true）。ほかは通す（false）
    private static func handleKey(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        guard hotKey.matches(keyCode: keyCode, flags: flags),
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              isFilePanelFocused(in: app.processIdentifier) else { return false }
        guard let folder = currentFolder() else {
            NSSound.beep()
            return true
        }
        Task { await typeGoToFolder(folder.path) }
        return true
    }

    // MARK: ファイルを選ぶ画面か

    /// 前面のウィンドウ（または、その上に出ているシート）が、macOS のファイルを選ぶ画面か
    static func isFilePanelFocused(in pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        guard let window: AXUIElement = attribute(app, kAXFocusedWindowAttribute) else { return false }
        if isFilePanel(window) { return true }
        let children: [AXUIElement] = attribute(window, kAXChildrenAttribute) ?? []
        return children.contains { (attribute($0, kAXRoleAttribute) as String?) == kAXSheetRole && isFilePanel($0) }
    }

    /// 「開く」の画面は open-panel、「保存」の画面は save-panel という識別子を持つ
    private static func isFilePanel(_ element: AXUIElement) -> Bool {
        let identifier: String? = attribute(element, kAXIdentifierAttribute)
        return identifier == "open-panel" || identifier == "save-panel"
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    // MARK: 移す先と、キー入力の送り込み

    /// いちばん手前の Macorn のウィンドウの、操作対象の画面で開いているフォルダ
    static func currentFolder() -> URL? {
        for window in NSApp.orderedWindows {
            guard let controller = window.windowController as? BrowserWindowController else { continue }
            let url = controller.browser.state.currentURL
            return url.isFileURL ? url : nil
        }
        return nil
    }

    /// 「フォルダへ移動」（⇧⌘G）を開き、パスを打ち込んで移る
    private static func typeGoToFolder(_ path: String) async {
        // 押したキーの修飾キー（⌘ など）を離すまで待つ（押したままだと、送ったキーと混ざるため）
        for _ in 0..<30 {
            let held = CGEventSource.flagsState(.combinedSessionState)
                .intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
            if held.isEmpty { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        postKey(CGKeyCode(kVK_ANSI_G), flags: [.maskCommand, .maskShift])
        try? await Task.sleep(for: .milliseconds(400))
        postKey(CGKeyCode(kVK_ANSI_A), flags: .maskCommand)
        postText(path)
        try? await Task.sleep(for: .milliseconds(200))
        postKey(CGKeyCode(kVK_Return), flags: [])
    }

    private static func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: isDown) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
            event.post(tap: .cgSessionEventTap)
        }
    }

    /// 文字をそのまま送る（キーボードの配列に関係なく、日本語のフォルダ名も打てる）
    private static func postText(_ text: String) {
        let units = Array(text.utf16)
        var index = 0
        while index < units.count {
            let chunk = Array(units[index..<min(index + 16, units.count)])
            index += chunk.count
            for isDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: isDown) else { continue }
                event.flags = []
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
                event.post(tap: .cgSessionEventTap)
            }
        }
    }
}
