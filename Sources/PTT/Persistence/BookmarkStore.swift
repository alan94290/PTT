import Foundation

@MainActor
final class BookmarkStore: ObservableObject {
    @Published private(set) var bookmarks: [Bookmark] = []

    private let defaultsKey = "ptt.bookmarks"

    init() {
        load()
    }

    func isBookmarked(_ boardName: String) -> Bool {
        bookmarks.contains { $0.boardName.caseInsensitiveCompare(boardName) == .orderedSame }
    }

    func toggle(_ boardName: String) {
        if isBookmarked(boardName) {
            bookmarks.removeAll { $0.boardName.caseInsensitiveCompare(boardName) == .orderedSame }
        } else {
            bookmarks.append(Bookmark(boardName: boardName))
        }
        save()
    }

    func remove(at offsets: IndexSet) {
        bookmarks.remove(atOffsets: offsets)
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([Bookmark].self, from: data) else { return }
        bookmarks = decoded.sorted { $0.addedAt > $1.addedAt }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
