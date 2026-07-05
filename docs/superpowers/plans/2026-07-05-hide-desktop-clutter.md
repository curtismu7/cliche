# Hide Desktop Clutter (C8) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Settings toggle that removes Finder's desktop-icon windows from every ScreenCaptureKit capture and recording, keeping the wallpaper.

**Architecture:** A pure `DesktopClutter.isDesktopIconWindow` classifier (selftest-covered) plus a shared `exclusions(in:hideDesktopIcons:)` helper used by both `ScreenshotEngine` and `ScreenRecorder` when building their `SCContentFilter`. A defaulted `hideDesktopIcons` parameter threads from `AppSettings` through the existing call sites, mirroring how `showsCursor` flows.

**Tech Stack:** Swift 6 (v5 mode), macOS 14+, ScreenCaptureKit. Tests via `cliche-selftest`.

## Global Constraints

- Platform floor macOS 14; no new dependencies; model code in ClicheKit.
- Toggle default **off**; persisted like `showCursor`.
- CLI fallback (`screencapture`) and native window picking are unaffected (can't filter windows) — documented, not worked around.
- Existing behavior unchanged when the toggle is off (parameter defaults to `false`).

---

## File Structure

- **Create** `Sources/ClicheKit/DesktopClutter.swift` — classifier + SCWindow exclusion helper (Task 1)
- **Modify** `Sources/ClicheKit/AppSettings.swift` — `hideDesktopIcons` toggle (Task 1)
- **Modify** `Sources/ClicheKit/ScreenshotEngine.swift:20-29` — use the helper (Task 2)
- **Modify** `Sources/ClicheKit/ScreenRecorder.swift:30-39` — use the helper (Task 2)
- **Modify** `Sources/Cliche/AppDelegate.swift` (captureImage call sites at 320/348/404/424/497/513/541), `Sources/Cliche/ScrollingCapture.swift:69`, `Sources/Cliche/RecordingController.swift` — thread the flag (Task 2)
- **Modify** `Sources/Cliche/SettingsView.swift:44` area + `README.md` (Task 2)
- **Modify** `Sources/cliche-selftest/main.swift` — classifier + persistence tests (Task 1)

---

### Task 1: Classifier + settings toggle

**Files:**
- Create: `Sources/ClicheKit/DesktopClutter.swift`
- Modify: `Sources/ClicheKit/AppSettings.swift`
- Test: `Sources/cliche-selftest/main.swift`

**Interfaces:**
- Produces: `DesktopClutter.isDesktopIconWindow(owningBundleID: String?, windowLayer: Int) -> Bool`; `DesktopClutter.exclusions(in: [SCWindow], hideDesktopIcons: Bool) -> [SCWindow]` (own windows + optional icon windows); `AppSettings.hideDesktopIcons: Bool`.

- [ ] **Step 1: Write the failing test**

Append to `Sources/cliche-selftest/main.swift` (after the `// urlCommandParsing` block):

```swift
// desktopClutter
do {
    let iconLayer = Int(CGWindowLevelForKey(.desktopIconWindow))
    expect(DesktopClutter.isDesktopIconWindow(
        owningBundleID: "com.apple.finder", windowLayer: iconLayer),
        "Finder window at desktop-icon layer is clutter")
    expect(!DesktopClutter.isDesktopIconWindow(
        owningBundleID: "com.apple.finder", windowLayer: 0),
        "normal Finder window is not clutter")
    expect(!DesktopClutter.isDesktopIconWindow(
        owningBundleID: "com.example.other", windowLayer: iconLayer),
        "non-Finder window at icon layer is not clutter")
    expect(!DesktopClutter.isDesktopIconWindow(
        owningBundleID: nil, windowLayer: iconLayer),
        "nil bundle id is not clutter")

    let suite = "ClicheClutterTest-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let settings = AppSettings(defaults: defaults)
    expect(!settings.hideDesktopIcons, "hideDesktopIcons defaults to off")
    settings.hideDesktopIcons = true
    expect(AppSettings(defaults: defaults).hideDesktopIcons,
        "hideDesktopIcons persists")
    defaults.removePersistentDomain(forName: suite)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd /Users/cmuir/Development/cliche && swift build 2>&1 | grep error: | head -3`
Expected: `cannot find 'DesktopClutter' in scope`

- [ ] **Step 3: Write minimal implementation**

Create `Sources/ClicheKit/DesktopClutter.swift`:

```swift
import ScreenCaptureKit

/// Identifies the Finder windows that draw desktop icons so captures can
/// exclude them (the wallpaper is a different layer and stays visible).
public enum DesktopClutter {
    public static func isDesktopIconWindow(
        owningBundleID: String?, windowLayer: Int
    ) -> Bool {
        owningBundleID == "com.apple.finder"
            && windowLayer == Int(CGWindowLevelForKey(.desktopIconWindow))
    }

    /// The windows a capture should exclude: Cliché's own windows, plus —
    /// when `hideDesktopIcons` — Finder's desktop-icon windows.
    public static func exclusions(
        in windows: [SCWindow], hideDesktopIcons: Bool
    ) -> [SCWindow] {
        let ownPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        return windows.filter { window in
            if window.owningApplication?.processID == ownPID { return true }
            guard hideDesktopIcons else { return false }
            return isDesktopIconWindow(
                owningBundleID: window.owningApplication?.bundleIdentifier,
                windowLayer: window.windowLayer)
        }
    }
}
```

In `Sources/ClicheKit/AppSettings.swift`, add after `windowShadow`:

```swift
    /// Exclude Finder's desktop-icon windows from captures (wallpaper stays).
    public var hideDesktopIcons: Bool {
        didSet { defaults.set(hideDesktopIcons, forKey: "hideDesktopIcons") }
    }
```

and in `init` (after the `windowShadow` line):

```swift
        self.hideDesktopIcons =
            defaults.object(forKey: "hideDesktopIcons") as? Bool ?? false
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd /Users/cmuir/Development/cliche && swift run cliche-selftest 2>&1 | grep -iE "clutter|hideDesktopIcons|FAIL"`
Expected: all `PASS`, no `FAIL`.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClicheKit/DesktopClutter.swift Sources/ClicheKit/AppSettings.swift Sources/cliche-selftest/main.swift
git commit -m "feat(clutter): desktop-icon window classifier and settings toggle"
```

---

### Task 2: Wire through engine, recorder, call sites, UI, docs

**Files:**
- Modify: `Sources/ClicheKit/ScreenshotEngine.swift`, `Sources/ClicheKit/ScreenRecorder.swift`
- Modify: `Sources/Cliche/AppDelegate.swift`, `Sources/Cliche/ScrollingCapture.swift`, `Sources/Cliche/RecordingController.swift`
- Modify: `Sources/Cliche/SettingsView.swift`, `README.md`

**Interfaces:**
- Consumes: `DesktopClutter.exclusions(in:hideDesktopIcons:)`, `AppSettings.hideDesktopIcons` (Task 1).
- Produces: `ScreenshotEngine.captureImage(displayID:sourceRect:scale:showsCursor:hideDesktopIcons:)` (new defaulted param); same on `ScreenRecorder.start` / `RecordingController.begin` / `ScrollingCapture.begin`.

- [ ] **Step 1: Engine + recorder use the shared exclusion helper**

In `Sources/ClicheKit/ScreenshotEngine.swift`, add parameter `hideDesktopIcons: Bool = false` after `showsCursor` and replace the own-windows filter block with:

```swift
        let excluded = DesktopClutter.exclusions(
            in: content.windows, hideDesktopIcons: hideDesktopIcons)
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
```

Apply the same two changes in `Sources/ClicheKit/ScreenRecorder.swift` (`start` gains `hideDesktopIcons: Bool = false`; its own-windows block becomes the helper call).

- [ ] **Step 2: Thread the flag from settings**

In `Sources/Cliche/AppDelegate.swift`, every `ScreenshotEngine.captureImage(...)` call gains `hideDesktopIcons: settings.hideDesktopIcons` (7 sites — lines ~320/348/404/424/497/513/541). `RecordingController.begin` and `ScrollingCapture.begin` each gain a `hideDesktopIcons: Bool` parameter passed through to their internal `ScreenRecorder.start`/`captureImage` calls; AppDelegate passes `settings.hideDesktopIcons` at those two call sites.

- [ ] **Step 3: Settings row + README**

In `Sources/Cliche/SettingsView.swift`, after the "Show mouse pointer" toggle:

```swift
                    Toggle("Hide desktop icons in captures", isOn: $settings.hideDesktopIcons)
```

In `README.md`, under `### 📷 Screen capture` add:

```markdown
- **Hide desktop clutter** — a Settings toggle excludes desktop icons from captures and recordings; your wallpaper stays.
```

- [ ] **Step 4: Verify**

Run: `cd /Users/cmuir/Development/cliche && swift run cliche-selftest >/dev/null 2>&1; echo exit=$?; make install 2>&1 | tail -1`
Expected: `exit=0`; app reinstalls. Manual: toggle on in Settings, full-screen capture → icons gone, wallpaper present.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClicheKit Sources/Cliche README.md
git commit -m "feat(clutter): hide desktop icons across captures and recordings"
```

---

## Self-Review

**1. Spec coverage:** classifier+toggle → Task 1; engine/recorder/call-site wiring, Settings UI, README → Task 2. CLI-fallback limitation is documentation-only per spec. ✓
**2. Placeholders:** none. ✓
**3. Type consistency:** `exclusions(in:hideDesktopIcons:)` and the defaulted `hideDesktopIcons` param named identically across engine, recorder, controllers. ✓
