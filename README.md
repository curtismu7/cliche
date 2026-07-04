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
- **Paste directly** — `⌥Return`, `⌥-click`, or a row's ↵ hover button pastes
  the item straight into the app you were using (works for images too).
  Requires the Accessibility permission, requested only on first use; until
  granted, the item is on the clipboard for a manual `⌘V`.
- **Snippets** — reusable text templates in their own tab, with `%DATE%`,
  `%TIME%`, and `%CLIPBOARD%` variables rendered at copy time. Click to copy,
  ⌥-click to paste directly.
- **Screen capture** — region and full-screen captures run in-process via
  ScreenCaptureKit (instant, silent, ClipShot's own windows excluded); region
  selection uses ClipShot's crosshair overlay (drag to select, Esc cancels).
  Window capture uses the native macOS picker. Screenshots land on the
  Desktop as PNG and on the clipboard (so they also appear in history).
  If ScreenCaptureKit is unavailable, capture falls back to the system
  `screencapture` tool automatically.
- **Copy text from screen (OCR)** — the Text button (or `⌃⌥⌘6`) lets you
  select any region; the text in it is recognized on-device with Apple's
  Vision framework and copied to the clipboard. Beeps if no text was found.
- **Quick Access Overlay** — after each capture a small thumbnail floats in
  the bottom-left corner: drag it straight into another app, click it to
  annotate, or let it auto-dismiss after a few seconds.
- **Annotation editor** — arrows, rectangles, text labels, pixelate/redact,
  and auto-numbered counter badges. ⌘Z undoes, Copy puts the annotated image
  on the clipboard, Save overwrites the capture file. Open it from the
  overlay or any capture's ✏️ button.
- **Captures tab** — a thumbnail grid of past screenshots with copy,
  annotate, show-in-Finder, move-to-Trash, and float actions.
- **Float on top** — pin any screenshot or history image as an always-on-top
  window for reference while you work.
- **Launch at login** — toggle in the gear menu (System Settings shows it
  under Login Items).
- **Global hotkeys** — no Accessibility permission required:
  - `⌃⌥⌘C` — open/close the history panel
  - `⌃⌥⌘4` — capture region
  - `⌃⌥⌘5` — capture window
  - `⌃⌥⌘6` — copy text from screen (OCR)

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
