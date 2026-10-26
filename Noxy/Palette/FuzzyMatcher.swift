import Foundation

nonisolated struct FuzzyMatch: Equatable, Sendable {
    var score: Int
    /// 一致した文字の位置（候補の文字列の何文字目か）。表示で強調するのに使う
    var positions: [Int]
}

/// あいまい検索（要件 C-02）。入力した文字が順番どおりに含まれていれば一致とし、
/// 連続している・単語の先頭に当たっている一致ほど点数を高くする（fzf と同じ考え方）。
nonisolated enum FuzzyMatcher {
    private static let separators: Set<Character> = [" ", "/", "-", "_", ".", "›", "　", "（", "("]

    static func match(_ query: String, in candidate: String) -> FuzzyMatch? {
        let pattern = Array(query.lowercased().filter { !$0.isWhitespace })
        guard !pattern.isEmpty else { return FuzzyMatch(score: 0, positions: []) }
        let original = Array(candidate)
        let chars = original.map { Character(String($0).lowercased()) }
        guard pattern.count <= chars.count else { return nil }

        // 前から順に当てはめて、一致するかどうかを確かめる
        var queryIndex = 0
        var lastMatch = -1
        for (index, char) in chars.enumerated() where queryIndex < pattern.count && char == pattern[queryIndex] {
            queryIndex += 1
            lastMatch = index
        }
        guard queryIndex == pattern.count else { return nil }

        // 最後の一致から後ろ向きに当てはめ直し、できるだけまとまった一致にする
        var positions: [Int] = []
        var index = lastMatch
        var patternIndex = pattern.count - 1
        while index >= 0, patternIndex >= 0 {
            if chars[index] == pattern[patternIndex] {
                positions.append(index)
                patternIndex -= 1
            }
            index -= 1
        }
        positions.reverse()

        var score = 0
        for (offset, position) in positions.enumerated() {
            score += 16
            if position == 0 { score += 12 }
            if isWordStart(position, in: original) { score += 10 }
            if offset > 0 {
                let gap = position - positions[offset - 1] - 1
                score += gap == 0 ? 15 : -min(gap, 8)
            }
        }
        // 短い候補ほど少しだけ優先する
        score -= min(chars.count / 8, 10)
        return FuzzyMatch(score: score, positions: positions)
    }

    private static func isWordStart(_ index: Int, in chars: [Character]) -> Bool {
        guard index > 0 else { return true }
        let previous = chars[index - 1]
        let current = chars[index]
        if separators.contains(previous) { return true }
        // camelCase の大文字
        if previous.isLowercase, current.isUppercase { return true }
        return false
    }
}

/// 日本語をローマ字にする（「新規フォルダ」→「shinkiforuda」）。
/// メニュー名をローマ字でも探せるようにするため（要件 C-02）。
nonisolated enum Romaji {
    static func transcribe(_ text: String) -> String {
        let string = text as CFString
        let tokenizer = CFStringTokenizerCreate(
            nil, string, CFRangeMake(0, CFStringGetLength(string)),
            kCFStringTokenizerUnitWord, Locale(identifier: "ja_JP") as CFLocale
        )
        var result = ""
        while !CFStringTokenizerAdvanceToNextToken(tokenizer).isEmpty {
            if let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String {
                result += latin
            } else {
                let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
                result += (text as NSString).substring(with: NSRange(location: range.location, length: range.length))
            }
        }
        let plain = result.applyingTransform(.stripDiacritics, reverse: false) ?? result
        return plain.lowercased().filter { !$0.isWhitespace }
    }
}
