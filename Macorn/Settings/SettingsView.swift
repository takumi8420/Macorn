import AppKit
import Observation
import SwiftUI

/// 設定ウィンドウ（⌘,）。
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.title = "設定"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsView())
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 指定したタブを開く（タグの編集画面の「タグを管理…」など）
    func show(tab: SettingsTab) {
        SettingsNavigation.shared.tab = tab
        show()
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum SettingsTab: Hashable {
    case general, integration, sidebar, tags, shortcuts, history
}

/// 設定ウィンドウで開いているタブ（ほかの画面から切り替えられるように共有する）
@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()
    var tab: SettingsTab = .general
}

struct SettingsView: View {
    @Bindable private var navigation = SettingsNavigation.shared

    var body: some View {
        TabView(selection: $navigation.tab) {
            GeneralSettingsView()
                .tabItem { Label("一般", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            IntegrationSettingsView()
                .tabItem { Label("連携", systemImage: "terminal") }
                .tag(SettingsTab.integration)
            SidebarSettingsView()
                .tabItem { Label("サイドバー", systemImage: "sidebar.left") }
                .tag(SettingsTab.sidebar)
            TagManagerView()
                .tabItem { Label("タグ", systemImage: "tag") }
                .tag(SettingsTab.tags)
            ShortcutSettingsView()
                .tabItem { Label("ショートカット", systemImage: "keyboard") }
                .tag(SettingsTab.shortcuts)
            HistorySettingsView()
                .tabItem { Label("履歴", systemImage: "clock.arrow.circlepath") }
                .tag(SettingsTab.history)
        }
        .frame(width: 620, height: 520)
    }
}

// MARK: - 一般

private struct GeneralSettingsView: View {
    @AppStorage("showHiddenFiles") private var showHiddenFiles = false
    @AppStorage("confirmPaneTransfer") private var confirmPaneTransfer = true
    @AppStorage("calculateFolderSizes") private var calculateFolderSizes = true
    @AppStorage("vimKeyBindings") private var vimKeyBindings = false
    @AppStorage("colorFoldersByTag") private var colorFoldersByTag = true
    @AppStorage("checkForUpdates") private var checkForUpdates = true

    @Bindable private var theme = Theme.shared

    var body: some View {
        Form {
            Section("テーマ") {
                Picker("外観", selection: $theme.appearance) {
                    ForEach(Theme.Appearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("アクセントカラー") {
                    HStack(spacing: 8) {
                        ForEach(Theme.presets) { preset in
                            AccentSwatch(preset: preset, isSelected: theme.accentHex == preset.hex) {
                                theme.accentHex = preset.hex
                            }
                        }
                        ColorPicker("", selection: Binding(
                            get: { theme.accent },
                            set: { theme.accentHex = NSColor($0).hexString }
                        ), supportsOpacity: false)
                        .labelsHidden()
                        .help("好きな色を選ぶ")
                    }
                }
                Text("選択中の行・操作対象の画面の線・コマンドパレットの選択・Markdown のリンクなどの色です。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle("隠しファイルを表示する（⇧⌘.）", isOn: $showHiddenFiles)
                .onChange(of: showHiddenFiles) { _, value in
                    // 開いているウィンドウにもすぐ反映する
                    Preferences.showHiddenFiles = value
                }
            Toggle("フォルダのサイズを計算して表示する", isOn: $calculateFolderSizes)
                .onChange(of: calculateFolderSizes) { _, _ in
                    NotificationCenter.default.post(name: .macornDisplayPreferencesChanged, object: nil)
                }
            Toggle("Markdown・HTML・画像・PDF・動画などを選んだら、右にプレビューを出す（⌥⌘P）", isOn: Binding(
                get: { Preferences.filePreview },
                set: {
                    Preferences.filePreview = $0
                    NotificationCenter.default.post(name: .macornDisplayPreferencesChanged, object: nil)
                }
            ))
            Toggle("フォルダのアイコンをタグの色で塗る", isOn: $colorFoldersByTag)
                .onChange(of: colorFoldersByTag) { _, _ in
                    NotificationCenter.default.post(name: .macornDisplayPreferencesChanged, object: nil)
                }
            Toggle("F5 / F6 で反対側の画面へコピー・移動する前に確認する", isOn: $confirmPaneTransfer)
            Toggle("Vim 風のキー操作を使う（j / k で移動、gg / G で先頭・末尾）", isOn: $vimKeyBindings)
            Section("アップデート") {
                Toggle("起動時に新しいバージョンを確認する", isOn: $checkForUpdates)
                LabeledContent("お使いのバージョン") {
                    HStack {
                        Text(UpdateChecker.currentVersion)
                        Button("今すぐ確認") { UpdateChecker.checkManually() }
                    }
                }
                Text("新しいバージョンがあると知らせます。入れ替えは、ダウンロードした DMG から手動で行います。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 連携

private struct IntegrationSettingsView: View {
    @State private var terminal = TerminalLauncher.selected?.bundleIdentifier ?? ""
    @State private var editor = EditorLauncher.selected?.bundleIdentifier ?? ""
    @State private var newTab = Preferences.openTerminalInNewTab
    @State private var customEditors: [ExternalApp] = []
    @State private var revealsFiles = SystemFileViewer.revealsFiles

    var body: some View {
        Form {
            Section("ターミナル（⌥⌘T）") {
                Picker("使うアプリ", selection: $terminal) {
                    ForEach(ExternalApp.terminals) { app in
                        Text(app.isInstalled ? app.name : "\(app.name)（未インストール）")
                            .tag(app.bundleIdentifier)
                    }
                }
                .onChange(of: terminal) { _, value in Preferences.terminalBundleIdentifier = value }
                Toggle("新しいタブで開く", isOn: $newTab)
                    .disabled(!["com.googlecode.iterm2", "com.github.wez.wezterm"].contains(terminal))
                    .onChange(of: newTab) { _, value in Preferences.openTerminalInNewTab = value }
                Text("新しいタブで開けるのは iTerm2 と WezTerm です。それ以外は新しいウィンドウで開きます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("エディタ（⌥⌘E）") {
                Picker("使うアプリ", selection: $editor) {
                    ForEach(ExternalApp.editors + customEditors) { app in
                        Text(app.isInstalled ? app.name : "\(app.name)（未インストール）")
                            .tag(app.bundleIdentifier)
                    }
                }
                .onChange(of: editor) { _, value in Preferences.editorBundleIdentifier = value }
                Button("その他のアプリを選ぶ…", action: chooseEditor)
            }
            Section("Finder の代わりに使う") {
                Toggle("「Finder に表示」を Macorn で開く", isOn: Binding(get: { revealsFiles }, set: { setRevealsFiles($0) }))
                Text("ほかのアプリの「Finder に表示」で、その項目を Macorn で選んで表示します。すでに起動しているアプリは、開き直すと反映されます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("フォルダを開く既定のアプリは、macOS が Finder 以外に変えられないようにしています。Finder の中やデスクトップのフォルダは Finder で開きます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("コマンドラインツール") {
                Text("ターミナルで `macorn .` と入力すると、今いるフォルダを Macorn で開けます。")
                Button("インストール…") { CommandLineTool.install() }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadCustomEditor()
            refreshFileViewer()
        }
    }

    /// macOS 側の設定なので、ほかで変えられていることもある。開くたびに読み直す
    private func refreshFileViewer() {
        revealsFiles = SystemFileViewer.revealsFiles
    }

    private func setRevealsFiles(_ enabled: Bool) {
        SystemFileViewer.setRevealsFiles(enabled)
        refreshFileViewer()
    }

    private func loadCustomEditor() {
        guard let id = Preferences.editorBundleIdentifier,
              !ExternalApp.editors.contains(where: { $0.bundleIdentifier == id }),
              let app = ExternalApp.preferred(from: [], identifier: id) else { return }
        customEditors = [app]
    }

    private func chooseEditor() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "選択"
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        customEditors = [ExternalApp(name: FileManager.default.displayName(atPath: url.path), bundleIdentifier: id)]
        editor = id
    }
}

// MARK: - ショートカット（要件 K-01）

private struct ShortcutRow: Identifiable {
    var id: String
    var title: String
    var menu: String
    var combo: KeyCombo
}

private struct ShortcutSettingsView: View {
    @State private var rows: [ShortcutRow] = []
    @State private var recordingID: String?
    @State private var monitor: Any?
    @State private var message = ""
    @State private var pendingConflict: (id: String, combo: KeyCombo, other: NSMenuItem)?
    @State private var filter = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("操作を探す", text: $filter)
                    .textFieldStyle(.roundedBorder)
                Button("すべて初期設定に戻す") {
                    ShortcutStore.resetAll()
                    reload()
                }
            }
            List(filteredRows) { row in
                HStack {
                    VStack(alignment: .leading) {
                        Text(row.title)
                        Text(row.menu).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(recordingID == row.id ? "キーを押してください…" : (row.combo.isEmpty ? "なし" : row.combo.displayText)) {
                        startRecording(row.id)
                    }
                    .frame(minWidth: 150)
                    Button {
                        ShortcutStore.reset(row.id)
                        reload()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .help("初期設定に戻す")
                    Button {
                        ShortcutStore.set(.none, for: row.id)
                        reload()
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("ショートカットを外す")
                }
            }
            if let pendingConflict {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("\(pendingConflict.combo.displayText) は「\(pendingConflict.other.title)」で使われています。")
                    Spacer()
                    Button("置き換える") {
                        if let otherID = ShortcutStore.identifier(for: pendingConflict.other) {
                            ShortcutStore.set(.none, for: otherID)
                        }
                        ShortcutStore.set(pendingConflict.combo, for: pendingConflict.id)
                        self.pendingConflict = nil
                        reload()
                    }
                    Button("やめる") { self.pendingConflict = nil }
                }
            } else {
                Text(message.isEmpty ? "ボタンを押してから、割り当てたいキーを押してください（Esc で取り消し）。" : message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .onAppear(perform: reload)
        .onDisappear(perform: stopRecording)
    }

    private var filteredRows: [ShortcutRow] {
        guard !filter.isEmpty else { return rows }
        return rows.filter { FuzzyMatcher.match(filter, in: $0.title) != nil || FuzzyMatcher.match(filter, in: Romaji.transcribe($0.title)) != nil }
    }

    private func reload() {
        var result: [ShortcutRow] = []
        func walk(_ menu: NSMenu?, path: String) {
            for item in menu?.items ?? [] {
                if let submenu = item.submenu {
                    if submenu != NSApp.servicesMenu { walk(submenu, path: path.isEmpty ? submenu.title : path) }
                    continue
                }
                guard !item.isSeparatorItem, let id = ShortcutStore.identifier(for: item) else { continue }
                result.append(ShortcutRow(
                    id: id,
                    title: item.title,
                    menu: path,
                    combo: KeyCombo(key: item.keyEquivalent, flags: item.keyEquivalentModifierMask)
                ))
            }
        }
        walk(NSApp.mainMenu, path: "")
        rows = result
    }

    private func startRecording(_ id: String) {
        stopRecording()
        recordingID = id
        message = ""
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 記録中のキー入力はすべてここで受け取り、メニューやほかの画面には渡さない
            let keyCode = event.keyCode
            let combo = MainActor.assumeIsolated { KeyCombo.from(event: event) }
            MainActor.assumeIsolated {
                if keyCode == 53 { // Esc
                    stopRecording()
                    return
                }
                guard let combo else {
                    message = "⌘・⌥・⌃ などの修飾キーと一緒に押してください。"
                    return
                }
                stopRecording()
                if let other = ShortcutStore.conflict(for: combo, excluding: id) {
                    pendingConflict = (id, combo, other)
                } else {
                    ShortcutStore.set(combo, for: id)
                    reload()
                }
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recordingID = nil
    }
}

// MARK: - 履歴

private struct HistorySettingsView: View {
    @State private var folderCount = FolderHistory.shared.entries().count
    @State private var cleared = false

    var body: some View {
        Form {
            Section("フォルダの履歴（コマンドパレットのフォルダジャンプに使います）") {
                Text("\(folderCount) 件のフォルダを覚えています。")
                HStack {
                    Button("消えたフォルダを履歴から外す") {
                        FolderHistory.shared.removeMissing()
                        folderCount = FolderHistory.shared.entries().count
                    }
                    Button("履歴をすべて消す", role: .destructive) {
                        FolderHistory.shared.removeAll()
                        folderCount = 0
                    }
                }
            }
            Section("コマンドの使用履歴") {
                Button("使用履歴を消す", role: .destructive) {
                    AppDefaults.store.removeObject(forKey: "paletteCommandUsage")
                    cleared = true
                }
                if cleared { Text("消しました。").foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
    }
}


/// アクセントカラーの見本（丸）。「macOS に合わせる」は虹色の輪で表す
private struct AccentSwatch: View {
    let preset: Theme.Preset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if let hex = preset.hex {
                    Circle().fill(Color(nsColor: NSColor(hex: hex)))
                } else {
                    Circle().fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red], center: .center))
                }
                if isSelected {
                    Circle().fill(.white).frame(width: 6, height: 6)
                }
            }
            .frame(width: 18, height: 18)
            .overlay(Circle().strokeBorder(Color.primary.opacity(isSelected ? 0.5 : 0.12), lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .help(preset.name)
    }
}


// MARK: - サイドバー

/// サイドバーの構成: セクションの順番（ドラッグ）、表示・非表示、タグのセクションの追加・削除
private struct SidebarSettingsView: View {
    var store: SidebarStore = .shared
    var tags: TagStore = .shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("セクションはドラッグで並べ替えられます。チェックを外すと隠れます。タグを1つのセクションとして置いたり、自分でセクションを作ったりできます。")
                .font(.callout)
                .foregroundStyle(.secondary)
            List {
                ForEach(store.sections) { section in
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.tertiary)
                        Toggle(isOn: Binding(
                            get: { !store.isSectionHidden(section) },
                            set: { store.setSection(section, hidden: !$0) }
                        )) {
                            Label(section.title, systemImage: symbol(for: section))
                        }
                        Spacer()
                        if case .tag(let id) = section {
                            Button {
                                store.removeTagSection(id)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("このタグのセクションを外す")
                        }
                        if case .custom(let id) = section {
                            Button {
                                SidebarPrompts.renameSection(id, in: store)
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                            .help("名前を変更")
                            Button {
                                SidebarPrompts.deleteSection(id, in: store)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("このセクションを削除")
                        }
                    }
                }
                .onMove { store.moveSections(from: $0, to: $1) }
            }
            HStack {
                Menu("タグのセクションを追加") {
                    ForEach(tags.sortedTags.filter { !store.containsTagSection($0.id) }) { tag in
                        Button(tag.name) { store.addTagSection(tag.id) }
                    }
                }
                .disabled(tags.sortedTags.allSatisfy { store.containsTagSection($0.id) })
                .fixedSize()
                Button("セクションを作る…") { SidebarPrompts.createSection(in: store) }
                Spacer()
                Button("元に戻す") { store.resetSections() }
            }
            Text("お気に入りは「お気に入り」のタグが付いた項目の一覧です。自分で作るセクションは、タグ・フォルダ・ファイルをまとめる見出しで、項目には何も付きません。お気に入りと自分で作ったセクションにはタグも置けます（1つのタグは1か所だけ）。中の順番や置き場所はサイドバーでドラッグして変えられます。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func symbol(for section: SidebarSection) -> String {
        switch section {
        case .favorites: "star"
        case .tags: "tag"
        case .locations: "externaldrive"
        case .tag: "tag.fill"
        case .custom: "rectangle.stack"
        }
    }
}
