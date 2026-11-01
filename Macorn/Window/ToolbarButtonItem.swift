import AppKit

/// ツールバーのボタン。カーソルを乗せたときの説明を、ボタンそのものに付ける。
/// 画像だけの NSToolbarItem では説明が外枠（項目の枠）にしか付かず、macOS 26 ではボタンの上で説明が出ないため、
/// 自分で NSButton を作って項目のビューにする。
final class ToolbarButtonItem: NSToolbarItem {
    private let button = NSButton()

    override init(itemIdentifier: NSToolbarItem.Identifier) {
        super.init(itemIdentifier: itemIdentifier)
        button.bezelStyle = .toolbar
        button.imagePosition = .imageOnly
        button.setButtonType(.momentaryPushIn)
        button.target = self
        button.action = #selector(perform(_:))
        view = button
    }

    override var image: NSImage? {
        get { button.image }
        set { button.image = newValue }
    }

    override var label: String {
        didSet { button.setAccessibilityLabel(label) }
    }

    override var toolTip: String? {
        didSet { button.toolTip = toolTip }
    }

    override var isEnabled: Bool {
        didSet { button.isEnabled = isEnabled }
    }

    /// ボタンを押したら、項目に設定した操作を送る
    @objc private func perform(_ sender: Any?) {
        guard let action else { return }
        NSApp.sendAction(action, to: target, from: self)
    }

    /// ビューを持つ項目は自動では有効・無効が切り替わらないので、送り先に尋ねて決める
    override func validate() {
        guard let action else { return }
        if let validator = NSApp.target(forAction: action, to: target, from: self) as? NSToolbarItemValidation {
            isEnabled = validator.validateToolbarItem(self)
        } else {
            isEnabled = NSApp.target(forAction: action, to: target, from: self) != nil
        }
    }
}
