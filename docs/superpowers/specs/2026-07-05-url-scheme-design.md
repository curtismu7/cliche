# URL-Scheme Automation (C7) — Design

Date: 2026-07-05
Status: Approved, ready for planning

## Goal

A `cliche://` URL scheme so Raycast, Shortcuts, Alfred, and `open`(1) can
drive capture. Research item **C7** in `docs/CAPTURE-RESEARCH.md`.

## Commands (approved scope)

- `cliche://capture` and `cliche://capture?mode=region` — region capture
- `cliche://capture?mode=window` — window capture
- `cliche://capture?mode=fullscreen` — full-screen capture
- `cliche://capture?mode=allinone` — all-in-one overlay
- `cliche://ocr` — copy text from screen
- `cliche://repeat` — repeat last region
- `cliche://panel` — open the clipboard panel

Out of scope: x-callback-url, format/destination parameters, history
access (privacy surface), record/ruler/scroll URLs.

## Architecture

1. **`URLCommand` (ClicheKit, pure, testable)**

```swift
public enum URLCommand: Equatable {
    case captureRegion, captureWindow, captureFullScreen,
         allInOne, ocr, repeatRegion, panel
    /// nil for anything not recognized — wrong scheme, unknown host,
    /// unknown mode. Never traps.
    public static func parse(_ url: URL) -> URLCommand?
}
```

Host selects the command; `capture` reads the `mode` query item
(default `region`). Case-insensitive scheme/host/mode.

2. **Info.plist** — `Scripts/make-app.sh` adds `CFBundleURLTypes`
registering the `cliche` scheme (name `org.coachcurtis.cliche.url`).

3. **AppDelegate** — registers an Apple Events handler for
`kInternetEventClass`/`kAEGetURL` in `applicationDidFinishLaunching`;
the handler parses the URL string and routes each command to the same
private methods the hotkeys use (`capture(.region)`, `startAllInOne()`,
`captureText()`, `repeatLastRegion()`, `togglePopover()`).
Unrecognized URLs `NSSound.beep()` and do nothing.

4. **README** — new "Automation" subsection listing the URLs with a
Raycast/terminal example (`open "cliche://capture?mode=region"`).

## Testing

- Selftest: every documented URL parses to the right command;
  `mode` defaults to region; case-insensitive; wrong scheme, unknown
  host, and unknown mode return nil.
- Manual: `open "cliche://capture"` from Terminal starts a region
  capture; `open "cliche://panel"` opens the panel; garbage URL beeps.

## Success Criteria

- All seven documented URLs work from Terminal via `open`.
- Parser fully covered in selftest; suite green.
- No new capture logic — routing only.
