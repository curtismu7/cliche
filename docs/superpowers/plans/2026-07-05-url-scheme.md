# URL-Scheme Automation (C7) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `cliche://` URLs (capture/ocr/repeat/panel) drive Cliché from Raycast, Shortcuts, and `open`(1).

**Architecture:** Pure `URLCommand.parse` in ClicheKit (selftest-covered); `CFBundleURLTypes` in the generated Info.plist; an `kAEGetURL` Apple Events handler in AppDelegate routing to the existing hotkey methods. No new capture logic.

**Tech Stack:** Swift 6 (v5 mode), macOS 14+, AppKit Apple Events. Tests via `cliche-selftest`.

## Global Constraints

- Platform floor macOS 14; no new dependencies; model code in ClicheKit, UI/app code in Cliche.
- Out of scope (spec): x-callback-url, format/destination params, history access, record/ruler/scroll URLs.
- Unrecognized URLs: `NSSound.beep()`, no other effect.

---

## File Structure

- **Create** `Sources/ClicheKit/URLCommand.swift` — parser (Task 1)
- **Modify** `Scripts/make-app.sh` — CFBundleURLTypes (Task 2)
- **Modify** `Sources/Cliche/AppDelegate.swift:27` — handler registration + routing (Task 2)
- **Modify** `README.md` — Automation section (Task 2)
- **Modify** `Sources/cliche-selftest/main.swift` — parser tests (Task 1)

---

### Task 1: `URLCommand` parser

**Files:**
- Create: `Sources/ClicheKit/URLCommand.swift`
- Test: `Sources/cliche-selftest/main.swift`

**Interfaces:**
- Produces: `public enum URLCommand: Equatable { case captureRegion, captureWindow, captureFullScreen, allInOne, ocr, repeatRegion, panel; public static func parse(_ url: URL) -> URLCommand? }`

- [x] **Step 1: Write the failing test**

Append to `Sources/cliche-selftest/main.swift` (after the `// allInOneHotkey` block):

```swift
// urlCommandParsing
do {
    func cmd(_ s: String) -> URLCommand? { URL(string: s).flatMap(URLCommand.parse) }
    expect(cmd("cliche://capture") == .captureRegion, "capture defaults to region")
    expect(cmd("cliche://capture?mode=region") == .captureRegion, "mode=region")
    expect(cmd("cliche://capture?mode=window") == .captureWindow, "mode=window")
    expect(cmd("cliche://capture?mode=fullscreen") == .captureFullScreen, "mode=fullscreen")
    expect(cmd("cliche://capture?mode=allinone") == .allInOne, "mode=allinone")
    expect(cmd("cliche://ocr") == .ocr && cmd("cliche://repeat") == .repeatRegion
        && cmd("cliche://panel") == .panel, "ocr/repeat/panel hosts parse")
    expect(cmd("CLICHE://CAPTURE?mode=Window") == .captureWindow,
        "scheme/host/mode are case-insensitive")
    expect(cmd("https://capture") == nil && cmd("cliche://nope") == nil
        && cmd("cliche://capture?mode=nope") == nil,
        "wrong scheme, unknown host, unknown mode → nil")
}
```

- [x] **Step 2: Run to verify it fails**

Run: `cd /Users/cmuir/Development/cliche && swift build 2>&1 | grep error: | head -3`
Expected: `cannot find 'URLCommand' in scope`

- [x] **Step 3: Write minimal implementation**

Create `Sources/ClicheKit/URLCommand.swift`:

```swift
import Foundation

/// Commands reachable via the cliche:// URL scheme (Raycast, Shortcuts,
/// `open`). Parsing is total: anything unrecognized returns nil.
public enum URLCommand: Equatable {
    case captureRegion, captureWindow, captureFullScreen,
         allInOne, ocr, repeatRegion, panel

    public static func parse(_ url: URL) -> URLCommand? {
        guard url.scheme?.lowercased() == "cliche" else { return nil }
        switch url.host?.lowercased() {
        case "capture":
            let mode = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name.lowercased() == "mode" }?
                .value?.lowercased() ?? "region"
            switch mode {
            case "region": return .captureRegion
            case "window": return .captureWindow
            case "fullscreen": return .captureFullScreen
            case "allinone": return .allInOne
            default: return nil
            }
        case "ocr": return .ocr
        case "repeat": return .repeatRegion
        case "panel": return .panel
        default: return nil
        }
    }
}
```

- [x] **Step 4: Run to verify it passes**

Run: `cd /Users/cmuir/Development/cliche && swift run cliche-selftest 2>&1 | grep -iE "mode=|hosts parse|case-insensitive|→ nil|FAIL"`
Expected: all `PASS`, no `FAIL`.

- [x] **Step 5: Commit**

```bash
git add Sources/ClicheKit/URLCommand.swift Sources/cliche-selftest/main.swift
git commit -m "feat(url-scheme): URLCommand parser for cliche:// automation"
```

---

### Task 2: Scheme registration, routing, docs

**Files:**
- Modify: `Scripts/make-app.sh` (Info.plist heredoc)
- Modify: `Sources/Cliche/AppDelegate.swift:27` (`applicationDidFinishLaunching`)
- Modify: `README.md`

**Interfaces:**
- Consumes: `URLCommand.parse` (Task 1); existing `capture(_:)`, `startAllInOne()`, `captureText()`, `repeatLastRegion()`, `togglePopover()`.

- [x] **Step 1: Register the scheme in the plist**

In `Scripts/make-app.sh`, inside the Info.plist heredoc, add before the closing `</dict>`:

```xml
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>org.coachcurtis.cliche.url</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>cliche</string>
            </array>
        </dict>
    </array>
```

- [x] **Step 2: Handle and route the URLs**

In `Sources/Cliche/AppDelegate.swift`, add at the top of `applicationDidFinishLaunching`:

```swift
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURLEvent(_:with:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))
```

Add near `perform(_:)`:

```swift
    /// cliche:// automation entry point (Raycast, Shortcuts, `open`).
    @objc private func handleURLEvent(
        _ event: NSAppleEventDescriptor, with reply: NSAppleEventDescriptor
    ) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string),
              let command = URLCommand.parse(url)
        else {
            NSSound.beep()
            return
        }
        switch command {
        case .captureRegion: capture(.region)
        case .captureWindow: capture(.window)
        case .captureFullScreen: capture(.fullScreen)
        case .allInOne: startAllInOne()
        case .ocr: captureText()
        case .repeatRegion: repeatLastRegion()
        case .panel: togglePopover()
        }
    }
```

- [x] **Step 3: README Automation section**

Add after the "Default shortcuts" section:

```markdown
## Automation

Drive Cliché from Raycast, Shortcuts, Alfred, or the terminal via its URL scheme:

| URL | Action |
| --- | --- |
| `cliche://capture` (or `?mode=region`) | Capture a region |
| `cliche://capture?mode=window` | Capture a window |
| `cliche://capture?mode=fullscreen` | Capture the full screen |
| `cliche://capture?mode=allinone` | All-in-one capture overlay |
| `cliche://ocr` | Copy text from screen |
| `cliche://repeat` | Repeat the last region |
| `cliche://panel` | Open the clipboard panel |

Example: `open "cliche://capture?mode=region"`
```

- [x] **Step 4: Verify**

Run: `cd /Users/cmuir/Development/cliche && swift run cliche-selftest >/dev/null 2>&1; echo exit=$?; make install 2>&1 | tail -1`
Expected: `exit=0`, app reinstalls.

Then: `sleep 2 && open "cliche://panel"` — the clipboard panel opens. `open "cliche://nope"` — beep, nothing else.

- [x] **Step 5: Commit**

```bash
git add Scripts/make-app.sh Sources/Cliche/AppDelegate.swift README.md
git commit -m "feat(url-scheme): register cliche:// and route to capture actions"
```

---

## Self-Review

**1. Spec coverage:** parser+tests → Task 1; plist, handler, routing, README → Task 2; beep on unknown → Task 2 Step 2 guard. ✓
**2. Placeholders:** none. ✓
**3. Type consistency:** `URLCommand` cases match between parser, tests, and routing switch. ✓
