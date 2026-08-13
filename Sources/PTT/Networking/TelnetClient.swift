import Foundation
import Network

enum TelnetError: Error, LocalizedError {
    case connectionFailed(String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason): return "無法連線: \(reason)"
        case .notConnected: return "尚未連線"
        }
    }
}

/// A raw TCP client that speaks just enough Telnet (RFC 854) to talk to a BBS:
/// it strips IAC option-negotiation sequences from the incoming stream and
/// politely refuses every option the server offers, since PTT's UI is carried
/// entirely as plain bytes + ANSI escapes and doesn't need any negotiated
/// Telnet option to function.
actor TelnetClient {
    private var connection: NWConnection?
    let incomingBytes: AsyncStream<[UInt8]>
    private let continuation: AsyncStream<[UInt8]>.Continuation

    init() {
        var cont: AsyncStream<[UInt8]>.Continuation!
        self.incomingBytes = AsyncStream { streamContinuation in
            cont = streamContinuation
        }
        self.continuation = cont
    }

    func connect(host: String, port: UInt16) async throws {
        let params = NWParameters.tcp
        let conn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: params)
        self.connection = conn

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var didResume = false
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if !didResume { didResume = true; cont.resume() }
                case .failed(let error):
                    if !didResume { didResume = true; cont.resume(throwing: TelnetError.connectionFailed(error.localizedDescription)) }
                case .cancelled:
                    if !didResume { didResume = true; cont.resume(throwing: TelnetError.connectionFailed("cancelled")) }
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
        }

        receiveLoop()
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        continuation.finish()
    }

    func send(_ string: String) async throws {
        guard let connection else { throw TelnetError.notConnected }
        let data = Data(string.utf8)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: TelnetError.connectionFailed(error.localizedDescription))
                } else {
                    cont.resume()
                }
            })
        }
    }

    private func receiveLoop() {
        guard let connection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task {
                if let data, !data.isEmpty {
                    await self.handleIncoming(Array(data))
                }
                if let error {
                    await self.finishStream(error: error)
                    return
                }
                if isComplete {
                    await self.finishStream(error: nil)
                    return
                }
                await self.receiveLoop()
            }
        }
    }

    private func finishStream(error: Error?) {
        continuation.finish()
    }

    // MARK: - Telnet IAC negotiation

    private var negotiator = TelnetNegotiator()

    private func handleIncoming(_ bytes: [UInt8]) async {
        let result = negotiator.process(bytes)
        if !result.reply.isEmpty {
            try? await send(rawBytes: result.reply)
        }
        if !result.payload.isEmpty {
            continuation.yield(result.payload)
        }
    }

    private func send(rawBytes: [UInt8]) async throws {
        guard let connection else { throw TelnetError.notConnected }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: Data(rawBytes), completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: TelnetError.connectionFailed(error.localizedDescription))
                } else {
                    cont.resume()
                }
            })
        }
    }
}

/// Strips Telnet IAC command sequences out of a byte stream and builds the
/// reply bytes needed to decline every negotiated option, using the standard
/// "refuse everything" strategy (WILL -> DONT, DO -> WONT). PTT's BBS UI does
/// not require any option to actually be enabled, so this keeps the protocol
/// handshake from ever stalling the connection.
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
