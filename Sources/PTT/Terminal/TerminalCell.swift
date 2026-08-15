import Foundation

struct TerminalCell: Hashable {
    var character: Character = " "
    var foreground: TerminalColor = .defaultColor
    var background: TerminalColor = .defaultColor
    var bold: Bool = false
    var reverse: Bool = false
    /// True for the "shadow" cell immediately after a double-width (CJK) character;
    /// it holds no visible glyph of its own.
    var isWideContinuation: Bool = false

    static let blank = TerminalCell()
}
