import Foundation
import Testing
@testable import Macorn

struct TerminalEmulatorTests {
    @Test func printsTextAndMovesWithCRLF() {
        let terminal = TerminalEmulator(columns: 10, rows: 3)
        terminal.feed("ab\r\ncd")
        #expect(terminal.screenText == ["ab", "cd", ""])
        #expect(terminal.cursorX == 2 && terminal.cursorY == 1)
    }

    @Test func wrapsAtRightEdgeAndScrolls() {
        let terminal = TerminalEmulator(columns: 4, rows: 2)
        terminal.feed("abcdefgh\r\nij")
        #expect(terminal.screenText == ["efgh", "ij"])
        #expect(terminal.scrollback.map(TerminalEmulator.text(of:)) == ["abcd"])
    }

    @Test func handlesCursorMovesAndErase() {
        let terminal = TerminalEmulator(columns: 10, rows: 3)
        terminal.feed("hello\r\nworld")
        terminal.feed("\u{1B}[1;3H")  // 1行目の3桁目へ
        terminal.feed("X")
        terminal.feed("\u{1B}[2;1H\u{1B}[K")
        #expect(terminal.screenText == ["heXlo", "", ""])
        terminal.feed("\u{1B}[2J")
        #expect(terminal.screenText == ["", "", ""])
    }

    @Test func readsColors() {
        let terminal = TerminalEmulator(columns: 10, rows: 1)
        terminal.feed("\u{1B}[1;31mR\u{1B}[38;5;200mP\u{1B}[38;2;1;2;3mT\u{1B}[0mN")
        let cells = terminal.lines[0]
        #expect(cells[0].attributes.foreground == .indexed(1))
        #expect(cells[0].attributes.bold)
        #expect(cells[1].attributes.foreground == .indexed(200))
        #expect(cells[2].attributes.foreground == .rgb(1, 2, 3))
        #expect(cells[3].attributes == TerminalAttributes())
    }

    @Test func placesWideCharactersInTwoCells() {
        let terminal = TerminalEmulator(columns: 5, rows: 2)
        terminal.feed("あいう")
        // 3文字目は右端に入らないので次の行へ
        #expect(terminal.screenText == ["あい", "う"])
        #expect(terminal.lines[0][0].width == 2 && terminal.lines[0][1].width == 0)
        #expect(terminal.cursorX == 2 && terminal.cursorY == 1)
        // 全角の右半分に上書きしたら、左半分は消える
        terminal.feed("\u{1B}[1;2Hx")
        #expect(terminal.screenText[0] == " xい")
    }

    @Test func joinsCombiningCharacters() {
        let terminal = TerminalEmulator(columns: 5, rows: 1)
        terminal.feed("か\u{3099}")  // か + 濁点
        #expect(terminal.lines[0][0].character == "が")
        #expect(terminal.cursorX == 2)
    }

    @Test func decodesUTF8SplitAcrossChunks() {
        let terminal = TerminalEmulator(columns: 5, rows: 1)
        let bytes = Array("日".utf8)
        terminal.feed(Data(bytes.prefix(1)))
        terminal.feed(Data(bytes.dropFirst()))
        #expect(terminal.screenText == ["日"])
    }

    @Test func switchesToAlternateScreenAndBack() {
        let terminal = TerminalEmulator(columns: 6, rows: 2)
        terminal.feed("shell")
        terminal.feed("\u{1B}[?1049h")
        #expect(terminal.isAlternateScreen)
        #expect(terminal.screenText == ["", ""])
        terminal.feed("vim")
        terminal.feed("\u{1B}[?1049l")
        #expect(!terminal.isAlternateScreen)
        #expect(terminal.screenText == ["shell", ""])
        #expect(terminal.cursorX == 5)
    }

    @Test func scrollRegionKeepsOtherLines() {
        let terminal = TerminalEmulator(columns: 4, rows: 4)
        terminal.feed("a\r\nb\r\nc\r\nd")
        terminal.feed("\u{1B}[2;3r")      // 2〜3行目だけをスクロールさせる
        terminal.feed("\u{1B}[3;1H\n")
        #expect(terminal.screenText == ["a", "c", "", "d"])
        #expect(terminal.scrollback.isEmpty)
    }

    @Test func insertsAndDeletesCharacters() {
        let terminal = TerminalEmulator(columns: 6, rows: 1)
        terminal.feed("abcdef\u{1B}[1;2H\u{1B}[2P")
        #expect(terminal.screenText == ["adef"])
        terminal.feed("\u{1B}[1@")
        #expect(terminal.screenText == ["a def"])
    }

    @Test func answersCursorPositionQuery() {
        let terminal = TerminalEmulator(columns: 10, rows: 5)
        var answers: [String] = []
        terminal.respond = { answers.append($0) }
        terminal.feed("\u{1B}[3;4H\u{1B}[6n")
        #expect(answers == ["\u{1B}[3;4R"])
    }

    @Test func readsTitleAndDirectory() {
        let terminal = TerminalEmulator(columns: 10, rows: 1)
        terminal.feed("\u{1B}]0;作業\u{07}\u{1B}]7;file://host/Users/me/a%20b\u{1B}\\")
        #expect(terminal.title == "作業")
        #expect(terminal.reportedDirectory == "/Users/me/a b")
        #expect(terminal.screenText == [""])
    }

    @Test func resizesKeepingCursorVisible() {
        let terminal = TerminalEmulator(columns: 6, rows: 4)
        terminal.feed("1\r\n2\r\n3\r\n4")
        terminal.resize(columns: 3, rows: 2)
        #expect(terminal.screenText == ["3", "4"])
        #expect(terminal.cursorY == 1)
        #expect(terminal.scrollback.map(TerminalEmulator.text(of:)) == ["1", "2"])
    }

    @Test func measuresWidths() {
        #expect(TerminalEmulator.width(of: "a") == 1)
        #expect(TerminalEmulator.width(of: "あ") == 2)
        #expect(TerminalEmulator.width(of: "漢") == 2)
        #expect(TerminalEmulator.width(of: "Ａ") == 2)
        #expect(TerminalEmulator.width(of: "ｱ") == 1)
        #expect(TerminalEmulator.width(of: "\u{3099}") == 0)
        #expect(TerminalEmulator.width(of: "😀") == 2)
    }
}
