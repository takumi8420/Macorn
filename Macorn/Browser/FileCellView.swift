import AppKit

/// リスト表示の列（要件 V-01）。
enum FileColumn: String, CaseIterable {
    case name
    case dateModified
    case size
    case kind
    case tags

    var identifier: NSUserInterfaceItemIdentifier { NSUserInterfaceItemIdentifier(rawValue) }

    var title: String {
        switch self {
        case .name: "名前"
        case .dateModified: "変更日"
        case .size: "サイズ"
        case .kind: "種類"
        case .tags: "タグ"
        }
    }

    /// 並べ替えの基準（タグの列では並べ替えない）
    var sortKey: FileSortKey? {
        switch self {
        case .name: .name
        case .dateModified: .dateModified
        case .size: .size
        case .kind: .kind
        case .tags: .tags
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .name: 320
        case .dateModified: 150
        case .size: 80
        case .kind: 140
        case .tags: 150
        }
    }

    var minWidth: CGFloat {
        self == .name ? 120 : 50
    }
}

extension NSAttributedString.Key {
    /// 一覧の名前の欄で、押すとリポジトリのページを開く部分（「持ち主/リポジトリ」）
    static let repositoryLink = NSAttributedString.Key("macornRepositoryLink")
}

final class FileCellView: NSTableCellView, NSGestureRecognizerDelegate {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    private let column: FileColumn
    /// Git の状態の印（名前の列の右端）
    private var badge: NSTextField?
    /// Git の印を押したとき（差分を開く）。nil なら押せない
    var onBadgeClick: (() -> Void)? {
        didSet {
            badgeClick?.isEnabled = onBadgeClick != nil
        }
    }
    private var badgeClick: NSClickGestureRecognizer?
    /// 名前の欄の「持ち主/リポジトリ」を押したときに開くページ
    private var repositoryURL: URL?
    private var repositoryClick: NSClickGestureRecognizer?
    /// 「持ち主/リポジトリ」の後ろに敷く、ボタンらしい角丸の背景
    private var repositoryPill: NSView?

    init(column: FileColumn) {
        self.column = column
        super.init(frame: .zero)
        identifier = column.identifier

        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = column == .name ? .byTruncatingMiddle : .byTruncatingTail
        label.cell?.truncatesLastVisibleLine = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if column == .size { label.alignment = .right }
        if column != .name { label.textColor = .secondaryLabelColor }
        addSubview(label)
        textField = label

        var constraints = [
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
        ]
        if column == .name {
            let image = NSImageView()
            image.translatesAutoresizingMaskIntoConstraints = false
            image.imageScaling = .scaleProportionallyUpOrDown
            addSubview(image)
            imageView = image
            let badge = NSTextField(labelWithString: "")
            badge.translatesAutoresizingMaskIntoConstraints = false
            badge.font = .monospacedSystemFont(ofSize: 10, weight: .bold)
            badge.setContentCompressionResistancePriority(.required, for: .horizontal)
            badge.setContentHuggingPriority(.required, for: .horizontal)
            addSubview(badge)
            self.badge = badge
            let click = NSClickGestureRecognizer(target: self, action: #selector(badgeClicked(_:)))
            click.isEnabled = false
            badge.addGestureRecognizer(click)
            badgeClick = click
            // 「持ち主/リポジトリ」を押したときだけ受け取る（ほかの所のクリックは行の選択のまま）
            let repoClick = NSClickGestureRecognizer(target: self, action: #selector(repositoryClicked(_:)))
            repoClick.delegate = self
            label.addGestureRecognizer(repoClick)
            repositoryClick = repoClick
            let pill = NSView()
            pill.wantsLayer = true
            pill.layer?.cornerRadius = 4
            pill.isHidden = true
            addSubview(pill, positioned: .below, relativeTo: label)
            repositoryPill = pill
            constraints.removeAll { $0.firstAnchor == label.trailingAnchor }
            constraints += [
                badge.centerYAnchor.constraint(equalTo: centerYAnchor),
                badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
                label.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -4),
                image.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
                image.centerYAnchor.constraint(equalTo: centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 16),
                image.heightAnchor.constraint(equalToConstant: 16),
                label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 5),
            ]
        } else {
            constraints.append(label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2))
        }
        NSLayoutConstraint.activate(constraints)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 「● 仕事  ● 重要」のように、色の丸とタグ名を並べる
    static func tagText(_ tags: [Tag]) -> NSAttributedString {
        let text = NSMutableAttributedString()
        for (index, tag) in tags.enumerated() {
            if index > 0 { text.append(NSAttributedString(string: "  ")) }
            text.append(NSAttributedString(string: "● ", attributes: [.foregroundColor: NSColor(hex: tag.color)]))
            text.append(NSAttributedString(string: tag.leafName, attributes: [.foregroundColor: NSColor.labelColor, .font: NSFont.systemFont(ofSize: 12)]))
        }
        // 装飾つきの文字は欄の折り返しの設定を使わないので、ここで1行に収める（はみ出したら末尾を省略）
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
        return text
    }

    private static func color(for status: GitFileStatus?) -> NSColor {
        switch status {
        case .modified, .renamed: .systemOrange
        case .added, .untracked: .systemGreen
        case .deleted, .conflicted: .systemRed
        case .ignored, nil: .tertiaryLabelColor
        }
    }

    private static func description(for status: GitFileStatus) -> String {
        switch status {
        case .modified: "変更あり"
        case .added: "追加（ステージ済み）"
        case .untracked: "Git で管理していないファイル"
        case .deleted: "削除"
        case .renamed: "名前の変更"
        case .conflicted: "競合"
        case .ignored: "Git で無視"
        }
    }

    private(set) var isEditingName = false

    /// 名前の変更（要件 F-03）。一覧のその場で入力欄にする。
    func beginEditing(delegate: NSTextFieldDelegate) {
        guard let textField else { return }
        isEditingName = true
        textField.isEditable = true
        textField.isSelectable = true
        textField.drawsBackground = true
        textField.backgroundColor = .textBackgroundColor
        textField.lineBreakMode = .byClipping
        textField.cell?.isScrollable = true
        textField.focusRingType = .exterior
        textField.delegate = delegate
    }

    func endEditing() {
        guard let textField else { return }
        isEditingName = false
        textField.isEditable = false
        textField.isSelectable = false
        textField.drawsBackground = false
        textField.lineBreakMode = .byTruncatingMiddle
        textField.cell?.isScrollable = false
        textField.focusRingType = .none
        textField.delegate = nil
    }

    @objc private func badgeClicked(_ sender: Any?) {
        onBadgeClick?()
    }

    @objc private func repositoryClicked(_ sender: NSClickGestureRecognizer) {
        guard let repositoryURL else { return }
        NSWorkspace.shared.open(repositoryURL)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
        guard gestureRecognizer === repositoryClick, let textField, let rect = repositoryLinkRect() else { return false }
        return rect.contains(gestureRecognizer.location(in: textField))
    }

    /// 名前の欄のうち「持ち主/リポジトリ」が描かれている範囲（欄の座標）。見えていなければ nil
    func repositoryLinkRect() -> NSRect? {
        guard repositoryURL != nil, let textField, !isEditingName else { return nil }
        let text = textField.attributedStringValue
        var range = NSRange(location: NSNotFound, length: 0)
        text.enumerateAttribute(.repositoryLink, in: NSRange(location: 0, length: text.length)) { value, found, stop in
            if value != nil { range = found; stop.pointee = true }
        }
        guard range.location != NSNotFound else { return nil }
        // 欄と同じ条件（1行・はみ出したら省略）で並べて、その部分の位置を求める
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: max(textField.bounds.width - 4, 1), height: 1000))
        container.maximumNumberOfLines = 1
        container.lineBreakMode = .byTruncatingTail
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
        // 省略されて見えない部分は除く
        let used = layout.usedRect(for: container)
        rect = rect.intersection(used)
        guard rect.width > 4 else { return nil }
        // 欄の中の文字の位置に合わせる（左の余白 2pt、上下は欄いっぱい）
        return NSRect(x: rect.minX + 2, y: 0, width: rect.width, height: textField.bounds.height)
    }

    override func layout() {
        super.layout()
        updateRepositoryPill()
    }

    private func updateRepositoryPill() {
        guard let pill = repositoryPill else { return }
        guard let textField, let rect = repositoryLinkRect() else {
            pill.isHidden = true
            return
        }
        let frame = convert(rect, from: textField)
        pill.frame = NSRect(x: frame.minX - 4, y: frame.midY - 9, width: frame.width + 7, height: 18)
        pill.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.07).cgColor
        pill.isHidden = false
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateRepositoryPill()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if let textField, let rect = repositoryLinkRect() {
            addCursorRect(convert(rect, from: textField), cursor: .pointingHand)
        }
    }

    /// 「  ⎇ main」（ブランチの印とブランチ名。小さく、アクセントの色で）
    /// ブランチ名の後ろに添える「持ち主/リポジトリ」（リモートがあるとき）
    static func repositoryText(_ webURL: URL?, paragraph: NSParagraphStyle) -> NSAttributedString {
        guard let webURL, let name = GitRepository.repositoryName(of: webURL) else { return NSAttributedString() }
        let color = NSColor.secondaryLabelColor
        let font = NSFont.systemFont(ofSize: 11)
        let text = NSMutableAttributedString(string: "  ", attributes: [.font: font])
        if let symbol = NSImage(systemSymbolName: "shippingbox", accessibilityDescription: "リポジトリ")?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .regular).applying(.init(paletteColors: [color]))) {
            let attachment = NSTextAttachment()
            attachment.image = symbol
            attachment.bounds = NSRect(x: 0, y: -1, width: symbol.size.width, height: symbol.size.height)
            text.append(NSAttributedString(attachment: attachment))
            text.append(NSAttributedString(string: " ", attributes: [.font: font]))
        }
        text.append(NSAttributedString(string: name, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
        ]))
        // 先頭の空白を除いた「印と名前」を押せる部分にする
        text.addAttribute(.repositoryLink, value: webURL, range: NSRange(location: 2, length: text.length - 2))
        return text
    }

    static func branchText(_ branch: String, paragraph: NSParagraphStyle) -> NSAttributedString {
        let color = NSColor.controlAccentColor
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let text = NSMutableAttributedString(string: "  ", attributes: [.font: font])
        if let symbol = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "ブランチ")?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold).applying(.init(paletteColors: [color]))) {
            let attachment = NSTextAttachment()
            attachment.image = symbol
            attachment.bounds = NSRect(x: 0, y: -1, width: symbol.size.width, height: symbol.size.height)
            text.append(NSAttributedString(attachment: attachment))
            text.append(NSAttributedString(string: " ", attributes: [.font: font]))
        }
        text.append(NSAttributedString(string: branch.isEmpty ? "git" : branch, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
        ]))
        return text
    }

    func configure(with node: FileNode, gitStatus: GitFileStatus? = nil, tags: [Tag] = [], folderColor: String? = nil, showsLocation: Bool = false) {
        if isEditingName { endEditing() }
        let entry = node.entry
        repositoryURL = column == .name ? entry.gitRemoteWebURL : nil
        switch column {
        case .name:
            textField?.attributedStringValue = NSAttributedString(string: "")
            textField?.stringValue = entry.name
            // フォルダは、付いているタグの色で塗る
            imageView?.image = entry.isFolder ? node.icon(tintedWith: folderColor) : node.icon
            // Git で無視されているものは薄く、変更のあるものには印を付ける（要件 T-21）
            textField?.textColor = gitStatus == .ignored ? .tertiaryLabelColor : .labelColor
            if entry.isFolder, let gitStatus, gitStatus != .ignored {
                badge?.stringValue = "●"
                badge?.textColor = gitStatus == .untracked ? .systemGreen : .systemOrange
                badge?.toolTip = "中に変更があります"
            } else {
                badge?.stringValue = gitStatus?.badge ?? ""
                badge?.textColor = Self.color(for: gitStatus)
                badge?.toolTip = gitStatus.map(Self.description(for:))
            }
        case .dateModified:
            textField?.stringValue = entry.dateModified.map(Self.dateFormatter.string(from:)) ?? "--"
        case .size:
            textField?.stringValue = entry.size.map {
                ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
            } ?? "--"
        case .kind:
            textField?.stringValue = entry.kind
        case .tags:
            textField?.attributedStringValue = Self.tagText(tags)
            toolTip = tags.isEmpty ? nil : tags.map(\.name).joined(separator: "、")
        }
        // Git リポジトリのフォルダは、名前の後ろにブランチ名を添える（リポジトリだと分かるように）
        if column == .name, !showsLocation, let branch = entry.gitBranch {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            let text = NSMutableAttributedString(string: entry.name, attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: textField?.textColor ?? .labelColor,
                .paragraphStyle: paragraph,
            ])
            text.append(Self.branchText(branch, paragraph: paragraph))
            text.append(Self.repositoryText(entry.gitRemoteWebURL, paragraph: paragraph))
            textField?.attributedStringValue = text
            if badge?.toolTip == nil { badge?.toolTip = "Git リポジトリ（ブランチ \(branch.isEmpty ? "不明" : branch)）" }
        }
        // タグの一覧では、いろいろなフォルダの項目が並ぶので、名前の後ろに場所を添える
        if column == .name, showsLocation {
            // 1行に収め、はみ出したら場所の方（後ろ）を省略する
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            let text = NSMutableAttributedString(string: entry.name, attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ])
            text.append(NSAttributedString(
                string: "  " + PathCompletion.abbreviate(entry.url.deletingLastPathComponent().path),
                attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 11), .paragraphStyle: paragraph]
            ))
            if let branch = entry.gitBranch {
                text.append(Self.branchText(branch, paragraph: paragraph))
                text.append(Self.repositoryText(entry.gitRemoteWebURL, paragraph: paragraph))
            }
            textField?.attributedStringValue = text
        }
        // VoiceOver で Git の状態も読み上げる（要件 9.3）
        if column == .name {
            let status = badge?.toolTip.map { "、\($0)" } ?? ""
            setAccessibilityLabel(entry.name + status)
        }
        // 隠しファイルは Finder と同じく薄く表示する
        alphaValue = entry.isHidden ? 0.5 : 1
        toolTip = column == .name ? [entry.path, entry.gitRemoteWebURL.map { "リポジトリ名を押すと開く: \($0.absoluteString)" }].compactMap { $0 }.joined(separator: "\n") : nil
        window?.invalidateCursorRects(for: self)
        needsLayout = true
    }
}
