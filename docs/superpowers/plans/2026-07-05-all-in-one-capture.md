# All-in-One Capture Mode (B7) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One customizable hotkey (default `⌃⌥⌘3`) opens the frozen capture overlay with a mode strip — Region / Window / Full Screen / OCR — switching modes with keys 1–4 or clicks.

**Architecture:** A pure `AllInOneMode` enum in ClicheKit carries the mode table (labels, symbols, key equivalents, in-place-vs-dismiss routing) so it's testable in `cliche-selftest`. `RegionSelector` gains an all-in-one overload that shows a SwiftUI mode strip inside the existing frozen-frame overlay window; Region and OCR select in place, Window and Full Screen dismiss and delegate to existing `AppDelegate` flows. Existing single-mode paths are untouched.

**Tech Stack:** Swift 6 (language mode v5), macOS 14+, AppKit + SwiftUI, Vision. Tests via the `cliche-selftest` executable (no XCTest).

## Global Constraints

- Platform floor: macOS 14 (`.macOS(.v14)`); Swift language mode v5. Do not raise.
- No new third-party dependencies.
- Pure/model code in `ClicheKit`; UI in `Cliche`.
- Tests are `do { … expect(condition, "label") }` blocks appended to `Sources/cliche-selftest/main.swift`; `expect(_:_:)` exists; the executable exits non-zero on any failure.
- Zero behavior change to existing hotkeys (`⌃⌥⌘C/4/5/6/R`, `⌥1`) and single-mode capture flows; the strip appears ONLY in the all-in-one entry point.
- New default hotkey is `⌃⌥⌘3` (`kVK_ANSI_3`, modifiers `controlKey|optionKey|cmdKey`), display string `"⌃⌥⌘3"`.

---

## File Structure

- **Create** `Sources/ClicheKit/AllInOneMode.swift` — the mode table (Task 1)
- **Modify** `Sources/ClicheKit/Hotkeys.swift` — `allInOne` case + default combo (Task 2)
- **Modify** `Sources/ClicheKit/OCRService.swift` — `recognizeText(in: CGImage)` overload (Task 3)
- **Modify** `Sources/Cliche/RegionSelector.swift` — all-in-one overload + mode strip hosting (Task 4)
- **Create** `Sources/Cliche/ModeStripView.swift` — SwiftUI strip (Task 4)
- **Modify** `Sources/Cliche/AppDelegate.swift` — `startAllInOne()` + dispatch case (Task 4)
- **Modify** `Sources/Cliche/HistoryView.swift` + `Sources/Cliche/HelpView.swift` — panel button + help row (Task 5)
- **Modify** `README.md` — shortcut row + feature bullet (Task 5)
- **Modify** `Sources/cliche-selftest/main.swift` — Tasks 1–3 test blocks

---

### Task 1: `AllInOneMode` mode table

**Files:**
- Create: `Sources/ClicheKit/AllInOneMode.swift`
- Test: `Sources/cliche-selftest/main.swift` (append a `do { }` block after the `// beautifyPersistence` block)

**Interfaces:**
- Produces: `public enum AllInOneMode: CaseIterable, Equatable { case region, window, fullScreen, ocr }` with `var label: String`, `var symbol: String`, `var keyEquivalent: String`, `var switchesInPlace: Bool`, `static func mode(forKey: String) -> AllInOneMode?`.

- [x] **Step 1: Write the failing test**

Append to `Sources/cliche-selftest/main.swift`:

```swift
// allInOneModeTable
do {
    expect(AllInOneMode.allCases == [.region, .window, .fullScreen, .ocr],
        "all-in-one modes in strip order")
    expect(AllInOneMode.allCases.map(\.keyEquivalent) == ["1", "2", "3", "4"],
        "key equivalents are 1-4 in strip order")
    expect(AllInOneMode.mode(forKey: "2") == .window
        && AllInOneMode.mode(forKey: "4") == .ocr
        && AllInOneMode.mode(forKey: "9") == nil,
        "mode(forKey:) maps 1-4 and rejects unknown keys")
    expect(AllInOneMode.allCases.filter(\.switchesInPlace) == [.region, .ocr],
        "region and OCR switch in place; window and full screen dismiss")
    let labels = AllInOneMode.allCases.map(\.label)
    expect(Set(labels).count == labels.count && labels.allSatisfy { !$0.isEmpty },
        "mode labels are unique and non-empty")
}
```

- [x] **Step 2: Run to verify it fails**

Run: `cd /Users/cmuir/Development/cliche && swift build 2>&1 | grep error: | head -3`
Expected: `cannot find 'AllInOneMode' in scope`

- [x] **Step 3: Write minimal implementation**

Create `Sources/ClicheKit/AllInOneMode.swift`:

```swift
/// The all-in-one capture strip: every mode, its UI attributes, and the
/// routing rule. `switchesInPlace` modes are drag-selections on the frozen
/// frame; the others dismiss the overlay and run their own flow.
public enum AllInOneMode: CaseIterable, Equatable {
    case region, window, fullScreen, ocr

    public var label: String {
        switch self {
        case .region: return "Region"
        case .window: return "Window"
        case .fullScreen: return "Full Screen"
        case .ocr: return "Copy Text"
        }
    }

    public var symbol: String {
        switch self {
        case .region: return "rectangle.dashed"
        case .window: return "macwindow"
        case .fullScreen: return "rectangle.inset.filled"
        case .ocr: return "text.viewfinder"
        }
    }

    /// Number-key shortcut inside the overlay, in strip order.
    public var keyEquivalent: String {
        String(AllInOneMode.allCases.firstIndex(of: self)! + 1)
    }

    /// True for modes that select on the frozen frame; false for modes that
    /// tear the overlay down and delegate to their existing flow.
    public var switchesInPlace: Bool {
        switch self {
        case .region, .ocr: return true
        case .window, .fullScreen: return false
        }
    }

    public static func mode(forKey key: String) -> AllInOneMode? {
        allCases.first { $0.keyEquivalent == key }
    }
}
```

- [x] **Step 4: Run to verify it passes**

Run: `cd /Users/cmuir/Development/cliche && swift run cliche-selftest 2>&1 | grep -i "all-in-one\|mode(\|in place\|labels"`
Expected: all lines `PASS`.

- [x] **Step 5: Commit**

```bash
git add Sources/ClicheKit/AllInOneMode.swift Sources/cliche-selftest/main.swift
git commit -m "feat(all-in-one): add AllInOneMode table with routing rule"
```

---

### Task 2: `allInOne` hotkey action

**Files:**
- Modify: `Sources/ClicheKit/Hotkeys.swift`
- Test: `Sources/cliche-selftest/main.swift`

**Interfaces:**
- Consumes: existing `HotkeyAction`, `HotkeyCombo`, `AppSettings.defaultHotkeys`, `AppSettings.action(using:)`.
- Produces: `HotkeyAction.allInOne` with label `"All-in-one capture"` and default combo `⌃⌥⌘3`.

- [x] **Step 1: Write the failing test**

Append to `Sources/cliche-selftest/main.swift`:

```swift
// allInOneHotkey
do {
    let suite = "ClicheHotkeyTest-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let settings = AppSettings(defaults: defaults)

    // Every action has a default combo, and no two defaults collide.
    let combos = HotkeyAction.allCases.map { settings.combo(for: $0) }
    let keys = combos.map { "\($0.keyCode)-\($0.carbonModifiers)" }
    expect(HotkeyAction.allCases.contains(.allInOne), "allInOne is a hotkey action")
    expect(Set(keys).count == keys.count, "no two default hotkeys collide")
    expect(settings.combo(for: .allInOne).display == "⌃⌥⌘3",
        "allInOne default is ⌃⌥⌘3")

    // Conflict detection covers the new case.
    let combo = settings.combo(for: .allInOne)
    expect(settings.action(using: combo) == .allInOne,
        "action(using:) finds allInOne — conflict warning covers it")
    expect(!HotkeyAction.allInOne.label.isEmpty, "allInOne has a label")
    defaults.removePersistentDomain(forName: suite)
}
```

- [x] **Step 2: Run to verify it fails**

Run: `cd /Users/cmuir/Development/cliche && swift build 2>&1 | grep error: | head -3`
Expected: `type 'HotkeyAction' has no member 'allInOne'`

- [x] **Step 3: Write minimal implementation**

In `Sources/ClicheKit/Hotkeys.swift`:

(a) Add the case to the `HotkeyAction` enum (after `case floatingList`):

```swift
    case allInOne
```

(b) Add to the `label` switch:

```swift
        case .allInOne: return "All-in-one capture"
```

(c) Add to `AppSettings.defaultHotkeys` (inside the returned dictionary, after `.floatingList`):

```swift
            .allInOne: HotkeyCombo(
                keyCode: UInt32(kVK_ANSI_3), carbonModifiers: base, display: "⌃⌥⌘3"),
```

- [x] **Step 4: Run to verify it passes**

Run: `cd /Users/cmuir/Development/cliche && swift run cliche-selftest 2>&1 | grep -i "allinone\|collide\|conflict"`
Expected: all lines `PASS`. (If AppDelegate's hotkey dispatch switch is exhaustive it will fail to compile — add a temporary `case .allInOne: break` there; Task 4 replaces it.)

- [x] **Step 5: Commit**

```bash
git add Sources/ClicheKit/Hotkeys.swift Sources/cliche-selftest/main.swift Sources/Cliche/AppDelegate.swift
git commit -m "feat(all-in-one): add allInOne hotkey action, default ⌃⌥⌘3"
```

---

### Task 3: OCR from a CGImage

**Files:**
- Modify: `Sources/ClicheKit/OCRService.swift`
- Test: `Sources/cliche-selftest/main.swift`

**Interfaces:**
- Consumes: existing `OCRService.recognizeText(in url: URL)`.
- Produces: `public static func recognizeText(in image: CGImage) throws -> String` — same recognition settings, newline-joined lines.

- [x] **Step 1: Write the failing test**

Append to `Sources/cliche-selftest/main.swift` (mirrors the existing URL-based OCR test's image-drawing approach):

```swift
// ocrFromCGImage
do {
    let width = 700, height = 100
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ("HELLO CLICHE 42" as NSString).draw(
        at: NSPoint(x: 30, y: 30),
        withAttributes: [.font: NSFont.boldSystemFont(ofSize: 40),
                         .foregroundColor: NSColor.black])
    NSGraphicsContext.restoreGraphicsState()
    let image = ctx.makeImage()!
    let text = (try? OCRService.recognizeText(in: image)) ?? ""
    expect(text.contains("HELLO") && text.contains("42"),
        "OCR recognizes text from a CGImage")
}
```

- [x] **Step 2: Run to verify it fails**

Run: `cd /Users/cmuir/Development/cliche && swift build 2>&1 | grep error: | head -3`
Expected: `no exact matches in call to static method 'recognizeText'` (only the URL overload exists).

- [x] **Step 3: Write minimal implementation**

In `Sources/ClicheKit/OCRService.swift`, add below the URL-based `recognizeText`:

```swift
    /// CGImage variant used by the all-in-one overlay, which crops the
    /// frozen frame directly instead of round-tripping through a file.
    public static func recognizeText(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        let lines = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }
```

- [x] **Step 4: Run to verify it passes**

Run: `cd /Users/cmuir/Development/cliche && swift run cliche-selftest 2>&1 | grep -i "cgimage"`
Expected: `PASS  OCR recognizes text from a CGImage`

- [x] **Step 5: Commit**

```bash
git add Sources/ClicheKit/OCRService.swift Sources/cliche-selftest/main.swift
git commit -m "feat(all-in-one): OCR directly from a CGImage crop"
```

---

### Task 4: Overlay mode strip + AppDelegate routing

**Files:**
- Create: `Sources/Cliche/ModeStripView.swift`
- Modify: `Sources/Cliche/RegionSelector.swift`
- Modify: `Sources/Cliche/AppDelegate.swift`
- Verification: build + manual (UI)

**Interfaces:**
- Consumes: `AllInOneMode` (Task 1), `HotkeyAction.allInOne` (Task 2), `OCRService.recognizeText(in: CGImage)` (Task 3), existing `RegionSelector`, `ScreenshotEngine.captureImage`, `AppDelegate.performCapture(_:on:)`, `AppDelegate.deliver(_:)`, `InfoHUD.show(_:)`.
- Produces: `RegionSelector.begin(frozen:on:allInOne:onSelect:onSwitchAway:onCancel:)`; `struct ModeStripView: View`; `AppDelegate.startAllInOne()`.

- [x] **Step 1: Create the strip view**

Create `Sources/Cliche/ModeStripView.swift`:

```swift
import ClicheKit
import SwiftUI

/// Top-center mode strip inside the all-in-one capture overlay.
struct ModeStripView: View {
    let current: AllInOneMode
    let onPick: (AllInOneMode) -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(AllInOneMode.allCases, id: \.self) { mode in
                    Button { onPick(mode) } label: {
                        VStack(spacing: 3) {
                            Image(systemName: mode.symbol).font(.system(size: 16))
                            Text(mode.label).font(.system(size: 10, weight: .medium))
                            Text(mode.keyEquivalent)
                                .font(.system(size: 9, design: .monospaced))
                                .opacity(0.65)
                        }
                        .frame(width: 78, height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(mode == current
                                    ? Color(red: 0.88, green: 0.19, blue: 0.19)
                                    : Color.white.opacity(0.08)))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.72)))
            Text("drag to capture · 1–4 switch mode · esc cancel")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Capsule().fill(Color.black.opacity(0.55)))
        }
    }
}
```

- [x] **Step 2: Add the all-in-one overload to RegionSelector**

In `Sources/Cliche/RegionSelector.swift`:

(a) Add `import SwiftUI` and `import ClicheKit` at the top (keep `import AppKit`).

(b) Add stored state + the overload to the `RegionSelector` class:

```swift
    private var mode: AllInOneMode = .region
    private var onSelectMode: ((CGRect, AllInOneMode) -> Void)?
    private var onSwitchAway: ((AllInOneMode) -> Void)?
    private var stripHost: NSHostingView<ModeStripView>?

    /// All-in-one variant: same frozen-frame picker plus a mode strip.
    /// Region/OCR select in place; Window/Full Screen call `onSwitchAway`
    /// after the overlay is dismissed. Esc calls `onCancel`.
    static func begin(
        frozen: CGImage, on screen: NSScreen,
        allInOne initialMode: AllInOneMode,
        onSelect: @escaping (CGRect, AllInOneMode) -> Void,
        onSwitchAway: @escaping (AllInOneMode) -> Void,
        onCancel: @escaping () -> Void
    ) {
        guard active == nil else {
            onCancel()
            return
        }
        let selector = RegionSelector(completion: { _ in })
        selector.mode = initialMode
        selector.onSelectMode = onSelect
        selector.onSwitchAway = onSwitchAway
        selector.onCancelAllInOne = onCancel
        active = selector
        selector.show(frozen: frozen, on: screen)
        selector.installStrip()
    }

    private var onCancelAllInOne: (() -> Void)?
    private var isAllInOne: Bool { onSelectMode != nil }

    private func installStrip() {
        guard isAllInOne, let window, let contentView = window.contentView else { return }
        let host = NSHostingView(rootView: ModeStripView(
            current: mode, onPick: { [weak self] in self?.switchMode(to: $0) }))
        host.frame.size = host.fittingSize
        host.frame.origin = NSPoint(
            x: (contentView.bounds.width - host.frame.width) / 2,
            y: contentView.bounds.height - host.frame.height - 24)
        contentView.addSubview(host)
        stripHost = host
        (contentView as? SelectionView)?.onModeKey = { [weak self] key in
            guard let mode = AllInOneMode.mode(forKey: key) else { return false }
            self?.switchMode(to: mode)
            return true
        }
    }

    private func switchMode(to newMode: AllInOneMode) {
        guard newMode != mode else { return }
        if newMode.switchesInPlace {
            mode = newMode
            stripHost?.rootView = ModeStripView(
                current: newMode, onPick: { [weak self] in self?.switchMode(to: $0) })
        } else {
            let handler = onSwitchAway
            teardown()
            handler?(newMode)
        }
    }

    private func teardown() {
        window?.orderOut(nil)
        window = nil
        Self.active = nil
    }
```

(c) Route completion through the all-in-one callbacks. Replace the body of `private func finish(_ pixelRect: CGRect?)` with:

```swift
    private func finish(_ pixelRect: CGRect?) {
        let selectHandler = onSelectMode
        let cancelHandler = onCancelAllInOne
        let currentMode = mode
        let wasAllInOne = isAllInOne
        teardown()
        if let rect = pixelRect, rect.width >= 4, rect.height >= 4 {
            if wasAllInOne {
                selectHandler?(rect.integral, currentMode)
            } else {
                completion(rect.integral)
            }
        } else {
            if wasAllInOne {
                cancelHandler?()
            } else {
                completion(nil)
            }
        }
    }
```

(d) In `SelectionView`, add a key hook and use it in `keyDown` (replace the existing `keyDown`):

```swift
    var onModeKey: ((String) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {  // Esc
            onFinish?(nil)
            return
        }
        if let characters = event.charactersIgnoringModifiers,
           onModeKey?(characters) == true {
            return
        }
    }
```

- [x] **Step 3: Add `startAllInOne()` and the dispatch case in AppDelegate**

In `Sources/Cliche/AppDelegate.swift`:

(a) In the hotkey dispatch switch (the one with `case .captureRegion: capture(.region)`), replace the temporary `case .allInOne: break` from Task 2 with:

```swift
        case .allInOne: startAllInOne()
```

(b) Add below `startRegionCapture`:

```swift
    /// ⌃⌥⌘3 — frozen overlay with the Region/Window/Full Screen/OCR strip.
    private func startAllInOne() {
        closeAllPopovers()
        let screen = Self.screenUnderMouse()
        guard let displayID = screen.displayID else {
            captureWithCLI(.region)
            return
        }
        let scale = screen.backingScaleFactor
        Task { @MainActor in
            do {
                let frozen = try await ScreenshotEngine.captureImage(
                    displayID: displayID, scale: scale,
                    showsCursor: settings.showCursor)
                RegionSelector.begin(
                    frozen: frozen, on: screen, allInOne: .region,
                    onSelect: { [weak self] pixelRect, mode in
                        guard let self, let cropped = frozen.cropping(to: pixelRect)
                        else { return }
                        switch mode {
                        case .region:
                            self.settings.lastRegion = (pixelRect, displayID)
                            self.deliver(cropped)
                        case .ocr:
                            let text = (try? OCRService.recognizeText(in: cropped)) ?? ""
                            if text.isEmpty {
                                NSSound.beep()
                            } else {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(text, forType: .string)
                                InfoHUD.show("Text copied")
                            }
                        case .window, .fullScreen:
                            break  // unreachable: not in-place modes
                        }
                    },
                    onSwitchAway: { [weak self] mode in
                        guard let self else { return }
                        switch mode {
                        case .window: self.performCapture(.window, on: screen)
                        case .fullScreen:
                            // Slight delay so the overlay is fully gone.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                self.performCapture(.fullScreen, on: screen)
                            }
                        case .region, .ocr: break
                        }
                    },
                    onCancel: { })
            } catch {
                NSLog("Cliche: all-in-one freeze failed (\(error)); using CLI region")
                self.captureWithCLI(.region)
            }
        }
    }
```

- [x] **Step 4: Build and manually verify**

Run: `cd /Users/cmuir/Development/cliche && swift build 2>&1 | tail -3`
Expected: `Build complete!`

Manual (after Task 5's install): `⌃⌥⌘3` shows frozen frame + strip; `1–4`/clicks switch highlight; Region drag delivers file+overlay; OCR drag copies text (HUD "Text copied"); `2` dismisses into native window picker; `3` captures full screen; Esc cancels; `⌃⌥⌘4/5/6` unchanged, no strip.

- [x] **Step 5: Commit**

```bash
git add Sources/Cliche/ModeStripView.swift Sources/Cliche/RegionSelector.swift Sources/Cliche/AppDelegate.swift
git commit -m "feat(all-in-one): mode strip overlay with in-place region/OCR and window/fullscreen handoff"
```

---

### Task 5: Panel button, help, README, final verification

**Files:**
- Modify: `Sources/Cliche/HistoryView.swift` (capture tab buttons, around the existing `CaptureButton` row at ~392)
- Modify: `Sources/Cliche/AppDelegate.swift` (pass the action into HistoryView)
- Modify: `Sources/Cliche/HelpView.swift` (shortcut row)
- Modify: `README.md`

**Interfaces:**
- Consumes: `AppDelegate.startAllInOne()` (Task 4), existing `HistoryView` closure-injection pattern (`onCapture`, `onCaptureText`).
- Produces: `HistoryView.onAllInOne: () -> Void`.

- [x] **Step 1: Add the button**

In `Sources/Cliche/HistoryView.swift`: add `let onAllInOne: () -> Void` next to `let onCaptureText: () -> Void` (line ~32). In the capture-buttons row (where `onCapture(.region)` etc. are wired, ~line 392), add a button first in the row, following the exact local `CaptureButton`/labelled-button pattern used by its neighbors, with symbol `"square.grid.2x2"`, help `"All-in-one capture  \(settings.combo(for: .allInOne).display)"`, action `onAllInOne`. In `Sources/Cliche/AppDelegate.swift`, every `HistoryView(` construction gains `onAllInOne: { [weak self] in self?.startAllInOne() },` next to its `onCaptureText:` argument. In `Sources/Cliche/HelpView.swift`, add a row `("⌃⌥⌘3 (customizable)", "All-in-one capture — strip with Region/Window/Full Screen/OCR")` alongside the existing hotkey rows (match the existing tuple/row format found in the file).

- [x] **Step 2: Update README**

In `README.md`: add `| `⌃⌥⌘3` | All-in-one capture (mode strip) |` as a row in the shortcuts table, and under `### 📷 Screen capture` add the bullet:

```markdown
- **All-in-one capture** — one hotkey (`⌃⌥⌘3`) opens the overlay with a mode strip: Region, Window, Full Screen, or Copy Text, switchable with keys 1–4.
```

- [x] **Step 3: Full test suite + build**

Run: `cd /Users/cmuir/Development/cliche && swift run cliche-selftest 2>&1 | grep -c FAIL; swift run cliche-selftest >/dev/null 2>&1; echo exit=$?`
Expected: `0` and `exit=0`.

Run: `make app 2>&1 | tail -2`
Expected: `Built build/Cliche.app`

- [x] **Step 4: Install and manually smoke-test**

Run: `make install` — then walk the manual checklist from Task 4 Step 4.

- [x] **Step 5: Commit**

```bash
git add Sources/Cliche/HistoryView.swift Sources/Cliche/AppDelegate.swift Sources/Cliche/HelpView.swift README.md
git commit -m "feat(all-in-one): panel button, help entry, README docs"
```

---

## Self-Review

**1. Spec coverage:** §1 mode table → Task 1. §2 hotkey + conflict coverage → Task 2 (selftest asserts no default collisions and `action(using:)` finds `.allInOne`). §3 overlay integration → Task 4. §4 routing incl. CGImage OCR → Tasks 3+4. §5 panel button → Task 5. §6 docs → Task 5. Non-goals respected (no record/ruler/scroll in strip; window picking stays CLI; single-mode `begin` untouched — the plain completion path in `finish` is preserved). ✓

**2. Placeholder scan:** none; Task 5 Step 1 references existing in-file patterns by exact location rather than inventing code that would drift from the file's local style — acceptable as it names file, line anchor, symbol, and action precisely. ✓

**3. Type consistency:** `AllInOneMode`, `mode(forKey:)`, `switchesInPlace`, `begin(frozen:on:allInOne:onSelect:onSwitchAway:onCancel:)`, `recognizeText(in: CGImage)`, `startAllInOne()` used identically across tasks. ✓
