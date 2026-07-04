# ClipShot

A macOS menu bar app combining a clipboard history manager and screen capture.

## Features

- **Clipboard history** — remembers the last 150 text snippets and 50 images
  copied anywhere on your Mac. Click any item to copy it back. Pin items to
  keep them forever (pinned items survive Clear History and are never evicted).
- **Fuzzy search** — the search field is focused when the panel opens; just
  type to filter (subsequence match, e.g. `hw` finds "hello world").
- **Keyboard navigation** — `↑`/`↓` select, `Return` copies the selection,
  `⌘1`–`⌘9` copy the first nine items, `⌘⌫` deletes and `⌘P` pins the
  selection. Everything is always copied as plain text — no formatting.
- **Screen capture** — region, window, or full screen via the native macOS
  capture UI. Screenshots land on the Desktop as PNG and on the clipboard
  (so they also appear in history).
- **Captures tab** — a thumbnail grid of past screenshots with copy,
  show-in-Finder, move-to-Trash, and float actions.
- **Float on top** — pin any screenshot or history image as an always-on-top
  window for reference while you work.
- **Launch at login** — toggle in the gear menu (System Settings shows it
  under Login Items).
- **Global hotkeys** — no Accessibility permission required:
  - `⌃⌥⌘C` — open/close the history panel
  - `⌃⌥⌘4` — capture region
  - `⌃⌥⌘5` — capture window

History persists across restarts in `~/Library/Application Support/ClipShot/`.
Content marked concealed/transient/auto-generated (e.g. password managers) is
never recorded; gear menu → "Edit Ignore Rules…" opens `ignore-rules.json`
where you can add more pasteboard types or app bundle IDs to ignore.

## Build & run

Requires macOS 14+ and Swift 6 (Xcode Command Line Tools are enough).

```sh
make test   # run the self-test suite
make app    # build build/ClipShot.app
make run    # build and launch
```

The first screen capture prompts for the Screen Recording permission
(System Settings → Privacy & Security → Screen & System Audio Recording).

## Development

- `Sources/ClipShotKit` — library: history store, clipboard monitor,
  capture service, hotkey manager
- `Sources/ClipShot` — the menu bar app (AppKit shell + SwiftUI panel)
- `Sources/clipshot-selftest` — assertion-based tests run with
  `swift run clipshot-selftest` (Command Line Tools ship no XCTest)
- `docs/superpowers/specs/` — design docs
