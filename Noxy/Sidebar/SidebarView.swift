import SwiftUI

struct SidebarView: View {
    var store: SidebarStore
    /// 操作対象の画面（2画面のときはその時々で変わる）
    var window: WindowModel
    var onSelect: (URL) -> Void

    var body: some View {
        List(selection: selection) {
            Section("よく使う項目") {
                ForEach(store.favorites) { item in
                    Label(item.name, systemImage: item.symbol)
                        .tag(item.id)
                        .contextMenu {
                            Button("サイドバーから削除") { store.removeFavorite(item.url) }
                        }
                }
                .onMove { store.moveFavorites(from: $0, to: $1) }
            }

            Section("場所") {
                ForEach(store.volumes) { item in
                    HStack {
                        Label(item.name, systemImage: item.symbol)
                        Spacer()
                        if item.isEjectable {
                            Button {
                                store.eject(item)
                            } label: {
                                Image(systemName: "eject.fill")
                            }
                            .buttonStyle(.borderless)
                            .help("取り出す")
                        }
                    }
                    .tag(item.id)
                    .contextMenu {
                        if item.isEjectable {
                            Button("取り出す") { store.eject(item) }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    /// 表示中のフォルダと同じ項目を選択状態にする。クリックされたらそのフォルダへ移動する。
    private var selection: Binding<String?> {
        Binding(
            get: {
                let path = window.activePane.currentURL.path
                let all = store.favorites + store.volumes
                return all.contains { $0.id == path } ? path : nil
            },
            set: { newValue in
                guard let newValue, newValue != window.activePane.currentURL.path else { return }
                onSelect(URL(fileURLWithPath: newValue))
            }
        )
    }
}
