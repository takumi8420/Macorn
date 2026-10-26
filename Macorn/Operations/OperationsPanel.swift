import AppKit
import Observation
import SwiftUI

/// 実行中のファイル操作1件。
@Observable
final class FileOperation: Identifiable {
    enum Kind {
        case copy, move, delete, compress, expand

        var verb: String {
            switch self {
            case .copy: "コピー"
            case .move: "移動"
            case .delete: "削除"
            case .compress: "圧縮"
            case .expand: "展開"
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let itemCount: Int
    var totalBytes: Int64 = 0
    var completedBytes: Int64 = 0
    var currentName = ""
    var isFinished = false

    @ObservationIgnored let progress = TransferProgress()

    init(kind: Kind, itemCount: Int) {
        self.kind = kind
        self.itemCount = itemCount
    }

    var title: String { "\(itemCount) 項目を\(kind.verb)中…" }

    var fraction: Double? {
        guard totalBytes > 0 else { return nil }
        return min(1, Double(completedBytes) / Double(totalBytes))
    }

    func cancel() { progress.cancel() }

    /// 別スレッドで進んでいる値を画面用の値に写す。
    func syncFromProgress() {
        completedBytes = progress.completedBytes
        currentName = progress.currentName
    }
}

@Observable
final class OperationsStore {
    var operations: [FileOperation] = []
}

/// ファイル操作の進み具合を出す小さなウィンドウ（要件 F-09）。
/// すぐ終わる操作でちらつかないよう、0.5秒以上かかったときだけ表示する。
final class OperationsPanelController {
    static let shared = OperationsPanelController()

    let store = OperationsStore()

    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 90),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: true
        )
        panel.title = "ファイル操作"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        let host = NSHostingController(rootView: OperationsView(store: store))
        host.sizingOptions = [.preferredContentSize]
        panel.contentViewController = host
        panel.center()
        return panel
    }()

    var isPanelVisible: Bool { panel.isVisible }

    func start(_ operation: FileOperation) {
        store.operations.append(operation)
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            if !operation.isFinished { panel.orderFront(nil) }
        }
    }

    func finish(_ operation: FileOperation) {
        operation.isFinished = true
        store.operations.removeAll { $0 === operation }
        if store.operations.isEmpty { panel.orderOut(nil) }
    }
}

struct OperationsView: View {
    var store: OperationsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if store.operations.isEmpty {
                Text("実行中の操作はありません")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.operations) { operation in
                OperationRow(operation: operation)
            }
        }
        .padding(16)
        .frame(width: 400, alignment: .leading)
    }
}

private struct OperationRow: View {
    var operation: FileOperation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(operation.title)
                    .font(.headline)
                Spacer()
                Button {
                    operation.cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("中止")
            }
            if let fraction = operation.fraction {
                ProgressView(value: fraction)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var detail: String {
        var parts: [String] = []
        if operation.totalBytes > 0 {
            let done = ByteCountFormatter.string(fromByteCount: operation.completedBytes, countStyle: .file)
            let total = ByteCountFormatter.string(fromByteCount: operation.totalBytes, countStyle: .file)
            parts.append("\(done) / \(total)")
        }
        if !operation.currentName.isEmpty { parts.append(operation.currentName) }
        return parts.joined(separator: " ・ ")
    }
}
