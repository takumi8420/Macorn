import AppKit
import Observation

/// 1つの画面。VS Code のエディタのまとまりのように、上にタブの列を持ち、選んだタブのフォルダ（FileBrowserViewController）を出す。
/// タブはそれぞれ別の FileBrowserViewController で、戻る・進むの履歴や選択を別々に持つ。
final class PaneTabsController: NSViewController {
    private(set) var tabs: [FileBrowserViewController] = []
    private(set) var selectedIndex = 0
    let tabBar = PaneTabBarView()
    /// 選んだタブの中身を置くところ（ドラッグの置き場所の判定にも使う）
    let contentView = NSView()

    /// タブを押して選んだとき
    var onSelectTab: ((FileBrowserViewController) -> Void)?
    /// タブの「×」・中クリックで閉じるとき
    var onCloseTab: ((FileBrowserViewController) -> Void)?
    /// タブのドラッグを始めたとき
    var onBeginTabDrag: ((FileBrowserViewController, NSEvent, NSView) -> Void)?
    /// タブの列の空いた所をダブルクリックしたとき（新しいタブ）
    var onNewTab: (() -> Void)?

    /// この画面が操作対象か（選んだタブの見た目を変える）
    var isActiveGroup = false {
        didSet { if isActiveGroup != oldValue { reloadTabBar() } }
    }

    init(tabs: [FileBrowserViewController], selected: Int = 0) {
        super.init(nibName: nil, bundle: nil)
        for tab in tabs { addChild(tab) }
        self.tabs = tabs
        selectedIndex = min(max(selected, 0), max(tabs.count - 1, 0))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var selected: FileBrowserViewController? { tabs.indices.contains(selectedIndex) ? tabs[selectedIndex] : nil }

    func contains(_ browser: FileBrowserViewController) -> Bool {
        tabs.contains { $0 === browser }
    }

    func index(of browser: FileBrowserViewController) -> Int? {
        tabs.firstIndex { $0 === browser }
    }

    override func loadView() {
        let container = PaneBackgroundView()
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tabBar)
        container.addSubview(contentView)
        NSLayoutConstraint.activate([
            // ツールバーの下から並べる（ウィンドウの中身はツールバーの裏まで広がっている）
            tabBar.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: PaneTabBarView.height),
            contentView.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        tabBar.onSelect = { [weak self] index in
            guard let self, tabs.indices.contains(index) else { return }
            select(index)
            onSelectTab?(tabs[index])
        }
        tabBar.onClose = { [weak self] index in
            guard let self, tabs.indices.contains(index) else { return }
            let tab = tabs[index]
            // 押したボタンの処理が終わってから閉じる（ボタンを含むタブごと外すため）
            DispatchQueue.main.async { self.onCloseTab?(tab) }
        }
        tabBar.onBeginDrag = { [weak self] index, event, view in
            guard let self, tabs.indices.contains(index) else { return }
            onBeginTabDrag?(tabs[index], event, view)
        }
        tabBar.onDoubleClickEmpty = { [weak self] in self?.onNewTab?() }
        tabBar.onNewTab = { [weak self] in self?.onNewTab?() }
        view = container
        showSelected()
        observeTitles()
    }

    // MARK: - タブの出し入れ

    func insert(_ browser: FileBrowserViewController, at index: Int, select shouldSelect: Bool) {
        let index = min(max(index, 0), tabs.count)
        if browser.parent !== self { addChild(browser) }
        let wasSelected = selected
        tabs.insert(browser, at: index)
        if shouldSelect || wasSelected == nil {
            selectedIndex = index
        } else if let wasSelected, let kept = self.index(of: wasSelected) {
            selectedIndex = kept
        }
        if isViewLoaded { showSelected() }
        observeTitles()
    }

    /// タブを外す。選んでいたタブなら、右隣（なければ左隣）を選ぶ
    func remove(_ browser: FileBrowserViewController) {
        guard let index = index(of: browser) else { return }
        let wasSelected = selected
        tabs.remove(at: index)
        if browser.view.superview === contentView { browser.view.removeFromSuperview() }
        browser.removeFromParent()
        if wasSelected === browser {
            selectedIndex = min(index, max(tabs.count - 1, 0))
        } else if let wasSelected, let kept = self.index(of: wasSelected) {
            selectedIndex = kept
        }
        if isViewLoaded { showSelected() }
        observeTitles()
    }

    /// 同じ画面の中で、タブの順番を変える（index は動かす前の並びでの、置きたい位置）
    func move(_ browser: FileBrowserViewController, to index: Int) {
        guard let from = self.index(of: browser) else { return }
        var target = min(max(index, 0), tabs.count)
        if target > from { target -= 1 }
        guard target != from else { return }
        let wasSelected = selected
        tabs.remove(at: from)
        tabs.insert(browser, at: target)
        if let wasSelected, let kept = self.index(of: wasSelected) { selectedIndex = kept }
        reloadTabBar()
    }

    func select(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        selectedIndex = index
        if isViewLoaded { showSelected() }
    }

    /// 選んだタブの中身だけを出す
    private func showSelected() {
        for tab in tabs where tab !== selected && tab.isViewLoaded && tab.view.superview === contentView {
            tab.view.removeFromSuperview()
        }
        if let selected, selected.view.superview !== contentView {
            let view = selected.view
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: contentView.topAnchor),
                view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            ])
        }
        reloadTabBar()
    }

    func reloadTabBar() {
        guard isViewLoaded else { return }
        tabBar.items = tabs.map { tab in
            let url = tab.state.currentURL
            return PaneTabBarView.Item(
                title: TagLocation.displayName(for: url),
                icon: Self.icon(for: url),
                toolTip: url.isFileURL ? PathCompletion.abbreviate(url.path) : TagLocation.displayName(for: url)
            )
        }
        tabBar.selectedIndex = selectedIndex
        tabBar.isActiveGroup = isActiveGroup
    }

    /// 各タブのフォルダが変わったら、タブの名前を出し直す
    private func observeTitles() {
        guard isViewLoaded else { return }
        let tabs = self.tabs
        withObservationTracking {
            for tab in tabs { _ = tab.state.currentURL }
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.reloadTabBar()
                self?.observeTitles()
            }
        }
    }

    private static func icon(for url: URL) -> NSImage? {
        if !url.isFileURL {
            return NSImage(systemSymbolName: "tag.fill", accessibilityDescription: nil)
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 14, height: 14)
        return image
    }
}

// MARK: - タブの列

/// 画面の上のタブの列。タブを押すと選び、「×」・中クリックで閉じ、ドラッグでほかの画面や画面の端へ動かせる。
/// 地はすりガラス。選んだタブは中身と同じ地の平らな面で、下の中身とつながる（枠も影も付けない）。
/// マウスを乗せたタブはうすく塗る。
final class PaneTabBarView: NSView {
    static let height: CGFloat = 36

    struct Item: Equatable {
        var title: String
        var icon: NSImage?
        var toolTip: String
    }

    /// 並びが変わるたびに出し直す。タブの部品は作り直さず使い回す
    /// （押している最中のタブを外すと、そのあとのドラッグが届かなくなるため）
    var items: [Item] = [] { didSet { sync() } }
    var selectedIndex = 0 { didSet { if selectedIndex != oldValue { updateAppearance() } } }
    /// 分けているときの、操作対象の画面か（選んだタブの上の端に色の線を引く）
    var isActiveGroup = false { didSet { if isActiveGroup != oldValue { updateAppearance() } } }
    /// 画面を分けているか
    var isInSplit = false { didSet { if isInSplit != oldValue { updateAppearance() } } }

    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onBeginDrag: ((Int, NSEvent, NSView) -> Void)?
    var onDoubleClickEmpty: (() -> Void)?
    /// 「＋」を押したとき
    var onNewTab: (() -> Void)?

    private var itemViews: [PaneTabItemView] = []
    /// 地のすりガラス（後ろがうっすら透ける）と、下の区切り線。タブより奥に置く
    private let material: NSVisualEffectView = {
        let view = NSVisualEffectView()
        view.material = .titlebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }()
    private let separator = SeparatorLineView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(material)
        addSubview(separator)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 最後のタブのすぐ右の「＋」（Chrome と同じ）。押すと、この画面に新しいタブ
    private lazy var addButton: HoverIconButton = {
        let button = HoverIconButton(symbol: "plus", pointSize: 11, cornerRadius: 6)
        button.toolTip = "新しいタブ（⌘T）"
        button.setAccessibilityLabel("新しいタブ")
        button.target = self
        button.action = #selector(addClicked(_:))
        addSubview(button)
        return button
    }()

    static let addButtonSize: CGFloat = 24
    static let maxTabWidth: CGFloat = 190
    static let minTabWidth: CGFloat = 76
    /// 左端の余白と、タブどうしの間
    private static let inset: CGFloat = 6
    private static let gap: CGFloat = 3
    /// タブの上の余白（タブは下の端まで伸ばし、中身とつなげる）
    private static let topInset: CGFloat = 6

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        material.frame = bounds
        separator.frame = NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
        let width = tabWidth
        // 下の区切り線にもかぶせて、選んだタブが中身とつながって見えるようにする
        let height = bounds.height - Self.topInset
        var x = Self.inset
        for view in itemViews {
            view.frame = NSRect(x: x, y: Self.topInset, width: width, height: height)
            x += width + Self.gap
        }
        let size = Self.addButtonSize
        addButton.frame = NSRect(x: x + 1, y: Self.topInset + (height - 1 - size) / 2, width: size, height: size)
    }

    /// タブ1つの幅。「＋」の分を空けて、収まらなければ縮める
    private var tabWidth: CGFloat {
        guard !itemViews.isEmpty else { return 0 }
        let count = CGFloat(itemViews.count)
        let available = bounds.width - Self.inset * 2 - Self.addButtonSize - Self.gap * count
        return min(Self.maxTabWidth, max(Self.minTabWidth, available / count))
    }

    @objc private func addClicked(_ sender: Any?) { onNewTab?() }

    private func sync() {
        while itemViews.count > items.count {
            itemViews.removeLast().removeFromSuperview()
        }
        while itemViews.count < items.count {
            let view = PaneTabItemView()
            view.onSelect = { [weak self, weak view] in
                guard let self, let view, let index = itemViews.firstIndex(of: view) else { return }
                onSelect?(index)
            }
            view.onClose = { [weak self, weak view] in
                guard let self, let view, let index = itemViews.firstIndex(of: view) else { return }
                onClose?(index)
            }
            view.onBeginDrag = { [weak self, weak view] event in
                guard let self, let view, let index = itemViews.firstIndex(of: view) else { return }
                onBeginDrag?(index, event, view)
            }
            addSubview(view)
            itemViews.append(view)
        }
        for (view, item) in zip(itemViews, items) { view.apply(item) }
        _ = addButton
        updateAppearance()
        needsLayout = true
    }

    private func updateAppearance() {
        for (index, view) in itemViews.enumerated() {
            view.isSelected = index == selectedIndex
            view.isActiveGroup = isActiveGroup
            view.isInSplit = isInSplit
        }
    }

    /// x（このビューの座標）に置いたときの、タブの並びでの位置
    func insertionIndex(atX x: CGFloat) -> Int {
        let step = tabWidth + Self.gap
        guard step > Self.gap else { return 0 }
        return min(max(Int(((x - Self.inset) / step).rounded()), 0), itemViews.count)
    }

    /// 並びの位置 index の境目の x（このビューの座標）
    func insertionX(for index: Int) -> CGFloat {
        Self.inset + (tabWidth + Self.gap) * CGFloat(index) - Self.gap / 2
    }

    override func mouseDown(with event: NSEvent) {
        // タブのない所のダブルクリックで、新しいタブ
        if event.clickCount == 2 { onDoubleClickEmpty?() }
    }

}

/// 1px の区切り線（ライト・ダークに追従）
final class SeparatorLineView: NSView {
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = NSColor.separatorColor.cgColor
    }
}

/// タブ1つ。フォルダのアイコン・名前・「×」
final class PaneTabItemView: NSView {
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    var onBeginDrag: ((NSEvent) -> Void)?

    var isSelected = false { didSet { if isSelected != oldValue { updateAppearance() } } }
    var isActiveGroup = false { didSet { if isActiveGroup != oldValue { updateAppearance() } } }
    /// 画面を分けているか（分けていないときは、選んだタブをいつも濃く出す）
    var isInSplit = false { didSet { if isInSplit != oldValue { updateAppearance() } } }

    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let closeButton = HoverIconButton(symbol: "xmark", pointSize: 8.5, cornerRadius: 8)
    private var hovering = false { didSet { if hovering != oldValue { updateAppearance() } } }
    private var mouseDownPoint: NSPoint?

    private static let cornerRadius: CGFloat = 7

    init() {
        super.init(frame: .zero)
        iconView.imageScaling = .scaleProportionallyDown
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingMiddle
        label.cell?.truncatesLastVisibleLine = true
        closeButton.target = self
        closeButton.action = #selector(closeClicked(_:))
        closeButton.toolTip = "タブを閉じる（⌘W）"
        closeButton.setAccessibilityLabel("タブを閉じる")
        for view in [iconView, label, closeButton] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -3),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),
        ])
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// タブの名前・アイコンを入れ替える（部品はそのまま）
    func apply(_ item: PaneTabBarView.Item) {
        iconView.image = item.icon
        if label.stringValue != item.title { label.stringValue = item.title }
        if toolTip != item.toolTip { toolTip = item.toolTip }
        setAccessibilityLabel(item.title)
    }

    override var isFlipped: Bool { true }

    private func updateAppearance() {
        // 操作対象の画面の選んだタブだけを濃く。ほかの画面の選んだタブは一段落とす（半透明にはしない）
        label.textColor = isSelected && (isActiveGroup || !isInSplit) ? .labelColor : .secondaryLabelColor
        label.font = .systemFont(ofSize: 12, weight: isSelected ? .medium : .regular)
        closeButton.isHidden = !(isSelected || hovering)
        setAccessibilityValue(isSelected)
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        onSelect?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        // 少し動かしてから、ドラッグを始める（クリックだけでは選ぶだけ）
        guard hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 4 else { return }
        mouseDownPoint = nil
        onBeginDrag?(event)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownPoint = nil
    }

    /// 中クリックで閉じる（ブラウザや VS Code と同じ）
    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 { onClose?() }
    }

    @objc private func closeClicked(_ sender: Any?) { onClose?() }

    override func draw(_ dirtyRect: NSRect) {
        let radius = Self.cornerRadius
        if isSelected {
            // 選んだタブ：中身と同じ地の平らな面。上の角だけを丸め、下は中身へそのままつなげる
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 0, y: bounds.maxY))
            path.line(to: NSPoint(x: 0, y: radius))
            path.appendArc(withCenter: NSPoint(x: radius, y: radius), radius: radius, startAngle: 180, endAngle: 270)
            path.line(to: NSPoint(x: bounds.maxX - radius, y: 0))
            path.appendArc(withCenter: NSPoint(x: bounds.maxX - radius, y: radius), radius: radius, startAngle: 270, endAngle: 360)
            path.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY))
            path.close()
            NSColor.controlBackgroundColor.setFill()
            path.fill()
            // 分けているときは、操作対象の画面の選んだタブの上の端に、アクセントの色の線
            if isActiveGroup {
                NSGraphicsContext.saveGraphicsState()
                path.addClip()
                Theme.shared.accentColor.setFill()
                NSRect(x: 0, y: 0, width: bounds.width, height: 2).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
        } else if hovering {
            let rect = NSRect(x: 0, y: 1, width: bounds.width, height: bounds.height - 5)
            NSColor.labelColor.withAlphaComponent(0.07).setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        }
    }
}

/// 記号だけの小さなボタン。マウスを乗せると、角の丸い背景をうすく出す（タブの「×」・「＋」）
final class HoverIconButton: NSButton {
    private let cornerRadius: CGFloat
    private var hovering = false { didSet { if hovering != oldValue { needsDisplay = true } } }

    init(symbol: String, pointSize: CGFloat, cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .semibold))
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        contentTintColor = .secondaryLabelColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func draw(_ dirtyRect: NSRect) {
        if hovering || isHighlighted {
            NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.14 : 0.08).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).fill()
        }
        super.draw(dirtyRect)
    }
}
