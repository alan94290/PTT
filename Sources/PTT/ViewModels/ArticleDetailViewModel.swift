import Foundation

@MainActor
final class ArticleDetailViewModel: ObservableObject {
    let boardName: String
    let index: Int
    private let session = PTTSession.shared

    @Published var content: ArticleContent?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isPushing = false
    @Published var pushMessage: String?

    init(boardName: String, index: Int) {
        self.boardName = boardName
        self.index = index
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            content = try await session.readArticle(index: index)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func push(kind: PushKind, message: String) async {
        guard !message.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isPushing = true
        pushMessage = nil
        do {
            try await session.push(index: index, kind: kind, message: message)
            pushMessage = "已送出"
            await load() // refresh to show the new push
        } catch {
            pushMessage = nil
            errorMessage = error.localizedDescription
        }
        isPushing = false
    }
}
