import Foundation

enum ComposeMode: Equatable, Hashable {
    case newPost(board: String)
    case reply(board: String, index: Int)

    var boardName: String {
        switch self {
        case .newPost(let board): return board
        case .reply(let board, _): return board
        }
    }

    var needsTitle: Bool {
        if case .newPost = self { return true }
        return false
    }

    var navigationTitle: String {
        switch self {
        case .newPost: return "發表新文章"
        case .reply: return "回覆文章"
        }
    }
}

@MainActor
final class ComposeViewModel: ObservableObject {
    let mode: ComposeMode
    private let session = PTTSession.shared

    @Published var title = ""
    @Published var body = ""
    @Published var isSubmitting = false
    @Published var errorMessage: String?
    @Published var didSucceed = false

    init(mode: ComposeMode) {
        self.mode = mode
    }

    var canSubmit: Bool {
        let hasBody = !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard mode.needsTitle else { return hasBody }
        return hasBody && !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            switch mode {
            case .newPost:
                try await session.post(title: title, content: body)
            case .reply(_, let index):
                try await session.reply(to: index, content: body, quoteOriginal: false, destination: .board)
            }
            didSucceed = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}
