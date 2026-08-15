import SwiftUI

struct BoardHomeView: View {
    @EnvironmentObject private var sessionVM: SessionViewModel
    @EnvironmentObject private var bookmarkStore: BookmarkStore

    @State private var boardNameInput = ""
    @State private var path: [String] = []

    private let popularBoards = [
        "Gossiping", "C_Chat", "Baseball", "NBA", "Stock",
        "LifeIsPhoto", "movie", "iOS", "MobileComm", "joke",
    ]

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("前往看板") {
                    HStack {
                        TextField("輸入看板名稱，例如 Gossiping", text: $boardNameInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit(goToTypedBoard)
                        Button("前往", action: goToTypedBoard)
                            .disabled(boardNameInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                if !bookmarkStore.bookmarks.isEmpty {
                    Section("我的書籤") {
                        ForEach(bookmarkStore.bookmarks) { bookmark in
                            NavigationLink(value: bookmark.boardName) {
                                Label(bookmark.boardName, systemImage: "bookmark.fill")
                            }
                        }
                        .onDelete(perform: bookmarkStore.remove)
                    }
                }

                Section("熱門看板") {
                    ForEach(popularBoards, id: \.self) { board in
                        NavigationLink(value: board) {
                            Text(board)
                        }
                    }
                }
            }
            .navigationTitle("看板")
            .navigationDestination(for: String.self) { board in
                ArticleListView(boardName: board)
            }
        }
    }

    private func goToTypedBoard() {
        let trimmed = boardNameInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        boardNameInput = ""
        path.append(trimmed)
    }
}

#Preview {
    BoardHomeView()
        .environmentObject(SessionViewModel())
        .environmentObject(BookmarkStore())
}
