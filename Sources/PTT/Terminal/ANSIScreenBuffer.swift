import Foundation

/// A minimal VT100/ANSI terminal emulator sized to PTT's fixed 80x24 screen.
///
/// PTT (and every other Telnet BBS) doesn't expose a data API — the "protocol"
/// is a stream of bytes that a real terminal renders into a character grid.
/// To read board lists, articles, and push comments we have to do the same
/// rendering ourselves, then read the resulting grid as text. This type owns
/// that rendering; `PTTScreenParser` reads the result.
final class ANSIScreenBuffer {
    let rows: Int
    let cols: Int
    private(set) var grid: [[TerminalCell]]
    private(set) var cursorRow = 0
    private(set) var cursorCol = 0

    private enum ParseState {
        case normal
        case escape
        case csi
    }

    private var state: ParseState = .normal
    private var csiParams: String = ""

    /// PTT's telnet interface sends Big5 (specifically the Big5-UAO variant
    /// BBS clients use), not UTF-8 — confirmed by a live capture where ASCII
    /// fragments in the welcome banner decoded fine under a UTF-8 assumption
    /// but every Chinese character came out as mojibake. Big5 is a 1-or-2-byte
    /// encoding: bytes below 0x80 are plain ASCII, and a lead byte >= 0x80 is
    /// always immediately followed by exactly one trail byte.
    private var pendingLeadByte: UInt8?

    private static let big5Encoding: String.Encoding = {
        let cfEncoding = CFStringEncoding(CFStringEncodings.big5.rawValue)
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String.Encoding(rawValue: nsEncoding)
    }()

    private var fg: TerminalColor = .defaultColor
    private var bg: TerminalColor = .defaultColor
    private var bold = false
    private var reverse = false

    init(rows: Int = 24, cols: Int = 80) {
        self.rows = rows
        self.cols = cols
        self.grid = Array(repeating: Array(repeating: .blank, count: cols), count: rows)
    }

    func reset() {
        grid = Array(repeating: Array(repeating: .blank, count: cols), count: rows)
        cursorRow = 0
        cursorCol = 0
        fg = .defaultColor
        bg = .defaultColor
        bold = false
        reverse = false
        state = .normal
        csiParams = ""
        pendingLeadByte = nil
    }

    func feed(_ bytes: [UInt8]) {
        for byte in bytes {
            process(byte)
        }
    }

    // MARK: - Byte-level state machine

    private func process(_ byte: UInt8) {
        switch state {
        case .normal:
            processNormal(byte)
        case .escape:
            processEscape(byte)
        case .csi:
            processCSI(byte)
        }
    }

    private func processNormal(_ byte: UInt8) {
        if let lead = pendingLeadByte {
            pendingLeadByte = nil
            emitBig5Pair(lead, byte)
            return
        }

        if byte == 0x1B { // ESC
            state = .escape
            return
        }

        if byte >= 0x80 {
            pendingLeadByte = byte
            return
        }

        handleControlOrASCII(byte)
    }

    private func processEscape(_ byte: UInt8) {
        switch byte {
        case 0x5B: // '['
            state = .csi
            csiParams = ""
        case 0x4F: // 'O' (SS3) — PTT servers don't send these, but tolerate it.
            state = .normal
        default:
            state = .normal
        }
    }

    private func processCSI(_ byte: UInt8) {
        // Parameter bytes: digits and ';'. Collect until a final byte (letter) arrives.
        if (0x30...0x3B).contains(byte) {
            csiParams.append(Character(UnicodeScalar(byte)))
            return
        }
        let final = Character(UnicodeScalar(byte))
        handleCSI(final: final, params: csiParams)
        state = .normal
        csiParams = ""
    }

    // MARK: - Control characters & printable ASCII

    private func handleControlOrASCII(_ byte: UInt8) {
        switch byte {
        case 0x0D: // \r
            cursorCol = 0
        case 0x0A: // \n
            advanceRow()
        case 0x08: // \b
            cursorCol = max(0, cursorCol - 1)
        case 0x07: // BEL
            break
        case 0x09: // \t
            cursorCol = min(cols - 1, ((cursorCol / 8) + 1) * 8)
        case 0x20...0x7E:
            writeChar(Character(UnicodeScalar(byte)), width: 1)
        default:
            break
        }
    }

    private func emitBig5Pair(_ lead: UInt8, _ trail: UInt8) {
        guard let character = String(bytes: [lead, trail], encoding: Self.big5Encoding)?.first else {
            return // Not a valid Big5 pair — drop it rather than corrupt the grid.
        }
        writeChar(character, width: 2) // every decodable Big5 pair is a full-width glyph.
    }

    // MARK: - Grid writes

    private func writeChar(_ character: Character, width: Int) {
        if cursorCol + width > cols {
            cursorCol = 0
            advanceRow()
        }
        guard cursorRow >= 0, cursorRow < rows else { return }
        var cell = TerminalCell()
        cell.character = character
        cell.foreground = fg
        cell.background = bg
        cell.bold = bold
        cell.reverse = reverse
        grid[cursorRow][cursorCol] = cell
        if width == 2, cursorCol + 1 < cols {
            var shadow = TerminalCell()
            shadow.isWideContinuation = true
            grid[cursorRow][cursorCol + 1] = shadow
        }
        cursorCol += width
    }

    private func advanceRow() {
        cursorRow += 1
        if cursorRow >= rows {
            grid.removeFirst()
            grid.append(Array(repeating: .blank, count: cols))
            cursorRow = rows - 1
        }
    }

    // MARK: - CSI command handling

    private func handleCSI(final: Character, params: String) {
        let parts = params.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) }

        func p(_ index: Int, default def: Int) -> Int {
            guard index < parts.count, let v = parts[index], v > 0 else { return def }
            return v
        }

        switch final {
        case "H", "f":
            let row = p(0, default: 1) - 1
            let col = p(1, default: 1) - 1
            cursorRow = min(max(row, 0), rows - 1)
            cursorCol = min(max(col, 0), cols - 1)
        case "A":
            cursorRow = max(0, cursorRow - p(0, default: 1))
        case "B":
            cursorRow = min(rows - 1, cursorRow + p(0, default: 1))
        case "C":
            cursorCol = min(cols - 1, cursorCol + p(0, default: 1))
        case "D":
            cursorCol = max(0, cursorCol - p(0, default: 1))
        case "J":
            eraseDisplay(mode: parts.first.flatMap { $0 } ?? 0)
        case "K":
            eraseLine(mode: parts.first.flatMap { $0 } ?? 0)
        case "m":
            applySGR(parts.isEmpty ? [0] : parts.map { $0 ?? 0 })
        default:
            break // scrolling regions, save/restore cursor, etc. — unused by PTT's UI.
        }
    }

    private func eraseDisplay(mode: Int) {
        switch mode {
        case 2, 3:
            grid = Array(repeating: Array(repeating: .blank, count: cols), count: rows)
        case 1:
            for r in 0..<cursorRow { grid[r] = Array(repeating: .blank, count: cols) }
            for c in 0...cursorCol where c < cols { grid[cursorRow][c] = .blank }
        default: // 0: cursor to end of screen
            for c in cursorCol..<cols { grid[cursorRow][c] = .blank }
            for r in (cursorRow + 1)..<rows { grid[r] = Array(repeating: .blank, count: cols) }
        }
    }

    private func eraseLine(mode: Int) {
        switch mode {
        case 1:
            for c in 0...cursorCol where c < cols { grid[cursorRow][c] = .blank }
        case 2:
            grid[cursorRow] = Array(repeating: .blank, count: cols)
        default: // 0: cursor to end of line
            for c in cursorCol..<cols { grid[cursorRow][c] = .blank }
        }
    }

    private func applySGR(_ codes: [Int]) {
        var i = 0
        while i < codes.count {
            let code = codes[i]
            switch code {
            case 0:
                fg = .defaultColor; bg = .defaultColor; bold = false; reverse = false
            case 1:
                bold = true
            case 7:
                reverse = true
            case 22:
                bold = false
            case 27:
                reverse = false
            case 30...37:
                fg = TerminalColor(rawValue: UInt8(code - 30)) ?? .defaultColor
            case 39:
                fg = .defaultColor
            case 40...47:
                bg = TerminalColor(rawValue: UInt8(code - 40)) ?? .defaultColor
            case 49:
                bg = .defaultColor
            default:
                break
            }
            i += 1
        }
    }

    // MARK: - Reading the rendered screen as text

    /// Each row rendered as text, with wide-character shadow cells skipped and
    /// trailing whitespace trimmed. This is what all PTT screen parsing works from.
    func plainLines() -> [String] {
        grid.map { row -> String in
            var s = ""
            s.reserveCapacity(cols)
            for cell in row where !cell.isWideContinuation {
                s.append(cell.character)
            }
            while s.hasSuffix(" ") { s.removeLast() }
            return s
        }
    }

    func fullText() -> String {
        plainLines().joined(separator: "\n")
    }
}
