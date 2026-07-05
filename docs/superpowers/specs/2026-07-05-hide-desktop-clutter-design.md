# Hide Desktop Clutter (C8) — Design

Date: 2026-07-05
Status: Approved, ready for planning

## Goal

A Settings toggle that removes desktop icons from captures and recordings
while keeping the wallpaper. Research item **C8** in
`docs/CAPTURE-RESEARCH.md`.

## Behavior

- `Settings → Capture`: "Hide desktop icons in captures" (default **off**).
- When on, every ScreenCaptureKit path — region (frozen frame), full
  screen, repeat-area, all-in-one, scrolling capture, and screen
  recording — excludes the Finder windows that draw desktop icons.
- Wallpaper is a different window layer and stays visible.
- The `screencapture` CLI fallback and native window picking cannot
  filter windows; the toggle does not apply there (documented).

## Architecture

1. **`AppSettings.hideDesktopIcons: Bool`** — persisted UserDefaults
   toggle, same `didSet` pattern as `showCursor`.

2. **`DesktopClutter` (ClicheKit, pure, testable)**

```swift
public enum DesktopClutter {
    /// True for the Finder-owned windows that draw desktop icons
    /// (window layer kCGDesktopIconWindowLevel).
    public static func isDesktopIconWindow(
        owningBundleID: String?, windowLayer: Int
    ) -> Bool
}
```

Returns true iff `owningBundleID == "com.apple.finder"` and
`windowLayer == Int(CGWindowLevelForKey(.desktopIconWindow))`.

3. **Engine/recorder wiring** — `ScreenshotEngine.captureImage` gains
   `hideDesktopIcons: Bool = false`; when true, windows matching the
   classifier are appended to the existing own-windows exclusion before
   building `SCContentFilter`. `ScreenRecorder` applies the same append.
   All `captureImage`/recorder call sites in AppDelegate pass
   `settings.hideDesktopIcons`.

4. **SettingsView** — toggle row beside "Show cursor".

5. **README** — one bullet under Screen capture noting the toggle and
   the wallpaper-stays behavior.

## Testing

- Selftest (pure classifier): Finder + icon layer → true; Finder +
  layer 0 → false; other bundle at icon layer → false; nil bundle →
  false. Settings default off + persistence round-trip.
- Manual: toggle on, full-screen capture → icons gone, wallpaper
  present; toggle off → icons back.

## Success Criteria

- Toggle works across region/fullscreen/repeat/all-in-one/record.
- Default off; persisted; selftest green.
