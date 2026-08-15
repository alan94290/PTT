import Foundation

/// Keystrokes PTT's BBS UI expects, as raw strings sent over the terminal
/// session (PTT's WebSocket bridge — PTT retired plaintext Telnet).
///
/// These match the key bindings used by the long-running, widely-used PyPtt
/// automation library (github.com/PyPtt/PyPtt), which is the closest thing
/// PTT has to a documented "protocol". Bindings that trigger a real posting
/// action (push, post, reply) are exactly the sequences PyPtt sends in
/// production, cross-checked against PTT community how-tos.
enum PTTKey {
    static let enter = "\r"
    static let space = " "
    static let tab = "\t"
    static let backspace = "\u{08}"

    static let ctrlC = "\u{03}"
    static let ctrlP = "\u{10}" // open the post-composer from a board's article list
    static let ctrlU = "\u{15}"
    static let ctrlX = "\u{18}" // save/submit from the line editor
    static let ctrlY = "\u{19}" // delete-line, also used to clear a template body
    static let ctrlZ = "\u{1A}"

    // Arrow keys as SS3 sequences (ESC O <letter>), which is what a real
    // terminal sends and what PTT's UI expects — not the CSI (ESC [ <letter>)
    // form used for *output* cursor movement.
    static let up = "\u{1B}OA"
    static let down = "\u{1B}OB"
    static let right = "\u{1B}OC"
    static let left = "\u{1B}OD"

    static let pageUp = "P"
    static let pageDown = "N"

    /// Opens the 推/噓/→ menu on the article currently being read.
    static let comment = "X"

    /// From a board's article list: reset out to the main menu, then jump straight
    /// into another board by name via PTT's quick-search ("qs") shortcut.
    static func goMainMenu() -> String { space + String(repeating: left, count: 5) }
    static func quickSearchBoard(_ name: String) -> String { "qs" + name + enter }
}
