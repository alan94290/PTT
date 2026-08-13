import SwiftUI

struct ArticleDetailView: View {
    let boardName: String
    let index: Int

    @StateObject private var viewModel: ArticleDetailViewModel
    @State private var pushText = ""
    @State private var pushKind: PushKind = .push
    @State private var showReplySheet = false
    @FocusState private var pushFieldFocused: Bool

    init(boardName: String, index: Int) {
        self.boardName = boardName
        self.index = index
        _viewModel = StateObject(wrappedValue: ArticleDetailViewModel(boardName: boardName, index: index))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                if let content = viewModel.content {
                    VStack(alignment: .leading, spacing: 12) {
                        header(content)
                        Divider()
                        Text(content.bodyLines.joined(separator: "\n"))
                            .font(.system(.body, design: .default))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if !content.pushes.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(content.pushes) { push in
                                    PushRow(push: push)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }

            Divider()
            pushBar
        }
        .navigationTitle(viewModel.content?.title.isEmpty == false ? viewModel.content!.title : "文章")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("回覆") { showReplySheet = true }
            }
        }
        .overlay {
            if viewModel.isLoading && viewModel.content == nil {
                LoadingOverlay(message: "讀取文章中…")
            }
        }
        .alert("發生錯誤", isPresented: errorAlertBinding, presenting: viewModel.errorMessage) { _ in
            Button("確定") { viewModel.errorMessage = nil }
        } message: { message in
            Text(message)
        }
        .sheet(isPresented: $showReplySheet) {
            NavigationStack {
                ComposeView(mode: .reply(board: boardName, index: index))
            }
        }
        .task {
            await viewModel.load()
        }
    }

    private func header(_ content: ArticleContent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(content.title)
                .font(.headline)
            HStack {
                Text(content.author)
                Spacer()
                Text(content.postedAt)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var pushBar: some View {
        HStack(spacing: 8) {
            Picker("", selection: $pushKind) {
                Text("推").tag(PushKind.push)
                Text("噓").tag(PushKind.boo)
                Text("→").tag(PushKind.arrow)
            }
            .pickerStyle(.segmented)
            .frame(width: 140)

            TextField("推文內容", text: $pushText)
                .textFieldStyle(.roundedBorder)
                .focused($pushFieldFocused)
                .onSubmit(sendPush)

            Button {
                sendPush()
            } label: {
                if viewModel.isPushing {
                    ProgressView()
                } else {
                    Image(systemName: "paperplane.fill")
                }
            }
            .disabled(pushText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isPushing)
        }
        .padding(8)
    }

    private func sendPush() {
        let message = pushText
        pushText = ""
        pushFieldFocused = false
        Task { await viewModel.push(kind: pushKind, message: message) }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })
    }
}
