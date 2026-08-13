import Foundation

/// A locally-saved board shortcut, kept on-device (separate from PTT's own
/// server-side "我的最愛" list, which requires being logged in to modify).
struct Bookmark: Identifiable, Hashable, Codable {
    var id: String { boardName }
    let boardName: String
    var addedAt: Date

    init(boardName: String, addedAt: Date = Date()) {
        self.boardName = boardName
        self.addedAt = addedAt
    }
}
