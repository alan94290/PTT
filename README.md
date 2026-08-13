# PTT — a native iOS client for 批踢踢實業坊

A SwiftUI iOS app that connects directly to PTT (`ptt.cc`) over Telnet — the
same way a terminal client would — and renders it as a normal mobile app:
browse boards, read articles, push/噓/回文, search, and post.

PTT has no HTTP/REST API. Its only interface is a Telnet BBS meant for a
VT100 terminal, so "talking to PTT" means driving that terminal the way a
person would: send keystrokes, read the redrawn screen, react. That's what
this app's networking layer does.

## Architecture

```
Networking/   TelnetClient      raw TCP to ptt.cc:23 + Telnet IAC option negotiation
Terminal/     ANSIScreenBuffer  an 80x24 VT100/ANSI terminal emulator (cursor moves,
                                 SGR colors, CJK double-width chars, UTF-8 decode)
PTTKit/       PTTSession        actor that drives the terminal: login, board nav,
                                 article reading/paging, push, post, reply, search
              PTTKey / PTTScreen  the keystrokes PTT expects and the text markers
                                 used to recognize which screen is on display
              PTTScreenParser   turns rendered screen text into models
Models/       Board list rows, article content, push comments, bookmarks
Persistence/  Keychain-backed password storage, local board bookmarks
ViewModels/   @MainActor wrappers around PTTSession for each screen
Views/        SwiftUI screens (login, board list, article list, article detail,
              compose/reply, settings)
```

`PTTSession` is a single shared actor (`PTTSession.shared`) because PTT's own
UI has exactly one cursor and one screen at a time — the app mirrors that
instead of pretending multiple independent connections make sense.

## Requirements

- macOS with Xcode 15+ (this was developed and written in an environment
  **without** Xcode/Swift or outbound Telnet access — see "Status" below)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the `.xcodeproj`
  from `project.yml` (`brew install xcodegen`)

## Build & run

```sh
xcodegen generate
open PTT.xcodeproj
```

Then build & run the `PTT` scheme on a simulator or device (iOS 16+).

## Run the tests

```sh
xcodegen generate
xcodebuild test -project PTT.xcodeproj -scheme PTT -destination 'platform=iOS Simulator,name=iPhone 15'
```

Tests cover the parts that are pure logic and don't need a live connection:
the ANSI/VT100 terminal emulator, the Telnet IAC option-negotiation state
machine, and the board-list/article/push text parsers.

## Status & important caveats

This was built in a sandboxed Linux environment with **no Swift toolchain and
no outbound Telnet access**, so none of it has been compiled or exercised
against a real PTT server yet. Before relying on this, especially for
account-affecting actions:

1. **Build it in Xcode first** and fix anything the compiler flags — the code
   was written carefully but has not been through `swiftc`.
2. **Verify login/browsing on a real account** before trusting push/post/reply.
   The keystroke sequences for those (`PTTKey`, and the flows in
   `PTTSession.swift`) are based on publicly documented PTT usage and
   cross-checked against the source of the long-running
   [PyPtt](https://github.com/PyPtt/PyPtt) automation library, but PTT's UI
   has no formal spec — edge cases (board-specific prompts, rate limits,
   unusual terminal states) can differ from what's coded here.
3. **Test with a low-stakes/test account** before pushing or posting from a
   real one, since those actions are irreversible on a live board.
4. Article pagination concatenates each screen's text as you page through an
   article; PTT doesn't guarantee page boundaries won't occasionally overlap
   or skip a line depending on content length — this is a best-effort
   reconstruction, not a guaranteed-exact transcript.
5. `com.example.ptt` in `project.yml` is a placeholder bundle ID — change it
   before shipping anywhere.

## Features implemented

- Telnet connection + login (including duplicate-session and 18+ prompts)
- Browse a board's article list, page through older/newer articles
- Read a full article (auto-paginated) with its push comments
- 推 / 噓 / → on any article
- Reply to an article (to-board)
- Post a new article
- In-board keyword search
- Local board bookmarks (Keychain-backed saved login, on-device bookmark list)

## Not yet implemented

- Browsing PTT's board category directory (boards are opened by typing their
  exact name, or via the bundled "popular boards" shortcut list)
- Mail (站內信), 水球, 大水桶/系統事務等進階功能
- Rich rendering of PTT's ANSI colors in article bodies (currently plain text —
  the terminal emulator tracks color per cell, but the reading view doesn't
  paint it yet)
