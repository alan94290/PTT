import Foundation

enum WebSocketTerminalError: Error, LocalizedError {
    case connectionFailed(String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason): return "無法連線: \(reason)"
        case .notConnected: return "尚未連線"
        }
    }
}

/// PTT retired plaintext Telnet. Rather than pull in an SSH stack, this talks
/// to PTT's own WebSocket bridge (`wsproxy`) at `wss://ws.ptt.cc/bbs` — the
/// same endpoint term.ptt.cc's web terminal uses — over the platform's native
/// `URLSessionWebSocketTask`, so there's no third-party dependency at all.
/// The bridge relays raw bytes to and from PTT's classic BBS backend, so
/// everything above this layer (login flow, key sequences, screen parsing)
/// is unchanged from how a Telnet connection would have worked.
actor WebSocketTerminalClient {
    private static let endpoint = URL(string: "wss://ws.ptt.cc/bbs")!
    /// The bridge rejects connections without this — PTT scopes access to
    /// requests that claim to come from its own web terminal.
    private static let originHeader = "https://term.ptt.cc"

    let incomingBytes: AsyncStream<[UInt8]>
    private let continuation: AsyncStream<[UInt8]>.Continuation

    private var urlSession: URLSession?
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var negotiator = TelnetNegotiator()

    init() {
        var cont: AsyncStream<[UInt8]>.Continuation!
        self.incomingBytes = AsyncStream { streamContinuation in
            cont = streamContinuation
        }
        self.continuation = cont
    }

    func connect() async throws {
        var request = URLRequest(url: Self.endpoint)
        request.setValue(Self.originHeader, forHTTPHeaderField: "Origin")

        let urlSession = URLSession(configuration: .default)
        let wsTask = urlSession.webSocketTask(with: request)
        self.urlSession = urlSession
        self.task = wsTask
        wsTask.resume()

        receiveTask = Task {
            while !Task.isCancelled {
                do {
                    let message = try await wsTask.receive()
                    switch message {
                    case .data(let data):
                        await self.handleIncoming(Array(data))
                    case .string(let text):
                        // The bridge is documented as binary-only; handled defensively.
                        await self.handleIncoming(Array(text.utf8))
                    @unknown default:
                        break
                    }
                } catch {
                    break
                }
            }
            await self.finish()
        }
    }

    func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        urlSession = nil
        continuation.finish()
    }

    func send(_ string: String) async throws {
        guard let task else { throw WebSocketTerminalError.notConnected }
        // PTT's BBS backend speaks Big5 (Big5-UAO), not UTF-8 — encode
        // outgoing text (IDs, passwords, push/post/reply content) to match,
        // or the server sees garbage for anything outside ASCII.
        let data = string.data(using: Self.big5Encoding, allowLossyConversion: true) ?? Data(string.utf8)
        do {
            try await task.send(.data(data))
        } catch {
            throw WebSocketTerminalError.connectionFailed(error.localizedDescription)
        }
    }

    private static let big5Encoding: String.Encoding = {
        let cfEncoding = CFStringEncoding(CFStringEncodings.big5.rawValue)
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String.Encoding(rawValue: nsEncoding)
    }()

    private func handleIncoming(_ bytes: [UInt8]) {
        // The wsproxy bridge is expected to already strip Telnet's IAC
        // option-negotiation bytes before relaying to WebSocket clients, but
        // stripping defensively here is cheap insurance if it ever doesn't:
        // a plain byte-for-byte passthrough makes this a no-op either way.
        let result = negotiator.process(bytes)
        if !result.reply.isEmpty {
            Task { try? await send(rawBytes: result.reply) }
        }
        if !result.payload.isEmpty {
            continuation.yield(result.payload)
        }
    }

    private func send(rawBytes: [UInt8]) async throws {
        guard let task else { throw WebSocketTerminalError.notConnected }
        try await task.send(.data(Data(rawBytes)))
    }

    private func finish() {
        continuation.finish()
    }
}

/// Strips Telnet IAC command sequences out of a byte stream and builds the
/// reply bytes needed to decline every negotiated option, using the standard
/// "refuse everything" strategy (WILL -> DONT, DO -> WONT).
struct TelnetNegotiator {
    private enum State {
        case data
        case iac
        case command(UInt8) // WILL/WONT/DO/DONT awaiting the option byte
        case subnegotiation
        case subnegotiationIAC
    }

    private static let IAC: UInt8 = 255
    private static let WILL: UInt8 = 251
    private static let WONT: UInt8 = 252
    private static let DO: UInt8 = 253
    private static let DONT: UInt8 = 254
    private static let SB: UInt8 = 250
    private static let SE: UInt8 = 240

    private var state: State = .data

    mutating func process(_ bytes: [UInt8]) -> (payload: [UInt8], reply: [UInt8]) {
        var payload: [UInt8] = []
        var reply: [UInt8] = []

        for byte in bytes {
            switch state {
            case .data:
                if byte == Self.IAC {
                    state = .iac
                } else {
                    payload.append(byte)
                }
            case .iac:
                switch byte {
                case Self.WILL, Self.WONT, Self.DO, Self.DONT:
                    state = .command(byte)
                case Self.SB:
                    state = .subnegotiation
                case Self.IAC:
                    // Escaped 0xFF byte in the data stream.
                    payload.append(Self.IAC)
                    state = .data
                default:
                    // IAC NOP / DM / GA / etc. — nothing to reply to.
                    state = .data
                }
            case .command(let cmd):
                let option = byte
                switch cmd {
                case Self.WILL:
                    reply.append(contentsOf: [Self.IAC, Self.DONT, option])
                case Self.DO:
                    reply.append(contentsOf: [Self.IAC, Self.WONT, option])
                default:
                    break // WONT/DONT need no reply.
                }
                state = .data
            case .subnegotiation:
                if byte == Self.IAC {
                    state = .subnegotiationIAC
                }
            case .subnegotiationIAC:
                if byte == Self.SE {
                    state = .data
                } else {
                    state = .subnegotiation
                }
            }
        }

        return (payload, reply)
    }
}
