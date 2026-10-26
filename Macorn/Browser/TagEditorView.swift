import SwiftUI

/// 項目のタグを編集する小さな画面（⌥⌘G・右クリック）。
/// 入力した名前でタグを探し、無ければその名前で作って付ける。「仕事/案件A」のように / で階層にできる。
struct TagEditorView: View {
    let urls: [URL]
    var store: TagStore
    var onClose: () -> Void
    var onManage: () -> Void

    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(urls.count == 1 ? "「\(urls[0].lastPathComponent)」のタグ" : "\(urls.count) 項目のタグ")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            TextField("タグを探す・作る（例: 仕事/案件A）", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(submit)

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    if let newName = newTagName {
                        Button {
                            create(newName)
                        } label: {
                            Label("「\(newName)」を作って付ける", systemImage: "plus.circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(filteredTags) { tag in
                        TagToggleRow(tag: tag, state: state(of: tag), count: store.count(for: tag.id), indent: query.isEmpty) {
                            store.toggle(tag.id, on: urls)
                        }
                    }
                    if store.tags.isEmpty, newTagName == nil {
                        Text("まだタグがありません。上に名前を入れて Enter で作れます。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    }
                }
            }
            .frame(height: 220)

            Divider()
            HStack {
                Button("タグを管理…", action: onManage)
                    .buttonStyle(.link)
                Spacer()
                Button("閉じる", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { focused = true }
    }

    private var filteredTags: [Tag] {
        let tags = store.sortedTags
        guard !query.isEmpty else { return tags }
        return tags
            .compactMap { tag -> (Tag, Int)? in
                let match = FuzzyMatcher.match(query, in: tag.name) ?? FuzzyMatcher.match(query, in: Romaji.transcribe(tag.name))
                return match.map { (tag, $0.score) }
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    /// 入力した名前のタグがまだ無ければ、その名前
    private var newTagName: String? {
        let name = TagStore.normalize(query)
        guard !name.isEmpty, store.tag(named: name) == nil else { return nil }
        return name
    }

    private func state(of tag: Tag) -> NSControl.StateValue {
        let count = urls.filter { store.hasTag(tag.id, on: $0) }.count
        return count == 0 ? .off : (count == urls.count ? .on : .mixed)
    }

    /// Enter: 同じ名前のタグがあれば付け外し、無ければ作って付ける
    private func submit() {
        let name = TagStore.normalize(query)
        guard !name.isEmpty else { return }
        if let existing = store.tag(named: name) {
            store.toggle(existing.id, on: urls)
        } else if let best = filteredTags.first, newTagName == nil {
            store.toggle(best.id, on: urls)
        } else {
            create(name)
        }
        query = ""
    }

    private func create(_ name: String) {
        guard let tag = store.createTag(named: name) else { return }
        store.assign(tag.id, to: urls)
        query = ""
    }
}

private struct TagToggleRow: View {
    let tag: Tag
    let state: NSControl.StateValue
    let count: Int
    let indent: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Image(systemName: state == .on ? "checkmark.square.fill" : (state == .mixed ? "minus.square.fill" : "square"))
                    .foregroundStyle(state == .off ? Color.secondary : Theme.shared.accent)
                Circle()
                    .fill(Color(nsColor: NSColor(hex: tag.color)))
                    .frame(width: 10, height: 10)
                Text(indent ? tag.leafName : tag.name)
                    .lineLimit(1)
                Spacer()
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, indent ? CGFloat(tag.depth) * 16 : 0)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 設定の「タグ」タブ: タグの作成・名前の変更・色の変更・削除。
struct TagManagerView: View {
    var store: TagStore = .shared
    @State private var newName = ""
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("新しいタグ（/ で階層。例: 仕事/案件A）", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("追加", action: add)
                    .disabled(TagStore.normalize(newName).isEmpty)
            }
            List {
                ForEach(store.sortedTags) { tag in
                    TagManagerRow(tag: tag, store: store, message: $message)
                }
            }
            Text(message.isEmpty ? "名前を変えると、下の階層のタグの名前もいっしょに変わります。タグを削除すると、下の階層のタグも削除し、付けていた項目からも外します。" : message)
                .font(.caption)
                .foregroundStyle(message.isEmpty ? Color.secondary : Color.orange)
        }
        .padding()
    }

    private func add() {
        guard !TagStore.normalize(newName).isEmpty else { return }
        store.createTag(named: newName)
        newName = ""
    }
}

private struct TagManagerRow: View {
    let tag: Tag
    var store: TagStore
    @Binding var message: String
    @State private var name = ""
    @State private var confirmingDelete = false

    var body: some View {
        HStack(spacing: 8) {
            ColorPicker("", selection: Binding(
                get: { Color(nsColor: NSColor(hex: tag.color)) },
                set: { store.setColor(tag.id, to: NSColor($0).hexString) }
            ), supportsOpacity: false)
            .labelsHidden()
            .frame(width: 40)
            TextField("名前", text: $name)
                .textFieldStyle(.plain)
                .onSubmit(rename)
                .padding(.leading, CGFloat(tag.depth) * 14)
            Text("\(store.count(for: tag.id)) 項目")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("このタグを削除")
        }
        .onAppear { name = tag.name }
        .onChange(of: tag.name) { _, value in name = value }
        .confirmationDialog("タグ「\(tag.name)」を削除しますか？", isPresented: $confirmingDelete) {
            Button("削除", role: .destructive) { store.deleteTag(tag.id) }
        } message: {
            Text("下の階層のタグも削除し、付けていた項目からも外します。ファイル自体は消えません。")
        }
    }

    private func rename() {
        if store.renameTag(tag.id, to: name) {
            message = ""
        } else {
            message = "「\(name)」には変えられません（同じ名前のタグがあるか、名前が空です）。"
            name = tag.name
        }
    }
}
