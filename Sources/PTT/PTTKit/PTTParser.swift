import Foundation

/// Turns rendered PTT screens (plain text lines from `ANSIScreenBuffer`) into
/// the app's models. PTT's "API" is whatever a human eye can read off the
/// screen, so this is deliberately tolerant: rows it can't confidently parse
/// are skipped rather than thrown as errors.
enum PTTScreenParser {

    /// Parses one board article-list screen (24 rows) into its article rows.
    /// Column layout follows PTT's fixed-width board list rendering:
    /// index[0..<8]  status[8..<10]  push[10..<12]  date[12..<17]  ' '[17]  author[18..<31]  title[31...]
    static func parseArticleList(lines: [String]) -> [ArticleSummary] {
        var results: [ArticleSummary] = []
        for raw in lines {
            // Pad so column slicing never runs out of bounds on short/blank lines.
            let line = raw.count >= 31 ? raw : raw + String(repeating: " ", count: 31 - raw.count)
            let chars = Array(line)
            guard chars.count > 31 else { continue }

            func slice(_ range: Range<Int>) -> String {
                let end = min(range.upperBound, chars.count)
                guard range.lowerBound < end else { return "" }
                return String(chars[range.lowerBound..<end]).trimmingCharacters(in: .whitespaces)
            }

            let indexText = slice(0..<8)
            let status = slice(8..<10)
            let pushMark = slice(10..<12)
            let date = slice(12..<17)
            let author = slice(18..<31)
            let title = chars.count > 31 ? String(chars[31...]).trimmingCharacters(in: .whitespaces) : ""

            guard !title.isEmpty else { continue }
            guard !date.isEmpty else { continue } // blank separator / decorative lines

            let index = Int(indexText) // nil for pinned "★" rows — still readable, just not by index.
            let isDeleted = title.contains("本文已被刪除") || author == "-"

            results.append(ArticleSummary(
                index: index,
                mark: status,
                pushMark: pushMark,
                date: date,
                author: author,
                title: title,
                isDeleted: isDeleted
            ))
        }
        return results
    }

    private static let pushLineRegex = try! NSRegularExpression(
        pattern: #"^(推|噓|→)\s*([\w.\-]{1,20})\s*:(.*?)\s+(\d{2}/\d{2}(?:\s+\d{2}:\d{2})?)\s*$"#
    )

    static func parsePush(_ line: String) -> PushComment? {
        let ns = line as NSString
        guard let match = pushLineRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        guard match.numberOfRanges == 5 else { return nil }
        let markText = ns.substring(with: match.range(at: 1))
        guard let kind = PushKind(rawValue: markText) else { return nil }
        let author = ns.substring(with: match.range(at: 2))
        let content = ns.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
        let timestamp = ns.substring(with: match.range(at: 4))
        return PushComment(kind: kind, author: author, content: content, timestamp: timestamp)
    }

    /// Splits a fully-captured article screen (header + body + pushes concatenated
    /// across every page) into structured fields.
    static func parseArticleContent(board: String, lines: [String]) -> ArticleContent {
        var author = ""
        var title = ""
        var postedAt = ""
        var ip: String?
        var bodyLines: [String] = []
        var pushes: [PushComment] = []

        for line in lines {
            if line.hasPrefix("作者") {
                author = line.replacingOccurrences(of: "作者", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: ": \u{3000}"))
                continue
            }
            if line.hasPrefix("標題") {
                title = line.replacingOccurrences(of: "標題", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: ": \u{3000}"))
                continue
            }
            if line.hasPrefix("時間") {
                postedAt = line.replacingOccurrences(of: "時間", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: ": \u{3000}"))
                continue
            }
            if line.contains("發信站:") || line.hasPrefix("※ 發信站") {
                if let range = line.range(of: #"[\d]{1,3}\.[\d]{1,3}\.[\d]{1,3}\.[\d]{1,3}"#, options: .regularExpression) {
                    ip = String(line[range])
                }
                continue
            }
            if let push = parsePush(line) {
                pushes.append(push)
                continue
            }
            bodyLines.append(line)
        }

        return ArticleContent(
            board: board,
            author: author,
            title: title,
            postedAt: postedAt,
            bodyLines: bodyLines,
            pushes: pushes,
            ip: ip
        )
    }
}
