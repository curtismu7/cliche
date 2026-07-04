# ClipShot — Design Spec

**Date:** 2026-07-04
**Status:** Approved by user

## What

A macOS menu bar utility combining a clipboard history manager and screen capture, in one app. Repo: `~/Development/clipshot`.

## Constraints

- Built with Swift Package Manager only (no full Xcode installed — Command Line Tools, Swift 6.3, macOS 26).
- Native app: Swift 6 + SwiftUI UI hosted in an AppKit `NSStatusItem` popover. No Dock icon (`LSUIElement`).
- Minimum deployment target: macOS 14.

## Features (MVP)

### Clipboard history
- Poll `NSPasteboard.general.changeCount` every 0.5 s (macOS has no change notification API).
- Record plain text and images (PNG/TIFF). Skip transient/concealed pasteboard types (e.g. password managers marking `org.nspasteboard.ConcealedType`).
- Deduplicate identical items (re-copy moves the item to the front); caps: 150 text items and 50 images (oldest unpinned evicted per kind).
- Click a history row → item is written back to the clipboard.
- Pin items (hover button): pinned items are never evicted, survive Clear History, and show in a Pinned section.
- Remove individual items (hover trash button).
- "Clear" button empties unpinned history (and persisted files).
- Persistence: text items in `history.json`, images as PNG files, both under `~/Library/Application Support/ClipShot/`. Loaded on launch.

### Screen capture
- Shell out to `/usr/sbin/screencapture`:
  - Region: `screencapture -i <file>`
  - Window: `screencapture -iWo <file>` (window-selection mode, no shadow)
  - Full screen: `screencapture <file>`
- Output: timestamped PNG on the Desktop (`ClipShot 2026-07-04 at 09.41.03.png`) **and** copied to the clipboard, so it flows into history via the monitor.
- First capture triggers the macOS Screen Recording permission prompt (expected, unavoidable).

### Global hotkeys
- Carbon `RegisterEventHotKey` (no Accessibility permission required).
- ⌃⌥⌘C — toggle history panel; ⌃⌥⌘4 — region capture; ⌃⌥⌘5 — window capture.

### UI (popover)
- Header row: three capture buttons (Region / Window / Full Screen) + Quit.
- Scrollable history list: text previews (2-line truncation) and image thumbnails; click to re-copy.
- Footer: Clear History.

## Components

| Component | Responsibility | Depends on |
|---|---|---|
| `ClipShotApp` / `AppDelegate` | Status item, popover, wiring | all below |
| `ClipboardMonitor` | Poll pasteboard, emit new `ClipItem`s | HistoryStore |
| `HistoryStore` | In-memory list + JSON/PNG persistence, `@Observable` for SwiftUI | — |
| `CaptureService` | Run `screencapture`, put result on clipboard | — |
| `HotkeyManager` | Carbon hotkey registration → callbacks | — |
| `HistoryView` (SwiftUI) | Popover UI | HistoryStore, CaptureService |

## Packaging

- `swift build -c release` produces the executable; `Scripts/make-app.sh` assembles `ClipShot.app` (Contents/MacOS + Info.plist with `LSUIElement=true`, bundle id `org.coachcurtis.clipshot`).
- `make app` / `make run` convenience Makefile.

## Error handling

- `screencapture` non-zero exit or missing file (user pressed Esc) → silently ignore (matches native behavior).
- Persistence read/write failures → log and continue with in-memory history; never crash the app.
- Clipboard items with unsupported types → ignored.

## Testing

- Unit tests (swift-testing) for `HistoryStore`: append/dedupe/cap/clear/persist-reload round-trip.
- `ClipItem` codable round-trip.
- Manual verification checklist (clipboard capture, re-copy, three capture modes, hotkeys, relaunch persistence) — UI/permission flows can't be unit-tested headlessly.

## Success criteria

1. `swift build` and `swift test` pass.
2. App launches to menu bar; no Dock icon.
3. Copying text/images elsewhere appears in the panel within ~1 s.
4. Clicking a row restores that item to the clipboard.
5. Each capture mode produces a Desktop PNG and a clipboard image that appears in history.
6. History survives app relaunch.
