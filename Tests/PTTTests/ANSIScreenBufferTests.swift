import XCTest
@testable import PTT

final class ANSIScreenBufferTests: XCTestCase {
    func testPlainASCIIIsWrittenAtOrigin() {
        let buffer = ANSIScreenBuffer()
        buffer.feed(Array("Hello".utf8))
        XCTAssertEqual(buffer.plainLines().first, "Hello")
    }

    func testCarriageReturnLineFeedStartsNewLine() {
        let buffer = ANSIScreenBuffer()
        buffer.feed(Array("first\r\nsecond".utf8))
        let lines = buffer.plainLines()
        XCTAssertEqual(lines[0], "first")
        XCTAssertEqual(lines[1], "second")
    }

    func testCursorPositioningEscapeSequence() {
        let buffer = ANSIScreenBuffer()
        // Move to row 3, col 5 (1-based) and write "X".
        buffer.feed(Array("\u{1B}[3;5HX".utf8))
        let lines = buffer.plainLines()
        let row3 = Array(lines[2])
        XCTAssertEqual(row3[4], "X")
    }

    func testEraseDisplayClearsGrid() {
        let buffer = ANSIScreenBuffer()
        buffer.feed(Array("hello world".utf8))
        buffer.feed(Array("\u{1B}[2J".utf8))
        XCTAssertTrue(buffer.plainLines().allSatisfy { $0.isEmpty })
    }

    func testWideCharacterAdvancesCursorByTwoColumns() {
        let buffer = ANSIScreenBuffer()
        buffer.feed(Array("你A".utf8)) // CJK char (width 2) then ASCII
        let line = Array(buffer.plainLines()[0])
        XCTAssertEqual(line[0], "你")
        XCTAssertEqual(line[1], "A") // no phantom blank cell in the *rendered text*
    }

    func testMultiByteUTF8SplitAcrossFeedCallsDecodesCorrectly() {
        let buffer = ANSIScreenBuffer()
        let bytes = Array("測試".utf8)
        // Simulate a TCP chunk boundary landing mid-character.
        buffer.feed(Array(bytes[0..<2]))
        buffer.feed(Array(bytes[2...]))
        XCTAssertEqual(buffer.plainLines().first, "測試")
    }

    func testSGRColorDoesNotAppearInPlainText() {
        let buffer = ANSIScreenBuffer()
        buffer.feed(Array("\u{1B}[1;32m推 \u{1B}[m".utf8))
        XCTAssertEqual(buffer.plainLines().first, "推")
    }
}
