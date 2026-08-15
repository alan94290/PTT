import SwiftUI

/// The 8 standard ANSI colors PTT uses via SGR codes 30-37 / 40-47, plus the
/// terminal's default foreground/background.
enum TerminalColor: UInt8, Hashable {
    case black = 0
    case red = 1
    case green = 2
    case yellow = 3
    case blue = 4
    case magenta = 5
    case cyan = 6
    case white = 7
    case defaultColor = 8

    /// Approximate mapping to a readable color, tuned for a light/dark SwiftUI theme
    /// rather than a literal terminal palette (raw ANSI colors read poorly on mobile).
    func color(bold: Bool) -> Color {
        switch self {
        case .black: return bold ? Color(white: 0.45) : Color(white: 0.25)
        case .red: return bold ? .red : Color(red: 0.75, green: 0.15, blue: 0.15)
        case .green: return bold ? .green : Color(red: 0.1, green: 0.55, blue: 0.25)
        case .yellow: return bold ? .yellow : Color(red: 0.6, green: 0.5, blue: 0.05)
        case .blue: return bold ? Color(red: 0.35, green: 0.55, blue: 1.0) : Color(red: 0.15, green: 0.3, blue: 0.75)
        case .magenta: return bold ? .pink : Color(red: 0.65, green: 0.2, blue: 0.55)
        case .cyan: return bold ? .cyan : Color(red: 0.1, green: 0.5, blue: 0.55)
        case .white: return bold ? .primary : .secondary
        case .defaultColor: return .primary
        }
    }
}
