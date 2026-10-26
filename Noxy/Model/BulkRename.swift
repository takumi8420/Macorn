import Foundation

/// 一括で名前を変更する規則（要件 F-13）。
nonisolated struct BulkRenameOptions: Equatable, Sendable {
    enum Mode: String, CaseIterable, Sendable {
        case replace, regex, sequence, changeCase

        var title: String {
            switch self {
            case .replace: "置換"
            case .regex: "正規表現"
            case .sequence: "連番"
            case .changeCase: "大文字・小文字"
            }
        }
    }

    enum CaseStyle: String, CaseIterable, Sendable {
        case lower, upper, capitalized

        var title: String {
            switch self {
            case .lower: "すべて小文字"
            case .upper: "すべて大文字"
            case .capitalized: "単語の先頭を大文字"
            }
        }
    }

    var mode: Mode = .replace
    /// 置換
    var find = ""
    var replacement = ""
    var caseSensitive = false
    /// 正規表現（置換後には $1 などが使える）
    var pattern = ""
    var template = ""
    /// 連番: 「接頭辞 + 番号」にする。拡張子は残す
    var prefix = ""
    var start = 1
    var step = 1
    var digits = 2
    /// 大文字・小文字
    var caseStyle: CaseStyle = .lower
    /// 拡張子も変更の対象にするか（置換・正規表現・大文字小文字）
    var includeExtension = false
}

nonisolated struct BulkRenamePreview: Equatable, Sendable {
    var url: URL
    var oldName: String
    var newName: String
    /// 変更できない理由（なければ nil）
    var problem: String?

    var isChanged: Bool { oldName != newName }
}

nonisolated enum BulkRename {
    struct InvalidPattern: Error {}

    static func newName(for name: String, isDirectory: Bool, index: Int, options: BulkRenameOptions) throws -> String {
        let (base, ext) = FileNaming.split(name, isDirectory: isDirectory)
        // 拡張子を対象にしないときは、拡張子より前だけを変える
        let baseOnly = !options.includeExtension
        let target = baseOnly ? base : name
        func join(_ changed: String) -> String {
            baseOnly && !ext.isEmpty ? "\(changed).\(ext)" : changed
        }

        switch options.mode {
        case .replace:
            guard !options.find.isEmpty else { return name }
            let compare: String.CompareOptions = options.caseSensitive ? [] : [.caseInsensitive]
            return join(target.replacingOccurrences(of: options.find, with: options.replacement, options: compare))
        case .regex:
            guard !options.pattern.isEmpty else { return name }
            let regex: NSRegularExpression
            do {
                regex = try NSRegularExpression(pattern: options.pattern, options: options.caseSensitive ? [] : [.caseInsensitive])
            } catch {
                throw InvalidPattern()
            }
            let range = NSRange(target.startIndex..., in: target)
            return join(regex.stringByReplacingMatches(in: target, range: range, withTemplate: options.template))
        case .sequence:
            let number = options.start + index * options.step
            let digits = max(1, min(options.digits, 10))
            let numberText = String(format: "%0\(digits)d", number)
            let newBase = options.prefix + numberText
            return ext.isEmpty ? newBase : "\(newBase).\(ext)"
        case .changeCase:
            let changed: String = switch options.caseStyle {
            case .lower: target.lowercased()
            case .upper: target.uppercased()
            case .capitalized: target.capitalized
            }
            return join(changed)
        }
    }

    /// 変更前後の一覧。名前が重なる・使えない名前になるものには理由を付ける。
    /// otherNames: 同じフォルダにある、変更対象でない項目の名前
    static func preview(
        _ items: [(url: URL, isDirectory: Bool)],
        options: BulkRenameOptions,
        otherNames: (URL) -> Set<String>
    ) -> [BulkRenamePreview] {
        var results: [BulkRenamePreview] = items.enumerated().map { index, item in
            let name = item.url.lastPathComponent
            do {
                let newName = try newName(for: name, isDirectory: item.isDirectory, index: index, options: options)
                return BulkRenamePreview(url: item.url, oldName: name, newName: newName, problem: FileNaming.validationError(for: newName))
            } catch {
                return BulkRenamePreview(url: item.url, oldName: name, newName: name, problem: "正規表現が正しくありません。")
            }
        }

        // 同じフォルダの中で名前が重ならないか（macOS は大文字・小文字を区別しないことが多いので、区別せずに比べる）
        var counts: [String: Int] = [:]
        for result in results {
            counts[key(result.url.deletingLastPathComponent(), result.newName), default: 0] += 1
        }
        var othersCache: [String: Set<String>] = [:]
        for index in results.indices where results[index].problem == nil && results[index].isChanged {
            let folder = results[index].url.deletingLastPathComponent()
            if counts[key(folder, results[index].newName), default: 0] > 1 {
                results[index].problem = "ほかの項目と同じ名前になります。"
                continue
            }
            let others = othersCache[folder.path] ?? Set(otherNames(folder).map { $0.lowercased() })
            othersCache[folder.path] = others
            if others.contains(results[index].newName.lowercased()) {
                results[index].problem = "同じ名前の項目がすでにあります。"
            }
        }
        return results
    }

    private static func key(_ folder: URL, _ name: String) -> String {
        folder.path + "/" + name.lowercased()
    }
}
