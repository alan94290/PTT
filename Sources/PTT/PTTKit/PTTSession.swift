import Foundation

enum ArticleListPageDirection {
    case olderPage // 'P' — toward article #1
    case newerPage // 'N' — toward the newest article
}

enum ReplyDestination {
    case board
    case mail
    case both

    var key: String {
        switch self {
        case .board: return "F"
        case .mail: return "M"
        case .both: return "B"
        }
    }
}

/// Drives a PTT Telnet session end-to-end: connect, log in, browse boards and
/// articles, push/reply/post. Every action here is built the same way a human
/// would use PTT — send keystrokes, read the redrawn screen, react — because
/// that's the only interface PTT has. See `PTTKey` and `PTTScreen` for the
/// exact keystrokes/markers this relies on.
///
/// IMPORTANT: this talks to real PTT accounts. Actions like push/post/reply
/// are irreversible on a live board. The keystroke sequences below are based
/// on publicly documented PTT behavior and the long-established PyPtt
/// automation library, but have not been exercised against a live server in
/// this environment (no outbound Telnet here) — verify carefully with a
/// low-stakes account before relying on them.
actor PTTSession {
    /// PTT's own UI has exactly one cursor/screen at a time, so the app is
    /// built around a single shared session rather than juggling multiple
    /// independent connections.
    static let shared = PTTSession()

    private let telnet = TelnetClient()
    private let screen = ANSIScreenBuffer()

    private var pendingChunks: [[UInt8]] = []
    private var streamEnded = false
    private var readerTask: Task<Void, Never>?

    private(set) var username: String?
    private(set) var isConnected = false
    private(set) var currentBoard: String?

    // MARK: - Connection lifecycle

    func connect(host: String = "ptt.cc", port: UInt16 = 23) async throws {
        try await telnet.connect(host: host, port: port)
        isConnected = true
        pendingChunks = []
        streamEnded = false
        screen.reset()

        readerTask = Task { [telnet] in
            let stream = telnet.incomingBytes
            for await chunk in stream {
                self.enqueue(chunk)
            }
            self.markStreamEnded()
        }

        // Absorb the initial banner burst before we start driving the login.
        try? await drain(quiet: 1.2, timeout: 6)
    }

    func disconnect() async {
        readerTask?.cancel()
        await telnet.disconnect()
        isConnected = false
        username = nil
        currentBoard = nil
    }

    // MARK: - Login

    func login(id: String, password: String, kickOtherSessions: Bool = true) async throws {
        try await sendAndDrain(id + PTTKey.enter, timeout: 6)
        try await sendAndDrain(password + PTTKey.enter, timeout: 6)
        if PTTScreen.wrongPassword.contains(where: { screen.fullText().contains($0) }) {
            throw PTTError.invalidCredentials
        }

        // From here PTT may show any mix of: press-any-key banners, a
        // duplicate-login prompt, or (rarely) an over-18 gate, before finally
        // landing on the main menu. Drive through all of them adaptively.
        try await interact(rules: [
            .fail(PTTScreen.wrongPassword, error: .invalidCredentials),
            .respond([PTTScreen.duplicateLoginPrompt], with: (kickOtherSessions ? "y" : "n") + PTTKey.enter),
            .respond(PTTScreen.pressAnyKey, with: PTTKey.space),
            .respond([PTTScreen.over18Prompt], with: "y" + PTTKey.enter),
            .stopWhen(PTTScreen.mainMenuMarkers),
        ], timeout: 15)

        username = id
    }

    func logout() async throws {
        try await sendAndDrain(PTTKey.goMainMenu(), timeout: 5)
        try await interact(send: "g" + PTTKey.enter, rules: [
            .respond(["確定要離開"], with: "y" + PTTKey.enter),
        ], timeout: 5)
        await disconnect()
    }

    // MARK: - Board navigation

    func enterBoard(_ name: String) async throws {
        try await sendAndDrain(PTTKey.goMainMenu(), timeout: 5)
        try await interact(send: PTTKey.quickSearchBoard(name), rules: [
            .fail(PTTScreen.boardNotFound, error: .boardNotFound(name)),
            .respond([PTTScreen.over18Prompt], with: "y" + PTTKey.enter),
            .stopWhen(PTTScreen.inBoardMarkers),
        ], timeout: 8)
        // Some boards autoplay a welcome banner on entry; skip it.
        try await sendAndDrain(String(repeating: PTTKey.ctrlC, count: 3), timeout: 3)
        currentBoard = name
    }

    /// Captures the article-list screen currently on display. Pass a
    /// direction to page through the list first.
    func fetchArticleList(page direction: ArticleListPageDirection? = nil) async throws -> [ArticleSummary] {
        if let direction {
            let key = (direction == .olderPage) ? PTTKey.pageUp : PTTKey.pageDown
            try await sendAndDrain(key, quiet: 0.3, timeout: 5)
        }
        return PTTScreenParser.parseArticleList(lines: screen.plainLines())
    }

    // MARK: - Reading an article

    /// Jumps to `index` in the current board's article list and reads its
    /// full content, paging through automatically and collecting all push
    /// comments along the way. Leaves the cursor back at the article list.
    func readArticle(index: Int) async throws -> ArticleContent {
        guard let board = currentBoard else { throw PTTError.unexpectedScreen("not in a board") }

        try await openArticle(index: index)

        var collected: [String] = []
        var lastPageText: String?
        var safety = 0

        while safety < 300 {
            safety += 1
            let currentLines = screen.plainLines()
            let currentText = currentLines.joined(separator: "\n")

            if currentText != lastPageText {
                for line in currentLines where line != collected.last {
                    collected.append(line)
                }
            }

            let statusLine = currentLines.last ?? ""
            let atEnd = statusLine.contains("100%") || statusLine.contains("(END)")
            if atEnd { break }

            lastPageText = currentText
            try await sendAndDrain(PTTKey.space, quiet: 0.25, timeout: 4)

            let newText = screen.plainLines().joined(separator: "\n")
            if newText == currentText {
                break // Space had no effect — we're already at the bottom.
            }
        }

        try await sendAndDrain("q", timeout: 4)

        return PTTScreenParser.parseArticleContent(board: board, lines: collected)
    }

    /// Moves the list cursor to `index` and opens it, leaving the cursor
    /// inside the article (does not return to the list).
    private func openArticle(index: Int) async throws {
        try await sendAndDrain("\(index)" + PTTKey.enter, timeout: 5)
        try await sendAndDrain(PTTKey.enter, timeout: 6)
        try await handleOver18IfPresent()
    }

    /// Some boards gate their content behind an 18+ confirmation the first
    /// time you enter them in a session. Answer it if (and only if) it's
    /// actually on screen right now.
    private func handleOver18IfPresent() async throws {
        if screen.fullText().contains(PTTScreen.over18Prompt) {
            try await sendAndDrain("y" + PTTKey.enter, timeout: 4)
        }
    }

    // MARK: - Pushing / commenting

    /// Opens `index`, pushes/boos/notes it with `message`, then returns to the list.
    func push(index: Int, kind: PushKind, message: String) async throws {
        try await openArticle(index: index)

        try await interact(send: PTTKey.comment, rules: [
            .fail(PTTScreen.pushForbidden, errorBuilder: { .pushNotAllowed($0) }),
            .fail([PTTScreen.pushRateLimited], error: .pushRateLimited),
            .stopWhen([PTTScreen.pushPermissionGranted]),
        ], timeout: 6)

        let sanitized = message.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        let payload = kind.commandDigit + sanitized + PTTKey.enter + "y" + PTTKey.enter
        try await sendAndDrain(payload, quiet: 0.6, timeout: 6)
        if screen.fullText().contains(PTTScreen.pushRateLimited) {
            throw PTTError.pushRateLimited
        }

        try await sendAndDrain("q", timeout: 4)
    }

    // MARK: - Posting a new article

    /// `classIndex` is the 1-based category number the board's post menu
    /// shows (e.g. 1 = 問題, 2 = 心得, …) — pass `nil` when the board doesn't ask.
    func post(title: String, content: String, classIndex: Int? = nil) async throws {
        try await sendAndDrain(PTTKey.ctrlP, quiet: 0.4, timeout: 6)

        if let classIndex {
            try await sendAndDrain("\(classIndex)" + PTTKey.enter, timeout: 5)
        }
        try await sendAndDrain(title + PTTKey.enter, timeout: 5)

        // Clear any auto-inserted template, then type the body.
        let clearTemplate = String(repeating: PTTKey.ctrlY, count: 40)
        try await sendAndDrain(clearTemplate + content, timeout: 8)
        try await sendAndDrain(PTTKey.ctrlX, timeout: 5)

        try await driveSubmitPrompts()
    }

    // MARK: - Replying to an article

    func reply(to index: Int, content: String, quoteOriginal: Bool = false, destination: ReplyDestination = .board) async throws {
        try await openArticle(index: index)

        try await sendAndDrain("r", timeout: 6)
        try await interact(send: destination.key + PTTKey.enter, rules: [
            .respond(["請問要引用原文嗎"], with: (quoteOriginal ? "y" : "n") + PTTKey.enter),
            .respond(["採用原標題"], with: "y" + PTTKey.enter),
        ], timeout: 4)
        try? await drain(quiet: 0.4, timeout: 3)

        try await sendAndDrain(content, timeout: 8)
        try await interact(send: PTTKey.ctrlX, rules: [
            .respond(["強制寫入", "(W)"], with: "w" + PTTKey.enter),
        ], timeout: 4)

        try await driveSubmitPrompts()
    }

    /// Handles the tail of the compose flow, which varies slightly by board:
    /// save confirmation, an optional anonymous-posting prompt, a send
    /// confirmation, and a signature-file choice.
    private func driveSubmitPrompts() async throws {
        try await interact(rules: [
            .respond([PTTScreen.saveConfirm, "確定"], with: "s" + PTTKey.enter),
            .respond([PTTScreen.anonymousBoardPrompt], with: "r" + PTTKey.enter),
            .respond([PTTScreen.sendConfirm], with: "y" + PTTKey.enter),
            .respond([PTTScreen.signatureSelect], with: "x" + PTTKey.enter),
            .stopWhen(PTTScreen.inBoardMarkers),
        ], timeout: 12)
    }

    // MARK: - Search

    /// Full-text search within the current board (PTT's `/` search).
    func searchInBoard(keyword: String) async throws -> [ArticleSummary] {
        try await sendAndDrain("/" + keyword + PTTKey.enter, quiet: 0.4, timeout: 6)
        return PTTScreenParser.parseArticleList(lines: screen.plainLines())
    }

    // MARK: - Low-level interaction engine

    private func interact(send input: String? = nil, rules: [PTTRule], timeout: TimeInterval) async throws {
        if let input {
            try await telnet.send(input)
        }
        var fired = Set<Int>()
        let deadline = Date().addingTimeInterval(timeout)

        while true {
            let text = screen.fullText()
            for (i, rule) in rules.enumerated() where !fired.contains(i) {
                guard rule.match(text) else { continue }
                switch rule.action(text) {
                case .respond(let payload):
                    fired.insert(i)
                    try await telnet.send(payload)
                case .stop:
                    return
                case .fail(let error):
                    throw error
                case .ignore:
                    fired.insert(i)
                }
            }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else {
                if rules.isEmpty { return } // plain "send and don't wait for anything" calls
                throw PTTError.timedOut(context: input ?? "interact")
            }
            guard let chunk = try await nextChunk(timeout: remaining) else {
                // Nothing arrived before the deadline (or the connection closed).
                if rules.isEmpty { return }
                throw PTTError.timedOut(context: input ?? "interact")
            }
            screen.feed(chunk)
        }
    }

    /// Sends `input`, then absorbs whatever the server sends back until it's
    /// been quiet for a moment. Used for steps that have no single crisp
    /// success marker to wait for (unlike `interact`, this never times out
    /// the whole call just because the server takes its time settling).
    private func sendAndDrain(_ input: String, quiet: TimeInterval = 0.6, timeout: TimeInterval) async throws {
        try await telnet.send(input)
        try? await drain(quiet: quiet, timeout: timeout)
    }

    /// Consumes incoming data until the connection has been quiet for
    /// `quiet` seconds (or `timeout` total elapses), without sending anything.
    /// Useful after an action whose completion has no crisp text marker.
    private func drain(quiet: TimeInterval, timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return }
            guard let chunk = try await nextChunk(timeout: min(remaining, quiet)) else { return }
            screen.feed(chunk)
        }
    }

    private func nextChunk(timeout: TimeInterval) async throws -> [UInt8]? {
        let deadline = Date().addingTimeInterval(timeout)
        while pendingChunks.isEmpty && !streamEnded {
            if Date() >= deadline { return nil }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        if !pendingChunks.isEmpty {
            return pendingChunks.removeFirst()
        }
        return nil
    }

    private func enqueue(_ chunk: [UInt8]) {
        pendingChunks.append(chunk)
    }

    private func markStreamEnded() {
        streamEnded = true
    }
}

// MARK: - Screen interaction rules

/// A single "if the screen shows X, do Y" step used by `PTTSession`'s
/// interaction loop. See the `respond`/`fail`/`stopWhen` builders below.
struct PTTRule {
    let match: (String) -> Bool
    let action: (String) -> PTTRuleAction
}

enum PTTRuleAction {
    case respond(String)
    case stop
    case fail(PTTError)
    case ignore
}

extension PTTRule {
    static func respond(_ markers: [String], with payload: String) -> PTTRule {
        PTTRule(
            match: { text in markers.contains { !$0.isEmpty && text.contains($0) } },
            action: { _ in .respond(payload) }
        )
    }

    static func fail(_ markers: [String], error: PTTError) -> PTTRule {
        PTTRule(
            match: { text in markers.contains { !$0.isEmpty && text.contains($0) } },
            action: { _ in .fail(error) }
        )
    }

    static func fail(_ markers: [String], errorBuilder: @escaping (String) -> PTTError) -> PTTRule {
        PTTRule(
            match: { text in markers.contains { !$0.isEmpty && text.contains($0) } },
            action: { text in .fail(errorBuilder(text)) }
        )
    }

    static func stopWhen(_ markers: [String]) -> PTTRule {
        PTTRule(
            match: { text in markers.contains { !$0.isEmpty && text.contains($0) } },
            action: { _ in .stop }
        )
    }
}
