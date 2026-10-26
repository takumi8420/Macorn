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
        case .tags: nil
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

final class FileCellView: NSTableCellView {
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

    func configure(with node: FileNode, gitStatus: GitFileStatus? = nil, tags: [Tag] = [], folderColor: String? = nil, showsLocation: Bool = false) {
        if isEditingName { endEditing() }
        let entry = node.entry
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
            textField?.attributedStringValue = text
        }
        // VoiceOver で Git の状態も読み上げる（要件 9.3）
        if column == .name {
            let status = badge?.toolTip.map { "、\($0)" } ?? ""
            setAccessibilityLabel(entry.name + status)
        }
        // 隠しファイルは Finder と同じく薄く表示する
        alphaValue = entry.isHidden ? 0.5 : 1
        toolTip = column == .name ? entry.path : nil
    }
}
