import XCTest
@testable import PTT

final class PTTScreenParserTests: XCTestCase {
    /// Builds a board-list row from the same fixed-width columns
    /// `PTTScreenParser.parseArticleList` expects, so the test can't drift
    /// out of sync with hand-counted spaces.
    private func boardRow(index: String, status: String = "  ", push: String = "  ", date: String, author: String, title: String) -> String {
        func pad(_ s: String, _ width: Int) -> String {
            s.count >= width ? String(s.prefix(width)) : s + String(repeating: " ", count: width - s.count)
        }
        return pad(index, 8) + pad(status, 2) + pad(push, 2) + pad(date, 5) + " " + pad(author, 13) + title
    }

    func testParsesOrdinaryArticleRow() {
        let line = boardRow(index: "8080", push: "15", date: "8/13", author: "someone", title: "Re: [問題] 測試標題")
        let rows = PTTScreenParser.parseArticleList(lines: [line])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].index, 8080)
        XCTAssertEqual(rows[0].author, "someone")
        XCTAssertTrue(rows[0].title.contains("測試標題"))
    }

    func testPinnedArticleHasNilIndex() {
        let line = boardRow(index: "★", date: "8/01", author: "sysop", title: "[公告] 板規")
        let rows = PTTScreenParser.parseArticleList(lines: [line])
        XCTAssertEqual(rows.count, 1)
        XCTAssertNil(rows[0].index)
    }

    func testBlankLineIsSkipped() {
        let rows = PTTScreenParser.parseArticleList(lines: ["", "                               "])
        XCTAssertTrue(rows.isEmpty)
    }

    func testParsesPushLine() {
        let push = PTTScreenParser.parsePush("推 someone:這篇文章寫得真好                  08/13 21:30")
        XCTAssertNotNil(push)
        XCTAssertEqual(push?.kind, .push)
        XCTAssertEqual(push?.author, "someone")
        XCTAssertEqual(push?.timestamp, "08/13 21:30")
        XCTAssertEqual(push?.content, "這篇文章寫得真好")
    }

    func testParsesBooLine() {
        let push = PTTScreenParser.parsePush("噓 someone:不同意                            08/13 21:31")
        XCTAssertEqual(push?.kind, .boo)
    }

    func testNonPushLineReturnsNil() {
        XCTAssertNil(PTTScreenParser.parsePush("這只是內文的一行文字，不是推文"))
    }

    func testParseArticleContentSeparatesHeaderBodyAndPushes() {
        let lines = [
            "作者  someone (Some One)  看板  Test",
            "標題  [問題] 測試標題",
            "時間  Wed Aug 13 21:00:00 2026",
            "這是內文第一行",
            "這是內文第二行",
            "推 alice:推一個                              08/13 21:10",
            "※ 發信站: 批踢踢實業坊(ptt.cc), 來自: 1.2.3.4",
        ]
        let content = PTTScreenParser.parseArticleContent(board: "Test", lines: lines)
        XCTAssertTrue(content.author.contains("someone"))
        XCTAssertTrue(content.title.contains("測試標題"))
        XCTAssertEqual(content.bodyLines, ["這是內文第一行", "這是內文第二行"])
        XCTAssertEqual(content.pushes.count, 1)
        XCTAssertEqual(content.ip, "1.2.3.4")
    }
}
