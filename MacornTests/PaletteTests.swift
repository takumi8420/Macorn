import Foundation
import Testing
@testable import Macorn

struct FuzzyMatcherTests {
    @Test func matchesInitials() throws {
        let match = try #require(FuzzyMatcher.match("nwf", in: "New Folder"))
        #expect(match.positions.count == 3)
    }

    @Test func rejectsWhenLettersAreMissing() {
        #expect(FuzzyMatcher.match("xyz", in: "New Folder") == nil)
        #expect(FuzzyMatcher.match("fn", in: "New Folder") == nil)
    }

    @Test func prefersConsecutiveAndWordStarts() throws {
        let tight = try #require(FuzzyMatcher.match("fold", in: "Folder"))
        let loose = try #require(FuzzyMatcher.match("fold", in: "f_o_l_d"))
        #expect(tight.score > loose.score)
        let prefix = try #require(FuzzyMatcher.match("doc", in: "docs"))
        let middle = try #require(FuzzyMatcher.match("doc", in: "mydocs"))
        #expect(prefix.score > middle.score)
    }

    @Test func matchesJapanese() {
        #expect(FuzzyMatcher.match("フォルダ", in: "新規フォルダ") != nil)
        #expect(FuzzyMatcher.match("新規", in: "新規ファイル") != nil)
    }

    @Test func ignoresCaseAndSpaces() {
        #expect(FuzzyMatcher.match("NEW f", in: "new folder") != nil)
    }

    @Test func emptyQueryMatchesEverything() {
        #expect(FuzzyMatcher.match("", in: "anything")?.score == 0)
    }
}

struct RomajiTests {
    @Test func transcribesKanjiAndKatakana() {
        let romaji = Romaji.transcribe("新規フォルダ")
        #expect(romaji.contains("shinki"))
        #expect(romaji.contains("foruda"))
    }

    @Test func menuNamesBecomeSearchable() {
        #expect(FuzzyMatcher.match("gomi", in: Romaji.transcribe("ゴミ箱に入れる")) != nil)
        #expect(FuzzyMatcher.match("kopi", in: Romaji.transcribe("コピー")) != nil)
    }
}

struct PaletteModeTests {
    @Test func detectsPrefixes() {
        #expect(PaletteMode.detect(">rename") == .commands)
        #expect(PaletteMode.detect("~/repo") == .path)
        #expect(PaletteMode.detect("/usr") == .path)
        #expect(PaletteMode.detect("@readme") == .files)
        #expect(PaletteMode.detect("#work") == .sidebar)
        #expect(PaletteMode.detect("macorn") == .all)
    }

    @Test func stripsPrefixFromTerm() {
        #expect(PaletteMode.term("> new") == "new")
        #expect(PaletteMode.term("@readme") == "readme")
        #expect(PaletteMode.term("~/repo") == "~/repo")
    }
}

final class FolderHistoryTests {
    private let url = FileManager.default.temporaryDirectory.appendingPathComponent("macorn-history-\(UUID().uuidString).sqlite")

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    @Test func recordsVisitsAndRanks() {
        let history = FolderHistory(url: url)
        history.visit(URL(fileURLWithPath: "/a"))
        history.visit(URL(fileURLWithPath: "/b"))
        history.visit(URL(fileURLWithPath: "/b"))
        let entries = history.entries()
        #expect(entries.first?.path == "/b")
        #expect(entries.first?.rank == 2)
        #expect(entries.count == 2)
    }

    @Test func persistsAcrossInstances() {
        FolderHistory(url: url).visit(URL(fileURLWithPath: "/kept"))
        #expect(FolderHistory(url: url).entries().map(\.path) == ["/kept"])
    }

    @Test func recentVisitsWeighMore() {
        let now = Date()
        let recent = FolderHistory.Entry(path: "/r", rank: 1, lastAccess: now)
        let old = FolderHistory.Entry(path: "/o", rank: 4, lastAccess: now.addingTimeInterval(-30 * 86_400))
        #expect(recent.frecency(now: now) > old.frecency(now: now))
    }

    @Test func removesFolders() {
        let history = FolderHistory(url: url)
        history.visit(URL(fileURLWithPath: "/does-not-exist-\(UUID().uuidString)"))
        history.visit(URL(fileURLWithPath: NSTemporaryDirectory()))
        history.removeMissing()
        #expect(history.entries().count == 1)
        history.removeAll()
        #expect(history.entries().isEmpty)
    }

    @Test func agesWhenTotalRankGrows() {
        let history = FolderHistory(url: url)
        for _ in 0..<5 { history.visit(URL(fileURLWithPath: "/rare")) }
        for _ in 0..<Int(FolderHistory.maxTotalRank) { history.visit(URL(fileURLWithPath: "/busy")) }
        let total = history.entries().reduce(0) { $0 + $1.rank }
        #expect(total <= FolderHistory.maxTotalRank)
    }
}
