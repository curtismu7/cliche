# Cliché

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
  ScreenCaptureKit (instant, silent, Cliché's own windows excluded).
  Region selection happens on a **frozen frame** with a magnifier loupe,
  live pixel-size label, and Shift-to-lock-square; `⌃⌥⌘R` recaptures the
  exact previous region with no UI. Optional capture timer (3/5/10 s),
  show-cursor and window-shadow settings. Window capture uses the native
  macOS picker. Screenshots land on the Desktop and the clipboard. If
  ScreenCaptureKit is unavailable, capture falls back to the system
  `screencapture` tool automatically.
- **QR codes** — captures containing a QR code get a "copy its link" button
  on the post-capture thumbnail.
- **Before/after GIFs** — combine any capture with the previous one into a
  looping two-frame GIF from the Captures tab.
- **Contrast checker** — pick two colors in a row with the eyedropper and
  Cliché shows the WCAG contrast ratio and AA/AAA verdict.
- **Pixel ruler** — measure anything on screen: hover snaps to UI element
  edges and shows its size, drag measures point-to-point, click copies.
- **Scrolling capture** — select a region, scroll the content yourself, and
  Cliché stitches the frames into one tall image (Vision-aligned).
- **Screen recording** — record a region to MP4 on the Desktop, with an
  optional GIF export, driven by a floating stop/timer HUD.
- **Beautify backdrops** — the annotation editor can wrap any shot in a
  gradient backdrop with padding, rounded corners, and a drop shadow.
- **Auto-redaction** — one click in the editor blurs everything that looks
  sensitive: emails, links, phone numbers, API-key-shaped tokens.
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
- **Captures tab** — a thumbnail grid of past screenshots with share
  (AirDrop/Mail/Messages), copy, annotate, show-in-Finder, move-to-Trash,
  and float actions.
- **Color picker** — eyedropper button opens the native magnifier loupe;
  the picked pixel's hex code (e.g. `#3A7BD5`) is copied to the clipboard.
- **Edit clips** — hover a text item's ✏️ to edit its content in place
  (position and pin state are kept).
- **Float on top** — pin any screenshot or history image as an always-on-top
  window for reference while you work.
- **Settings** (gear button) — screenshot format (PNG or JPEG), whether
  captures are copied to the clipboard (all modes, including whole-screen)
  or saved to disk only, launch at login, and the ignore-rules editor.
  Images are always written to the clipboard as both PNG and TIFF so every
  app can paste them.
- **Global hotkeys** — no Accessibility permission required:
  - `⌃⌥⌘C` — open/close the history panel
  - `⌃⌥⌘4` — capture region
  - `⌃⌥⌘5` — capture window
  - `⌃⌥⌘6` — copy text from screen (OCR)
  - `⌃⌥⌘R` — repeat the last region capture

History persists across restarts in `~/Library/Application Support/Cliche/`.
Content marked concealed/transient/auto-generated (e.g. password managers) is
never recorded; gear menu → "Edit Ignore Rules…" opens `ignore-rules.json`
where you can add more pasteboard types or app bundle IDs to ignore.

## Build & run

Requires macOS 14+ and Swift 6 (Xcode Command Line Tools are enough).

```sh
make test   # run the self-test suite
make app    # build build/Cliche.app
make run    # build and launch
```

The first screen capture prompts for the Screen Recording permission
(System Settings → Privacy & Security → Screen & System Audio Recording).

## Development

- `Sources/ClicheKit` — library: history store, clipboard monitor,
  capture service, hotkey manager
- `Sources/Cliche` — the menu bar app (AppKit shell + SwiftUI panel)
- `Sources/cliche-selftest` — assertion-based tests run with
  `swift run cliche-selftest` (Command Line Tools ship no XCTest)
- `docs/superpowers/specs/` — design docs
