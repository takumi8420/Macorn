import AppKit
import SwiftUI

/// コマンドパレット（要件 5章）。⌘K でウィンドウ上部中央に開く。
final class PaletteController: NSObject {
    static let shared = PaletteController()

    private var panel: PalettePanel?
    private(set) var model: PaletteModel?
    private weak var windowController: BrowserWindowController?
    private var resignObserver: NSObjectProtocol?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle(for controller: BrowserWindowController) {
        if isVisible {
            close()
        } else {
            open(for: controller)
        }
    }

    func open(for controller: BrowserWindowController, query: String = "") {
        close()
        guard let parent = controller.window else { return }
        windowController = controller

        let commands = CommandCatalog.commands(window: parent)
        let model = PaletteModel(
            commands: commands,
            currentFolder: controller.browser.folderForRelativePaths,
            sidebarItems: SidebarStore.shared.favorites + SidebarStore.shared.volumes
        )
        model.query = query
        self.model = model

        let size = NSSize(width: 640, height: 420)
        let panel = PalettePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: PaletteView(
            model: model,
            onSubmit: { [weak self] modifiers in self?.execute(modifiers: modifiers) },
            onCancel: { [weak self] in self?.close() },
            onComplete: { [weak self] in self?.completePath() },
            onClick: { [weak self] index in
                self?.model?.selectedIndex = index
                self?.execute(modifiers: [])
            }
        ))

        let frame = parent.frame
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - 90 - size.height))
        parent.addChildWindow(panel, ordered: .above)
        if DebugFlags.isAutomating {
            // 自動テスト中は、利用者のキー入力を奪わないようキーウインドウにしない
            panel.orderFront(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
        self.panel = panel

        // ほかの場所をクリックしたら閉じる
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                #if DEBUG
                if ProcessInfo.processInfo.environment["MACORN_DEBUG_STEPS"] != nil { return }
                #endif
                self?.close()
            }
        }
    }

    func close() {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        guard let panel else { return }
        self.panel = nil
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        windowController?.window?.makeKey()
    }

    /// Tab: パス入力のときは補完する。
    private func completePath() {
        guard let model else { return }
        if model.mode == .path {
            let completed = PathCompletion.complete(model.query, relativeTo: model.currentFolder)
            if completed == model.query { NSSound.beep() } else { model.query = completed }
        } else if let item = model.selectedItem, case .folder(let url) = item.kind {
            // パス入力でなければ、選択中のフォルダのパスを入力欄に入れる
            model.query = PathCompletion.abbreviate(url.path) + "/"
        }
    }

    // MARK: - 実行

    /// Enter: 開く / 実行。⌘Enter: 反対側の画面で開く。⌥Enter: 新しいタブで開く。⌘⇧Enter: ターミナルで開く（要件 5.4）
    func execute(modifiers: NSEvent.ModifierFlags) {
        guard let model, let item = model.selectedItem, let controller = windowController else {
            NSSound.beep()
            return
        }
        close()

        switch item.kind {
        case .command(let action):
            CommandUsage.record(action)
            // パレットを閉じてウインドウがキーに戻ってから実行する
            Task { @MainActor in
                if !ActionRouter.send(action, in: controller.window) { NSSound.beep() }
            }
        case .tag(let id):
            openTag(id, modifiers: modifiers, in: controller)
        case .folder(let url), .path(let url), .file(let url):
            open(url, isFolder: FileTransfer.isDirectory(url) && url.pathExtension != "app", modifiers: modifiers, in: controller)
        }
    }

    private func openTag(_ id: UUID, modifiers: NSEvent.ModifierFlags, in controller: BrowserWindowController) {
        let url = TagLocation.url(for: id)
        let flags = modifiers.intersection([.command, .option, .shift])
        if flags == .option {
            controller.appDelegate?.windowControllerRequestsNewTab(controller, url: url)
        } else if flags == .command {
            let panes = controller.panes
            if !panes.isSplit { panes.openSplit(at: controller.browser.state.currentURL) }
            panes.otherPane?.navigate(to: url)
            panes.switchActivePane()
        } else {
            controller.browser.navigate(to: url)
            controller.browser.focusList()
        }
    }

    private func open(_ url: URL, isFolder: Bool, modifiers: NSEvent.ModifierFlags, in controller: BrowserWindowController) {
        let folder = isFolder ? url : url.deletingLastPathComponent()
        let selection: URL? = isFolder ? nil : url
        let flags = modifiers.intersection([.command, .option, .shift])

        if flags == [.command, .shift] {
            TerminalLauncher.open(folder)
        } else if flags == .option {
            controller.appDelegate?.windowControllerRequestsNewTab(controller, url: folder)
        } else if flags == .command {
            let panes = controller.panes
            if !panes.isSplit { panes.openSplit(at: folder) }
            if let other = panes.otherPane {
                other.navigate(to: folder, selecting: selection)
                panes.switchActivePane()
            }
        } else {
            controller.browser.navigate(to: folder, selecting: selection)
            controller.browser.focusList()
        }
    }
}

/// キー入力を受け取れる枠なしパネル。
final class PalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - 画面

struct PaletteView: View {
    var model: PaletteModel
    var onSubmit: (NSEvent.ModifierFlags) -> Void
    var onCancel: () -> Void
    var onComplete: () -> Void
    var onClick: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: modeSymbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                PaletteSearchField(
                    model: model,
                    onSubmit: onSubmit,
                    onCancel: onCancel,
                    onComplete: onComplete
                )
            }
            .padding(.horizontal, 14)
            .frame(height: 50)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                            PaletteRow(item: item, isSelected: index == model.selectedIndex)
                                .id(item.id)
                                .contentShape(Rectangle())
                                .onTapGesture { onClick(index) }
                        }
                        if model.items.isEmpty {
                            Text(emptyMessage)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 24)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: model.selectedIndex) { _, index in
                    if model.items.indices.contains(index) {
                        proxy.scrollTo(model.items[index].id)
                    }
                }
            }

            Divider()

            Text("↩ 開く・実行　⌘↩ 反対側の画面　⌥↩ 新しいタブ　⌘⇧↩ ターミナル　⇥ 補完　esc 閉じる")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .frame(height: 26)
        }
        .frame(width: 640, height: 420)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.12)))
    }

    private var modeSymbol: String {
        switch model.mode {
        case .all: "magnifyingglass"
        case .commands: "command"
        case .path: "folder"
        case .files: "doc.text.magnifyingglass"
        case .sidebar: "sidebar.left"
        }
    }

    private var emptyMessage: String {
        if model.isIndexingFiles { return "ファイルを集めています…" }
        return model.query.isEmpty ? "フォルダを開くと、ここに履歴が出ます" : "見つかりません"
    }
}

private struct PaletteRow: View {
    let item: PaletteItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(highlightedTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 8)
            if !item.detail.isEmpty {
                Text(item.detail)
                    .font(.system(size: 11, design: item.detail.first?.isLetter == true ? .default : .monospaced))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Theme.shared.accent : .clear)
        )
    }

    @ViewBuilder
    private var icon: some View {
        switch item.icon {
        case .symbol(let name):
            Image(systemName: name)
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
        case .file(let path):
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
        }
    }

    /// 一致した文字を太字にする
    private var highlightedTitle: AttributedString {
        var text = AttributedString()
        let positions = Set(item.highlights)
        for (index, character) in item.title.enumerated() {
            var part = AttributedString(String(character))
            if positions.contains(index) {
                part.font = .body.bold()
                if !isSelected { part.foregroundColor = Theme.shared.accent }
            }
            text += part
        }
        return text
    }
}

/// パレットの入力欄。矢印キー・Enter・Tab・Esc を受け取るため AppKit の NSTextField を使う。
private struct PaletteSearchField: NSViewRepresentable {
    var model: PaletteModel
    var onSubmit: (NSEvent.ModifierFlags) -> Void
    var onCancel: () -> Void
    var onComplete: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = PaletteTextField(string: model.query)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 20)
        field.placeholderString = "検索（> コマンド　/ ~ パス　@ ファイル　# サイドバー）"
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        // Tab 補完などで中身が変わったら入力欄に反映する
        if field.stringValue != model.query {
            field.stringValue = model.query
            field.currentEditor()?.selectedRange = NSRange(location: (model.query as NSString).length, length: 0)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PaletteSearchField

        init(parent: PaletteSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.model.query = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            let event = NSApp.currentEvent
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                parent.model.moveSelection(by: -1)
            case #selector(NSResponder.moveDown(_:)):
                parent.model.moveSelection(by: 1)
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)):
                parent.onSubmit(event?.modifierFlags ?? [])
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
            case #selector(NSResponder.insertTab(_:)):
                parent.onComplete()
            case Selector(("noop:")) where event?.keyCode == 36 || event?.keyCode == 76:
                // ⌘↩ などは noop として届くので、ここで受ける
                parent.onSubmit(event?.modifierFlags ?? [])
            default:
                return false
            }
            return true
        }
    }
}

private final class PaletteTextField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        Task { @MainActor in
            window.makeFirstResponder(self)
            self.currentEditor()?.moveToEndOfDocument(nil)
        }
    }
}
