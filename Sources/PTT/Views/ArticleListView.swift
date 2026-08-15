import SwiftUI

struct ArticleListView: View {
    let boardName: String

    @EnvironmentObject private var bookmarkStore: BookmarkStore
    @StateObject private var viewModel: ArticleListViewModel

    @State private var searchText = ""
    @State private var showComposeSheet = false

    init(boardName: String) {
        self.boardName = boardName
        _viewModel = StateObject(wrappedValue: ArticleListViewModel(boardName: boardName))
    }

    var body: some View {
        List {
            ForEach(viewModel.articles) { article in
                if let index = article.index {
                    NavigationLink(value: ArticleRoute(boardName: boardName, index: index, title: article.title)) {
                        ArticleRow(article: article)
                    }
                } else {
                    ArticleRow(article: article)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(boardName)
        .searchable(text: $searchText, prompt: "站內搜尋文章標題")
        .onSubmit(of: .search) {
            Task { await viewModel.search(keyword: searchText) }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    bookmarkStore.toggle(boardName)
                } label: {
                    Image(systemName: bookmarkStore.isBookmarked(boardName) ? "bookmark.fill" : "bookmark")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showComposeSheet = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    Task { await viewModel.loadOlder() }
                } label: {
                    Label("上頁（較舊）", systemImage: "chevron.up")
                }
                Spacer()
                Button {
                    Task { await viewModel.loadNewer() }
                } label: {
                    Label("下頁（較新）", systemImage: "chevron.down")
                }
            }
        }
        .overlay {
            if viewModel.isLoading && viewModel.articles.isEmpty {
                LoadingOverlay(message: "讀取看板中…")
            }
        }
        .alert("發生錯誤", isPresented: errorAlertBinding, presenting: viewModel.errorMessage) { _ in
            Button("確定") { viewModel.errorMessage = nil }
        } message: { message in
            Text(message)
        }
        .sheet(isPresented: $showComposeSheet) {
            NavigationStack {
                ComposeView(mode: .newPost(board: boardName))
            }
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .navigationDestination(for: ArticleRoute.self) { route in
            ArticleDetailView(boardName: route.boardName, index: route.index)
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })
    }
}

struct ArticleRoute: Hashable {
    let boardName: String
    let index: Int
    let title: String
}
