import Foundation

/// One row in a board's article list.
struct ArticleSummary: Identifiable, Hashable {
    /// The floor index within the board (used to open the article), nil for pinned (★) posts.
    let index: Int?
    let mark: String        // e.g. "M" (marked), "R" (replied by author), or empty
    let pushMark: String    // e.g. "爆", "X2", "16", "" — raw push-count text as shown on screen
    let date: String        // "mm/dd"
    let author: String      // empty/"-" when the article was deleted
    let title: String
    let isDeleted: Bool

    var id: String { "\(index.map(String.init) ?? "pinned")-\(title)-\(author)-\(date)" }
}

enum PushKind: String, Codable {
    case push = "推"
    case boo = "噓"
    case arrow = "→"

    var commandDigit: String {
        switch self {
        case .push: return "1"
        case .boo: return "2"
        case .arrow: return "3"
        }
    }
}

struct PushComment: Identifiable, Hashable {
    let kind: PushKind
    let author: String
    let content: String
    let timestamp: String // e.g. "08/13 21:30"

    var id: String { "\(author)-\(timestamp)-\(content.prefix(8))" }
}

/// The full content of an article, including its header fields and push comments.
struct ArticleContent {
    let board: String
    let author: String       // full "id (name)" line as shown, e.g. "someone (Some One)"
    let title: String
    let postedAt: String
    let bodyLines: [String]
    let pushes: [PushComment]
    let ip: String?
}
