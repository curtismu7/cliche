# All-in-One Capture Mode (B7) — Design

Date: 2026-07-05
Status: Approved, ready for planning

## Goal

One hotkey opens the capture overlay with a mode strip — **Region, Window,
Full Screen, OCR** — so every capture tool is one keystroke apart
(CleanShot X's signature UX). Research item **B7** in
`docs/CAPTURE-RESEARCH.md`.

## Decisions (from brainstorm)

- Mode set: the core four only — Region, Window, Full Screen, OCR. No
  Record/Ruler/Scrolling in the strip (deferred).
- Trigger: a **new** customizable hotkey (default `⌃⌥⌘3`) plus a button in
  the capture panel. All existing per-mode hotkeys keep working unchanged.
- Approach: integrated frozen overlay. Region and OCR switch **in place**
  on the frozen frame; Window and Full Screen dismiss the overlay and run
  the existing flows.

## Current State (seams this builds on)

- `RegionSelector` (Sources/Cliche/RegionSelector.swift) — frozen-frame
  region picker: borderless window, `SelectionView` with loupe/size
  label/Shift-square, completion delivers a pixel `CGRect?`.
- `AppDelegate.performCapture(_:on:)` routes `.region/.window/.fullScreen`;
  `captureText()` is the OCR flow (freeze → select → `OCRService`).
- `HotkeyAction` (Sources/ClicheKit/Hotkeys.swift) — enum of global
  hotkeys with default combos; Settings UI derives from `allCases`.

## Architecture

### 1. `AllInOneMode` (ClicheKit — pure, testable)

```swift
public enum AllInOneMode: CaseIterable {
    case region, window, fullScreen, ocr

    public var label: String        // "Region", "Window", "Full Screen", "Copy Text"
    public var symbol: String       // SF Symbol name for the strip button
    public var keyEquivalent: String  // "1"..."4" (strip order)
    public var switchesInPlace: Bool  // region/ocr = true; window/fullScreen = false
    public static func mode(forKey: String) -> AllInOneMode?  // "1"..."4" lookup
}
```

`switchesInPlace` is the routing rule: `true` modes stay in the frozen
overlay (the selection rect's meaning changes); `false` modes tear the
overlay down and hand off to the existing AppDelegate flow. This mapping
is covered in `cliche-selftest`.

### 2. Hotkey

`HotkeyAction` gains `case allInOne` ("All-in-one capture", default
`⌃⌥⌘3` — `kVK_ANSI_3` with the same base modifiers as the other capture
keys; `3` is unused among existing defaults). The Settings hotkey editor
picks it up automatically via `allCases`, including the existing
**conflict warning** (recording a combo owned by another action beeps,
shows "Already used by …", and refuses to save — `HotkeyRecorderRow` +
`HotkeyManager.action(using:)`). Conflicts with other apps' global
hotkeys are not detectable on macOS; the ⌃⌥⌘ prefix convention is the
mitigation. `AppDelegate`'s hotkey dispatch adds
`case .allInOne: startAllInOne()`.

### 3. Overlay integration

`RegionSelector.begin` gains an overload:

```swift
static func begin(frozen: CGImage, on screen: NSScreen,
                  allInOne initialMode: AllInOneMode,
                  onSelect: @escaping (CGRect, AllInOneMode) -> Void,
                  onSwitchAway: @escaping (AllInOneMode) -> Void,
                  onCancel: @escaping () -> Void)
```

When invoked this way, `SelectionView` shows a **mode strip**: a rounded
horizontal bar top-center of the frozen frame (NSHostingView with a small
SwiftUI `ModeStripView`), one button per `AllInOneMode` with icon, label,
and `1–4` badge; the current mode is highlighted in the brand red. A hint
line ("drag to capture · 1–4 switch mode · esc cancel") sits under it.

- Keys `1–4` and strip clicks set the mode.
- Switching to an in-place mode just updates the strip highlight and the
  crosshair behavior (Region and OCR are both drag-selects on the frozen
  frame).
- Switching to Window or Full Screen calls `onSwitchAway(mode)`; the
  selector dismisses first so the overlay isn't in the shot.
- Finishing a drag calls `onSelect(pixelRect, currentMode)`.
- Esc calls `onCancel`.
- The existing single-mode `begin(frozen:on:completion:)` is untouched;
  the strip never appears in the plain region/OCR/repeat flows.

### 4. AppDelegate routing

```text
startAllInOne():
    freeze display (same as startRegionCapture)
    RegionSelector.begin(allInOne: .region,
        onSelect: { rect, mode in
            switch mode {
            case .region: crop + deliver(cropped)      // existing path
            case .ocr:    crop + OCR → clipboard HUD    // existing captureText tail
            default: unreachable (in-place modes only)
            }
        },
        onSwitchAway: { mode in
            case .window:     performCapture(.window, on: screen)
            case .fullScreen: performCapture(.fullScreen, on: screen)
        },
        onCancel: { })
```

OCR in the all-in-one path recognizes the frozen-frame crop directly:
`OCRService` gains a `static func recognizeText(in image: CGImage) throws
-> String` overload (same Vision request as the existing URL-based one,
via `VNImageRequestHandler(cgImage:)`), and the clipboard/beep tail is
shared. The existing `captureText()` flow (`screencapture -i` → temp file)
is untouched.

### 5. Capture panel button

The capture panel (HistoryView capture tab) gains an "All-in-one" button
alongside the existing capture buttons, with its hotkey label under it,
matching the current button style.

### 6. Docs

README: add the `⌃⌥⌘3` row to the shortcuts table and a one-line feature
bullet under Screen capture.

## Non-Goals

- Record / Ruler / Scrolling in the strip (deferred; the strip design
  makes adding a button trivial later).
- Reimplementing window picking inside the overlay (stays `screencapture -iW`).
- Changing any existing hotkey or single-mode flow.

## Testing

- `cliche-selftest`: `AllInOneMode` mapping — `allCases` order and
  key-equivalents `1–4`; `mode(forKey:)` round-trip and unknown-key nil;
  `switchesInPlace` true exactly for region/ocr; labels non-empty and
  unique. Hotkeys: no two default combos collide (pairwise across
  `HotkeyAction.allCases`, now including `allInOne`), and
  `action(using:)` finds the `allInOne` default (conflict detection
  covers the new case).
- Manual: `⌃⌥⌘3` opens frozen overlay with strip; 1–4 and clicks switch
  highlight; drag in Region delivers a capture (file + overlay); drag in
  OCR lands text on clipboard; Window/Full Screen dismiss the overlay and
  run their native flows; Esc cancels cleanly; existing ⌃⌥⌘4/5/6 flows
  show no strip and behave exactly as before.

## Success Criteria

- One hotkey reaches all four capture tools; switching is one keystroke.
- Zero behavior change to existing per-mode hotkeys and flows.
- Mode-routing table covered by selftest; build + selftest green.
