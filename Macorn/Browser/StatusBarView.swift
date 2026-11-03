import SwiftUI

struct StatusBarView: View {
    var state: PaneState
    /// 「n 件の変更」を押したとき（変更のウィンドウを開く）
    var onShowChanges: () -> Void = {}
    /// ターミナルのボタンを押したとき（ウィンドウの下にターミナルを出す・隠す）
    var onToggleTerminal: () -> Void = {}

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onToggleTerminal) {
                HStack(spacing: 3) {
                    Image(systemName: "terminal")
                    Text("ターミナル")
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .foregroundStyle(state.isTerminalVisible ? Color.accentColor : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(state.isTerminalVisible ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.06))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(state.isTerminalVisible ? "ターミナルを隠す（⌃`）" : "ウィンドウの下にターミナルを出す（⌃`）")
            Text(summary)
                .lineLimit(1)
            Spacer()
            if let branch = state.gitBranch {
                HStack(spacing: 3) {
                    if let root = state.gitRepositoryRoot {
                        Image(systemName: "shippingbox")
                        if let url = state.gitRemoteWebURL {
                            // 押すとリポジトリのページ（GitHub など）を開く
                            Button(state.gitRepositoryName ?? root.lastPathComponent) {
                                NSWorkspace.shared.open(url)
                            }
                            .buttonStyle(.link)
                            .fontWeight(.medium)
                            .help("\(url.absoluteString) をブラウザで開く")
                        } else {
                            Text(root.lastPathComponent)
                                .fontWeight(.medium)
                                .help(root.path)
                        }
                        Text("・")
                    }
                    Image(systemName: "arrow.triangle.branch")
                    Text(branch)
                    if state.gitChangeCount > 0 {
                        Text("・")
                        Button("\(state.gitChangeCount) 件の変更", action: onShowChanges)
                            .buttonStyle(.link)
                            .help("変更の差分を見る")
                    }
                }
                .help("Git のリポジトリ・ブランチと、コミットしていない変更の数")
            }
            if state.isLoading {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
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
