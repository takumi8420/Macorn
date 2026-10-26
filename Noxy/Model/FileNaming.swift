import Foundation

/// ファイル名まわりの決まりごと（重複しない名前・名前変更のときの選択範囲・入力チェック）。
nonisolated enum FileNaming {
    enum Style {
        /// 「名前 2.txt」「名前 3.txt」…（同名があるときの「両方残す」、新規作成）
        case numbered
        /// 「名前 のコピー.txt」「名前 のコピー 2.txt」…（同じフォルダへのコピー）
        case copy
    }

    static let newFolderName = "名称未設定フォルダ"
    static let newFileName = "名称未設定.txt"

    static func uniqueURL(
        for url: URL,
        isDirectory: Bool,
        style: Style,
        exists: (URL) -> Bool = FileNaming.itemExists
    ) -> URL {
        let folder = url.deletingLastPathComponent()
        let (base, ext) = split(url.lastPathComponent, isDirectory: isDirectory)

        func make(_ name: String) -> URL {
            folder.appendingPathComponent(ext.isEmpty ? name : "\(name).\(ext)")
        }

        switch style {
        case .numbered:
            if !exists(url) { return url }
            var index = 2
            while exists(make("\(base) \(index)")) { index += 1 }
            return make("\(base) \(index)")
        case .copy:
            // 「a のコピー」をさらに複製したときは「a のコピー 2」にする（Finder と同じ）
            let base = stripCopySuffix(base)
            let first = make("\(base) のコピー")
            if !exists(first) { return first }
            var index = 2
            while exists(make("\(base) のコピー \(index)")) { index += 1 }
            return make("\(base) のコピー \(index)")
        }
    }

    static func stripCopySuffix(_ base: String) -> String {
        // URL から取り出した名前は「ピ」が「ヒ＋゜」に分かれていることがあるので、合成した形にそろえてから調べる
        let base = base.precomposedStringWithCanonicalMapping
        guard let range = base.range(of: #" のコピー( \d+)?$"#, options: .regularExpression) else { return base }
        let stripped = String(base[..<range.lowerBound])
        return stripped.isEmpty ? base : stripped
    }

    /// 名前を「拡張子より前」と「拡張子」に分ける。フォルダと「.zshrc」のような名前は拡張子なし。
    static func split(_ name: String, isDirectory: Bool) -> (base: String, ext: String) {
        guard !isDirectory else { return (name, "") }
        let ns = name as NSString
        let ext = ns.pathExtension
        let base = ns.deletingPathExtension
        guard !ext.isEmpty, !base.isEmpty else { return (name, "") }
        return (base, ext)
    }

    /// 名前の変更を始めたときに選択しておく範囲（拡張子の前まで）。
    static func editableRange(for name: String, isDirectory: Bool) -> NSRange {
        let base = split(name, isDirectory: isDirectory).base
        return NSRange(location: 0, length: (base as NSString).length)
    }

    /// 名前として使えなければ、その理由を返す。
    static func validationError(for name: String) -> String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "名前を入力してください。"
        }
        if name.contains("/") {
            return "名前に「/」は使えません。"
        }
        if name == "." || name == ".." {
            return "「\(name)」は名前として使えません。"
        }
        if name.utf8.count > 255 {
            return "名前が長すぎます。"
        }
        return nil
    }

    /// シンボリックリンクはリンク先ではなくリンク自体の有無を見る。
    static func itemExists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }
}
