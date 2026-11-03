import AppKit

/// 内蔵ターミナルを置く場所
enum TerminalPosition: String, CaseIterable {
    case bottom, left, right

    var title: String {
        switch self {
        case .bottom: "下に置く"
        case .left: "左に置く"
        case .right: "右に置く"
        }
    }

    var symbol: String {
        switch self {
        case .bottom: "rectangle.bottomhalf.inset.filled"
        case .left: "rectangle.lefthalf.inset.filled"
        case .right: "rectangle.righthalf.inset.filled"
        }
    }
}

/// ウィンドウの下に出す内蔵ターミナル（要件 T-30）。表示中のフォルダでシェルを開き、フォルダを移ったら追いかけて cd する。
final class TerminalPanelController: NSViewController {
    private(set) var emulator = TerminalEmulator(columns: 80, rows: 12)
    private(set) var terminalView: TerminalView!
    private var process: TerminalProcess?
    private let titleLabel = NSTextField(labelWithString: "ターミナル")
    /// 閉じるボタンを押した
    var onClose: (() -> Void)?
    /// 置き場所を選んだ
    var onChangePosition: ((TerminalPosition) -> Void)?
    private let positionButton = NSButton()
    private var currentPosition = TerminalPosition.bottom
    /// シェルを起動するフォルダ（表示中のフォルダ）
    var folderProvider: (() -> URL)?
    /// シェルに打ちかけの入力があるか（あれば cd を送らない）
    private var hasPendingInput = false
    /// 最後に cd したフォルダ（同じフォルダには送らない）
    private var lastDirectory: String?
    private var startFolder = FileManager.default.homeDirectoryForCurrentUser

    var isRunning: Bool { process?.isRunning == true }

    override func loadView() {
        let container = NSView()

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        let icon = NSImageView(image: NSImage(systemSymbolName: "terminal", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        icon.symbolConfiguration = .init(pointSize: 11, weight: .medium)
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingHead
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "ターミナルを閉じる") ?? NSImage(),
                             target: self, action: #selector(closePanel(_:)))
        close.isBordered = false
        close.contentTintColor = .secondaryLabelColor
        close.toolTip = "ターミナルを閉じる（⌃`）"
        positionButton.isBordered = false
        positionButton.contentTintColor = .secondaryLabelColor
        positionButton.target = self
        positionButton.action = #selector(showPositionMenu(_:))
        positionButton.toolTip = "ターミナルを置く場所（下・左・右）"
        updatePositionButton(currentPosition)
        let separator = NSBox()
        separator.boxType = .separator
        for view in [icon, titleLabel, positionButton, close, separator] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(view)
        }

        terminalView = TerminalView(emulator: emulator)
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        terminalView.registerForFileDrops()
        terminalView.send = { [weak self] data in self?.sendFromKeyboard(data) }
        terminalView.onResize = { [weak self] columns, rows in self?.process?.resize(columns: columns, rows: rows) }
        terminalView.onRestartRequest = { [weak self] in self?.restart() }
        emulator.respond = { [weak self] answer in self?.process?.write(answer) }

        container.addSubview(header)
        container.addSubview(terminalView)
        NSLayoutConstraint.activate([
            // 左・右に置いたときは、ツールバーの下から始める（上に置くとツールバーに隠れる）
            header.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 24),
            icon.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: positionButton.leadingAnchor, constant: -8),
            positionButton.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -10),
            positionButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            close.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -10),
            close.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            separator.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            terminalView.topAnchor.constraint(equalTo: header.bottomAnchor),
            terminalView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            terminalView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view = container
    }

    /// どんな開き方でも（区切り線を引き出したときも）、出てきたらシェルを起動する
    override func viewDidAppear() {
        super.viewDidAppear()
        if !isRunning, !terminalView.isProcessExited {
            startIfNeeded(in: folderProvider?() ?? FileManager.default.homeDirectoryForCurrentUser)
        }
    }

    // MARK: - シェル

    /// まだ動いていなければ、folder でシェルを起動する
    func startIfNeeded(in folder: URL) {
        guard !isRunning else { return }
        startFolder = folder
        start()
    }

    private func start() {
        loadViewIfNeeded()
        let process = TerminalProcess()
        process.onData = { [weak self] data in
            guard let self else { return }
            emulator.feed(data)
            terminalView.contentDidChange()
            updateTitle()
        }
        process.onExit = { [weak self] in self?.processDidExit() }
        let size = terminalView.gridSize
        emulator.resize(columns: size.columns, rows: size.rows)
        guard process.start(in: startFolder, columns: emulator.columns, rows: emulator.rows) else {
            emulator.feed("シェルを起動できませんでした。\r\n")
            terminalView.contentDidChange()
            return
        }
        self.process = process
        terminalView.isProcessExited = false
        lastDirectory = startFolder.standardizedFileURL.path
        hasPendingInput = false
        updateTitle()
    }

    private func restart() {
        emulator.feed("\u{1B}[2J\u{1B}[3J\u{1B}[H")
        start()
    }

    private func processDidExit() {
        process = nil
        terminalView.isProcessExited = true
        emulator.feed("\r\n\u{1B}[2m[プロセスが終了しました。Return で新しく開きます]\u{1B}[0m\r\n")
        terminalView.contentDidChange()
    }

    private func sendFromKeyboard(_ data: Data) {
        // Return・⌃C・⌃U で打ちかけの入力はなくなる。それ以外の文字を打ったら打ちかけとみなす
        if let last = data.last, [0x0D, 0x03, 0x15].contains(last) {
            hasPendingInput = false
        } else if !data.starts(with: [0x1B]) {
            hasPendingInput = true
        }
        process?.write(data)
    }

    /// Macorn で表示中のフォルダが変わったら、シェルが手すきのときだけ cd する
    /// （コマンドの実行中や、打ちかけの入力があるときは邪魔しない）
    func follow(_ folder: URL) {
        guard folder.isFileURL, let process, process.isRunning else { return }
        let path = folder.standardizedFileURL.path
        guard path != lastDirectory, path != emulator.reportedDirectory else { return }
        guard !hasPendingInput, process.isShellInForeground, !emulator.isAlternateScreen else { return }
        lastDirectory = path
        // 先頭の空白は、zsh の設定次第で履歴に残さないため
        process.write(" cd -- \(TerminalView.shellQuoted(path))\r")
    }

    private func updateTitle() {
        let directory = emulator.reportedDirectory ?? lastDirectory ?? startFolder.path
        let shown = emulator.title.isEmpty ? PathCompletion.abbreviate(directory) : emulator.title
        if titleLabel.stringValue != shown { titleLabel.stringValue = shown }
    }

    // MARK: - 表示

    func focus() {
        view.window?.makeFirstResponder(terminalView)
    }

    var hasFocus: Bool { view.window?.firstResponder === terminalView }

    @objc private func closePanel(_ sender: Any?) {
        onClose?()
    }

    /// 置き場所のボタンの絵を、今の置き場所に合わせる
    func updatePositionButton(_ position: TerminalPosition) {
        currentPosition = position
        positionButton.image = NSImage(systemSymbolName: position.symbol, accessibilityDescription: "ターミナルを置く場所")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
    }

    @objc private func showPositionMenu(_ sender: NSButton) {
        let menu = NSMenu()
        for position in TerminalPosition.allCases {
            let item = NSMenuItem(title: position.title, action: #selector(choosePosition(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = position.rawValue
            item.image = NSImage(systemSymbolName: position.symbol, accessibilityDescription: nil)
            item.state = position == currentPosition ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc private func choosePosition(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let position = TerminalPosition(rawValue: raw) else { return }
        onChangePosition?(position)
    }

    /// ウィンドウを閉じるとき
    func tearDown() {
        process?.terminate()
        process = nil
    }

    // MARK: - 自動操作用

    #if DEBUG
    var debugLayout: String {
        let header = titleLabel.superview
        return "panel=\(view.frame) header=\(header?.frame ?? .zero) title='\(titleLabel.stringValue)' \(titleLabel.frame) term=\(terminalView.frame) subviews=\(view.subviews.map { "\(type(of: $0)) \($0.frame)" })"
    }

    func debugSend(_ text: String) {
        process?.write(text.replacingOccurrences(of: "\\r", with: "\r"))
    }
    #endif
}

/// 画面（1〜6 画面）と内蔵ターミナルを並べる。ターミナルは下・左・右のどこにでも置ける
final class WorkspaceSplitViewController: NSSplitViewController {
    let terminalItem: NSSplitViewItem
    let terminal: TerminalPanelController
    private let panesItem: NSSplitViewItem
    private(set) var position: TerminalPosition

    init(panes: NSViewController) {
        terminal = TerminalPanelController()
        terminalItem = NSSplitViewItem(viewController: terminal)
        panesItem = NSSplitViewItem(viewController: panes)
        position = Preferences.terminalPosition
        super.init(nibName: nil, bundle: nil)
        splitView.dividerStyle = .thin
        panesItem.minimumThickness = 160
        terminalItem.canCollapse = true
        terminalItem.holdingPriority = .init(260)
        terminalItem.isCollapsed = true
        arrange()
        // 開いているかどうかは覚えない（起動したときはいつも閉じておく）
        terminal.updatePositionButton(position)
        terminal.onChangePosition = { [weak self] position in self?.move(to: position) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isTerminalVisible: Bool { !terminalItem.isCollapsed }

    /// 置き場所に合わせて、向きと順番を決める
    private func arrange() {
        for item in splitViewItems { removeSplitViewItem(item) }
        splitView.isVertical = position != .bottom
        terminalItem.minimumThickness = position == .bottom ? 90 : 220
        if position == .left {
            addSplitViewItem(terminalItem)
            addSplitViewItem(panesItem)
        } else {
            addSplitViewItem(panesItem)
            addSplitViewItem(terminalItem)
        }
    }

    /// ターミナルを下・左・右へ移す（動いているシェルはそのまま）
    func move(to newPosition: TerminalPosition) {
        guard newPosition != position else { return }
        let wasVisible = isTerminalVisible
        let hadFocus = terminal.hasFocus
        position = newPosition
        Preferences.terminalPosition = newPosition
        terminalItem.isCollapsed = true
        arrange()
        terminal.updatePositionButton(newPosition)
        if wasVisible {
            terminalItem.isCollapsed = false
            splitView.layoutSubtreeIfNeeded()
            resizeTerminalToDefault()
            if hadFocus { terminal.focus() }
        }
    }

    /// ターミナルの大きさを、ウィンドウの 3 分の 1 くらいにする
    private func resizeTerminalToDefault() {
        let length = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
        guard length > 300 else { return }
        let terminalLength = length * 0.36
        splitView.setPosition(position == .left ? terminalLength : length - terminalLength, ofDividerAt: 0)
    }

    /// ターミナルの区切り線を掴みやすくする
    override func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect, forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
        let rect = super.splitView(splitView, effectiveRect: proposedEffectiveRect, forDrawnRect: drawnRect, ofDividerAt: dividerIndex)
        return DividerGrab.rect(rect, vertical: splitView.isVertical)
    }

    func showTerminal(in folder: URL) {
        if terminalItem.isCollapsed {
            terminalItem.isCollapsed = false
            // はじめて開くときは、3 分の 1 くらいにする
            let thickness = splitView.isVertical ? terminal.view.frame.width : terminal.view.frame.height
            if thickness < 100 {
                splitView.layoutSubtreeIfNeeded()
                resizeTerminalToDefault()
            }
        }
        terminal.startIfNeeded(in: folder)
        terminal.focus()
    }

    func hideTerminal() {
        terminalItem.isCollapsed = true
    }
}
