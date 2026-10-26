import SwiftUI

struct StatusBarView: View {
    var state: PaneState

    var body: some View {
        HStack(spacing: 6) {
            Text(summary)
                .lineLimit(1)
            Spacer()
            if let branch = state.gitBranch {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.branch")
                    Text(branch)
                    if state.gitChangeCount > 0 {
                        Text("・\(state.gitChangeCount) 件の変更")
                    }
                }
                .help("Git のブランチと、コミットしていない変更の数")
            }
            if state.isLoading {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) { Divider() }
    }

    private var summary: String {
        var parts = [state.filterText.isEmpty ? "\(state.itemCount) 項目" : "\(state.visibleCount) / \(state.itemCount) 項目（絞り込み中）"]
        if state.selectedCount > 0 {
            parts[0] += " / \(state.selectedCount) 項目を選択中"
        }
        if let capacity = state.availableCapacity {
            parts.append("空き \(ByteCountFormatter.string(fromByteCount: capacity, countStyle: .file))")
        }
        return parts.joined(separator: " ・ ")
    }
}

/// フォルダを開けなかったときにリストの代わりに出す案内（要件 9.2）。
struct PaneMessageView: View {
    var state: PaneState
    var onOpenSettings: () -> Void

    var body: some View {
        if let error = state.error {
            VStack(spacing: 12) {
                Image(systemName: error.needsPermission ? "lock" : "exclamationmark.triangle")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text(error.message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 420)
                if error.needsPermission {
                    Button("システム設定を開く", action: onOpenSettings)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}
