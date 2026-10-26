import AppKit
import SwiftUI

/// 一括で名前を変更する画面（要件 F-13）。変更前後を見比べてから実行する。
struct BulkRenameView: View {
    let items: [(url: URL, isDirectory: Bool)]
    var onCancel: () -> Void
    var onApply: ([(url: URL, newName: String)]) -> Void

    @State private var options = BulkRenameOptions()

    private var previews: [BulkRenamePreview] {
        BulkRename.preview(items, options: options) { folder in
            let all = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            let renamed = Set(items.filter { $0.url.deletingLastPathComponent().path == folder.path }.map(\.url.lastPathComponent))
            return all.subtracting(renamed)
        }
    }

    var body: some View {
        let previews = previews
        let problems = previews.filter { $0.problem != nil }.count
        let changes = previews.filter { $0.isChanged && $0.problem == nil }.count

        VStack(alignment: .leading, spacing: 12) {
            Text("\(items.count) 項目の名前を変更")
                .font(.headline)

            Picker("方法", selection: $options.mode) {
                ForEach(BulkRenameOptions.Mode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            settings
                .frame(minHeight: 70, alignment: .top)

            Table(previews, columns: {
                TableColumn("変更前") { preview in
                    Text(preview.oldName).lineLimit(1).truncationMode(.middle)
                }
                TableColumn("変更後") { preview in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(preview.newName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(preview.problem != nil ? Color.red : (preview.isChanged ? Color.primary : Color.secondary))
                        if let problem = preview.problem {
                            Text(problem).font(.caption).foregroundStyle(.red)
                        }
                    }
                }
            })
            .frame(minHeight: 220)

            HStack {
                if problems > 0 {
                    Label("\(problems) 項目は変更できません。規則を直してください。", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                } else {
                    Text("\(changes) 項目の名前が変わります。")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                Spacer()
                Button("キャンセル", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("名前を変更") {
                    onApply(previews.filter(\.isChanged).map { ($0.url, $0.newName) })
                }
                .keyboardShortcut(.defaultAction)
                .disabled(problems > 0 || changes == 0)
            }
        }
        .padding(20)
        .frame(width: 620, height: 520)
    }

    @ViewBuilder
    private var settings: some View {
        Form {
            switch options.mode {
            case .replace:
                TextField("探す文字", text: $options.find)
                TextField("置き換える文字", text: $options.replacement)
                HStack {
                    Toggle("大文字と小文字を区別", isOn: $options.caseSensitive)
                    Toggle("拡張子も対象にする", isOn: $options.includeExtension)
                }
            case .regex:
                TextField("正規表現（例: (\\d+)-(.*)）", text: $options.pattern)
                    .font(.system(.body, design: .monospaced))
                TextField("置き換え後（$1 などで一致した部分を使えます）", text: $options.template)
                    .font(.system(.body, design: .monospaced))
                HStack {
                    Toggle("大文字と小文字を区別", isOn: $options.caseSensitive)
                    Toggle("拡張子も対象にする", isOn: $options.includeExtension)
                }
            case .sequence:
                TextField("名前（この後ろに番号を付けます）", text: $options.prefix)
                HStack {
                    Stepper("開始番号: \(options.start)", value: $options.start, in: 0...99_999)
                    Stepper("増やす数: \(options.step)", value: $options.step, in: 1...100)
                    Stepper("桁数: \(options.digits)", value: $options.digits, in: 1...6)
                }
            case .changeCase:
                Picker("変換", selection: $options.caseStyle) {
                    ForEach(BulkRenameOptions.CaseStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("拡張子も対象にする", isOn: $options.includeExtension)
            }
        }
        .formStyle(.columns)
    }
}

extension BulkRenamePreview: Identifiable {
    var id: String { url.path }
}

/// 情報を見る（要件 F-12）。
struct InfoView: View {
    let url: URL
    @State private var folderSize: Int64?
    @State private var itemCount: Int?

    var body: some View {
        let values = try? url.resourceValues(forKeys: [
            .localizedTypeDescriptionKey, .fileSizeKey, .totalFileSizeKey, .creationDateKey,
            .contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey,
        ])
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let isDirectory = values?.isDirectory == true

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.lastPathComponent)
                        .font(.headline)
                        .textSelection(.enabled)
                    Text(values?.localizedTypeDescription ?? "")
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                row("サイズ", sizeText(values: values, isDirectory: isDirectory))
                if isDirectory, let itemCount { row("項目数", "\(itemCount) 項目") }
                row("場所", PathCompletion.abbreviate(url.deletingLastPathComponent().path))
                row("作成日", values?.creationDate.map(Self.format) ?? "--")
                row("変更日", values?.contentModificationDate.map(Self.format) ?? "--")
                row("アクセス権", permissionsText(attributes))
                row("所有者", "\(attributes?[.ownerAccountName] as? String ?? "?") / \(attributes?[.groupOwnerAccountName] as? String ?? "?")")
                if values?.isSymbolicLink == true,
                   let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) {
                    row("リンク先", destination)
                }
            }
            HStack {
                Text(url.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                Spacer()
                Button("パスをコピー") { PathCopier.copy([url], style: .full) }
            }
        }
        .padding(20)
        .frame(width: 420, alignment: .leading)
        .task {
            guard isDirectory else { return }
            let url = url
            let result = await Task.detached(priority: .utility) {
                (FileTransfer.totalSize(of: [url]), (try? FileManager.default.contentsOfDirectory(atPath: url.path).count) ?? 0)
            }.value
            folderSize = result.0
            itemCount = result.1
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    private func sizeText(values: URLResourceValues?, isDirectory: Bool) -> String {
        if isDirectory {
            guard let folderSize else { return "計算中…" }
            return "\(ByteCountFormatter.string(fromByteCount: folderSize, countStyle: .file))（\(folderSize.formatted()) バイト）"
        }
        let size = Int64(values?.totalFileSize ?? values?.fileSize ?? 0)
        return "\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))（\(size.formatted()) バイト）"
    }

    private func permissionsText(_ attributes: [FileAttributeKey: Any]?) -> String {
        guard let mode = (attributes?[.posixPermissions] as? NSNumber)?.intValue else { return "--" }
        let symbols = ["r", "w", "x"]
        var text = ""
        for shift in stride(from: 6, through: 0, by: -3) {
            for (index, symbol) in symbols.enumerated() {
                text += (mode >> (shift + 2 - index)) & 1 == 1 ? symbol : "-"
            }
        }
        return "\(text)（\(String(mode, radix: 8))）"
    }

    private static func format(_ date: Date) -> String {
        date.formatted(date: .long, time: .standard)
    }
}

/// 情報ウインドウを開く。同じ項目なら前に出すだけにする。
enum InfoPanels {
    private static var panels: [String: NSPanel] = [:]

    static func show(_ urls: [URL]) {
        for (offset, url) in urls.prefix(10).enumerated() {
            if let panel = panels[url.path], panel.isVisible {
                panel.orderFront(nil)
                continue
            }
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
                styleMask: [.titled, .closable, .utilityWindow],
                backing: .buffered, defer: true
            )
            panel.title = "\(url.lastPathComponent) の情報"
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            let host = NSHostingController(rootView: InfoView(url: url))
            host.sizingOptions = [.preferredContentSize]
            panel.contentViewController = host
            panel.center()
            panel.setFrameOrigin(NSPoint(x: panel.frame.minX + CGFloat(offset * 24), y: panel.frame.minY - CGFloat(offset * 24)))
            if DebugFlags.isAutomating {
                panel.orderFront(nil)
            } else {
                panel.makeKeyAndOrderFront(nil)
            }
            panels[url.path] = panel
        }
    }

    static var visibleCount: Int { panels.values.filter(\.isVisible).count }
}
