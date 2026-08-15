import Foundation

@MainActor
final class ArticleListViewModel: ObservableObject {
    let boardName: String
    private let session = PTTSession.shared

    @Published var articles: [ArticleSummary] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasEnteredBoard = false

    init(boardName: String) {
        self.boardName = boardName
    }

    func loadIfNeeded() async {
        guard !hasEnteredBoard else { return }
        await enterAndLoad()
    }

    func enterAndLoad() async {
        isLoading = true
        errorMessage = nil
        do {
            try await session.enterBoard(boardName)
            hasEnteredBoard = true
            articles = try await session.fetchArticleList()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadOlder() async {
        await page(.olderPage)
    }

    func loadNewer() async {
        await page(.newerPage)
    }

    private func page(_ direction: ArticleListPageDirection) async {
        guard hasEnteredBoard, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            articles = try await session.fetchArticleList(page: direction)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func search(keyword: String) async {
        guard hasEnteredBoard, !keyword.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            articles = try await session.searchInBoard(keyword: keyword)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
