# ClipShot

A macOS menu bar app combining a clipboard history manager and screen capture.

## Features

- **Clipboard history** — remembers the last 150 text snippets and 50 images
  copied anywhere on your Mac. Click any item to copy it back. Pin items to
  keep them forever (pinned items survive Clear History and are never evicted).
- **Screen capture** — region, window, or full screen via the native macOS
  capture UI. Screenshots land on the Desktop as PNG and on the clipboard
  (so they also appear in history).
- **Global hotkeys** — no Accessibility permission required:
  - `⌃⌥⌘C` — open/close the history panel
  - `⌃⌥⌘4` — capture region
  - `⌃⌥⌘5` — capture window

History persists across restarts in `~/Library/Application Support/ClipShot/`.
Content marked concealed/transient (e.g. password managers) is ignored.

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
