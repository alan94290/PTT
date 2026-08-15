import XCTest
@testable import PTT

final class ANSIScreenBufferTests: XCTestCase {
    /// PTT's telnet interface sends Big5, not UTF-8 — see the comment on
    /// `ANSIScreenBuffer.pendingLeadByte`. Tests that feed Chinese text need
    /// to encode it the same way the real server does.
    private static let big5Encoding: String.Encoding = {
        let cfEncoding = CFStringBuiltInEncodings.big5.rawValue
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String.Encoding(rawValue: nsEncoding)
    }()

    private func big5Bytes(_ string: String) -> [UInt8] {
        Array(string.data(using: Self.big5Encoding)!)
    }

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
        buffer.feed(big5Bytes("你") + Array("A".utf8)) // CJK char (width 2) then ASCII
        let line = Array(buffer.plainLines()[0])
        XCTAssertEqual(line[0], "你")
        XCTAssertEqual(line[1], "A") // no phantom blank cell in the *rendered text*
    }

    func testBig5PairSplitAcrossFeedCallsDecodesCorrectly() {
        let buffer = ANSIScreenBuffer()
        let bytes = big5Bytes("測試")
        // Simulate a TCP chunk boundary landing mid-character (between the
        // lead and trail byte of "測").
        buffer.feed(Array(bytes[0..<1]))
        buffer.feed(Array(bytes[1...]))
        XCTAssertEqual(buffer.plainLines().first, "測試")
    }

    func testSGRColorDoesNotAppearInPlainText() {
        let buffer = ANSIScreenBuffer()
        buffer.feed(Array("\u{1B}[1;32m".utf8) + big5Bytes("推") + Array(" \u{1B}[m".utf8))
        XCTAssertEqual(buffer.plainLines().first, "推")
    }
}
