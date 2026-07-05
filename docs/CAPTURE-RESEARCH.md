# Capture Feature Research — Round 2 (2026-07-04)

Deep survey of screen-capture tools beyond the initial roadmap research,
focused on capture-side features ClipShot doesn't have yet.

## Long-Tail Survey (features NOT already in ClipShot)

**CleanShot X** ([features](https://cleanshot.com/features)) — Beyond what ClipShot has: self-timer with countdown; "advanced capture modes" (screen **freeze** during selection, crosshair magnifier/loupe); window capture with **transparent background or padded backdrop** and window-shadow toggle; **Background tool** (10 built-in backdrops, custom uploads, auto-balance alignment, padding, aspect-ratio presets for social posts); **All-in-One mode** (one hotkey, switch modes in the overlay, custom pixel size entry, aspect-ratio lock, last-selection memory); combine multiple images by drag-drop in editor; save-as-editable project files; extra annotation tools ClipShot lacks (ellipse, line, freehand pencil with smoothing, highlighter, **spotlight**, blur as distinct from pixelate, curved arrows, 7 text styles); crop with aspect ratio + edge snapping; full recording suite (MP4/GIF, mic + system audio, auto-DND, click highlights, keystroke display, webcam bubble, trim editor); cloud upload with self-destructing/password links; "hide desktop clutter"; URL-scheme API; capture-history filters by type.

**Shottr** ([shottr.cc](https://shottr.cc/), [changelog](https://shottr.cc/newversion.html)) — **Pixel ruler / screen measurement** (measure distances, Shift for outer size of element, click to *imprint* the measurement onto the screenshot); **Repeat Area Screenshot** hotkey (retake exact previous region); **QR code detection** during OCR; **Backdrop tool** (gradients, shadows, rounded corners); **WCAG 2.0 + APCA color-contrast checker** built into the color tools; text-only blur/erase (hides text without touching surrounding pixels); object removal/erase; image overlay (paste an image onto a screenshot); **before/after two-frame GIFs**; magnifier callout annotation; hand-drawn annotation style; S3 upload; scrolling capture.

**Xnapper** ([producthunt](https://www.producthunt.com/products/xnapper), [setapp](https://setapp.com/apps/xnapper)) — The "beautifier" category leader: mesh-gradient backgrounds, padding + inset control, rounded corners, drop shadows, **auto-balance** (removes unbalanced whitespace so the subject is perfectly centered), personal **watermark**, **automatic detection + redaction of sensitive info** (e.g. email addresses), multiple named presets, social-media size optimization. This whole pipeline is one screen: capture → instantly beautified → copy/share.

**Shots.so / device-mockup tools** ([shots.so](https://shots.so/)) — Device frames (iPhone/iPad/MacBook/Android) and **browser-window frames** around screenshots, gradient/image backgrounds, noise/VHS/glitch effects, social-media canvas presets, animated mockup exports. The stand-out transferable idea: wrap a captured window in a fake browser chrome or device bezel before sharing.

**Snagit** ([features](https://www.techsmith.com/snagit/features/)) — **Capture presets/profiles** (one click bundles mode + destination + effects); **delayed/timed capture** for menus and tooltips; **panoramic capture** (user scrolls manually while frames are stitched — a robust fallback when auto-scroll detection fails); **Simplify tool** (replaces real UI with abstract shapes to sanitize screenshots); **Templates** (combine several screenshots into one step-by-step tutorial image); capture the cursor optionally; stamp libraries.

**Monosnap / Greenshot / ksnip** — Monosnap: configurable cloud destinations (Dropbox, Drive, FTP/SFTP, S3) straight from capture. Greenshot: **multi-destination output on capture** (file + clipboard + printer + email + upload simultaneously). ksnip: tabbed editor (multiple screenshots open at once), stickers, image effects (drop shadow, grayscale, invert, border), custom upload scripts.

**Xnip** ([xnipapp.com](https://xnipapp.com/)) — **Multi-window capture** (select several windows and capture them together as one image); scrolling capture via continuous capture of the selected area + overlap matching; **physical-unit size indicator** (shows real-world cm/inch dimensions); window shadow effect toggle.

**PixelSnap 2** ([pixelsnap.com](https://pixelsnap.com/)) — Pure measurement overlay: hotkey draws measurement guides over the whole screen; drag between any two points for pixel distances; **drag an area and it snaps to detected object edges** showing dimensions; persistent snappable alignment guides; multiple simultaneous measurements; export measurements as an annotated screenshot; Retina-scale-aware real dimensions.

**macOS Screenshot.app** — Features ClipShot lacks: 5/10-second **timer**, **Remember Last Selection**, **Show Mouse Pointer** toggle, and a save-destination picker (Desktop/Documents/Clipboard/Mail/Messages/Preview) baked into the capture toolbar.

**Textify (Windows)** ([github](https://github.com/m417z/Textify)) — Grab text from dialogs/controls that can't be selected. The transferable idea is a *hover-and-grab* interaction (point at a UI element, get its text instantly) rather than draw-a-region.

**LICEcap / Peek / Kap + native OSS recorders** ([Kap](https://getkap.co/), [Capso](https://github.com/lzhgus/Capso), [macshot](https://github.com/sw33tLie/macshot), [ScrollSnap](https://github.com/Brkgng/ScrollSnap)) — LICEcap's enduring idea: a **resizable pass-through frame** — whatever is inside the frame gets recorded, movable mid-recording. Kap: record real video first, convert to GIF afterwards (much better UX than encoding GIF live), plugin-based export. Capso (Swift 6/SwiftUI, explicitly a native CleanShot clone): recording editor with zoom suggestions, cursor smoothing, background styling, MP4/GIF export — reusable SPM packages (`CaptureKit`, `AnnotationKit`). macshot (native Swift): scroll capture that auto-detects vertical/horizontal scrolling and **stitches frames using Apple Vision**, plus auto-redact-PII, OCR + translate, beautify. ScrollSnap: dedicated `StitchingManager` for ScreenCaptureKit-based scroll stitching.

**Community threads** ([HN: Shottr](https://news.ycombinator.com/item?id=31773863), [HN: CleanShot](https://news.ycombinator.com/item?id=33326757)) — Recurring user-loved features: pixel measurement ("CleanShot lacks a screen ruler and designers really miss it"), scrolling capture, OCR quality, *speed of getting a shareable link*, and freeze-screen + zoomed crosshair for pixel-perfect selection.

## Prioritized Recommendations

### Group A — High value / low effort

1. **Self-timer capture (3/5/10s countdown)** — capture menus, tooltips, hover states. *Source: macOS Screenshot.app, CleanShot X, Snagit.* Impl: `DispatchSourceTimer` + a non-activating `NSPanel` countdown HUD, then run the existing capture path. No new permissions.
2. **Repeat-last-area capture ("Remember Last Selection")** — persist the last region `CGRect` (per display, in `UserDefaults`), pre-seed the crosshair overlay with it, plus a dedicated hotkey that recaptures instantly without showing the overlay. *Source: Shottr "Repeat Area", macOS Screenshot.app.* Impl: trivial state on the existing overlay; store `CGDirectDisplayID` alongside the rect for multi-monitor correctness.
3. **Freeze screen + magnifier loupe during region selection** — grab a full-display image with `SCScreenshotManager.captureImage` *first*, display it in the overlay window, and select on the frozen frame; add a zoomed loupe near the crosshair showing pixel coordinates + color. *Source: CleanShot X advanced modes; repeatedly praised on HN.* Impl: overlay window + Screen Recording permission already exist; loupe is a `CALayer` with `magnificationFilter = .nearest` sampling the frozen `CGImage`.
4. **Aspect-ratio lock + exact-size selection + arrow-key nudge** — hold Shift for ratio presets (16:9, 4:3, 1:1), type WxH, nudge/resize selection with arrow keys before confirming. *Source: CleanShot All-in-One, Shottr.* Impl: pure math in the existing crosshair overlay.
5. **Show/hide mouse pointer option** — *Source: macOS Screenshot.app, Snagit.* Impl: one flag — `SCStreamConfiguration.showsCursor`. Zero extra work beyond a Settings toggle.
6. **Window capture: shadow toggle + transparent background** — capture the window with alpha; transparent PNG, shadow on/off, or a backdrop. *Source: CleanShot X, Xnip.* Impl: ScreenCaptureKit window-filter capture; `SCStreamConfiguration.ignoreShadowsSingleWindow` (macOS 14+) and `backgroundColor = .clear`.
7. **QR code detect/decode on capture** — if a capture contains a QR code, offer "Copy link" in the thumbnail overlay. *Source: Shottr.* Impl: `VNDetectBarcodesRequest` alongside the existing Vision OCR request — ~30 lines.
8. **WCAG/APCA contrast checker** — extend the existing color picker: pick two colors, show contrast ratio + AA/AAA pass. *Source: Shottr.* Impl: pure math on colors already sampled.
9. **Before/after two-frame GIF** — take two captures of the same region (pairs with Repeat Area) and export a looping 2-frame GIF. *Source: Shottr.* Impl: `CGImageDestination` GIF with per-frame delay. No recording pipeline needed.

### Group B — High value / higher effort

1. **Background/beautify pipeline ("make it social-ready")** — padding, gradient/mesh backgrounds, rounded corners, drop shadow, inset, auto-balance centering, optional watermark, named presets, social canvas sizes. Biggest gap vs. the market (Xnapper's entire business, CleanShot's Background tool, Shottr's Backdrop). Impl: Core Graphics compositing; SwiftUI live-preview panel; a tab/mode of the existing annotation editor. Auto-balance = trim uniform-color margins (scanline variance) then center.
2. **Sensitive-data auto-redaction** — detect emails, phone numbers, API-key-shaped strings in a capture; one-click pixelate all. *Source: Xnapper, macshot.* Impl: existing `VNRecognizeTextRequest` output → `NSDataDetector` (+ regexes), map `boundingBox` to image coords, reuse the pixelate annotation. No new permissions.
3. **Pixel ruler / on-screen measurement with edge snapping** — hover shows distances to nearest detected edges; drag measures between points; imprint onto screenshot. *Source: Shottr, PixelSnap 2 — the #1 "designers miss this" feature.* Impl: freeze-frame the display, per-scanline luminance-delta edge detection, guides in the overlay window; physical units via `CGDisplayScreenSize`.
4. **Scrolling capture** — proven OSS approaches: (a) [ScrollSnap](https://github.com/Brkgng/ScrollSnap) — `StitchingManager` + ScreenCaptureKit, closest to ClipShot's architecture; (b) [macshot](https://github.com/sw33tLie/macshot) — Vision translational registration (`VNTranslationalImageRegistrationRequest`), auto-detects scroll direction; (c) Snagit-style manual panoramic mode as robust fallback. Auto-scroll via `CGEvent(scrollWheelEvent2Source:)`; crop sticky headers by detecting the identical top strip before stitching.
5. **GIF/MP4 recording** — `SCStream` → `AVAssetWriter` MP4 first, then optional GIF conversion (Kap's model — live GIF encoding is a dead end). GIF: `AVAssetImageGenerator` at 10–15 fps → `CGImageDestination`. Reference: [Capso](https://github.com/lzhgus/Capso). Click highlights via global mouse-down monitor (no extra permission); keystroke overlay needs Input Monitoring — gate it. System audio free via `capturesAudio = true`; mic needs Microphone permission. LICEcap-style movable frame: display capture cropped to a draggable pass-through panel, updated via `SCStream.updateConfiguration`.
6. **Capture presets/profiles + multi-destination output** — named presets bundling mode + destinations + format + filename pattern, per-preset hotkeys. *Source: Snagit, Greenshot.* Impl: `Codable` preset model through a single capture pipeline; mostly refactoring.
7. **All-in-One capture mode** — one hotkey opens the selection overlay with a mode strip (region/window/fullscreen/OCR/record). *Source: CleanShot X.* Impl: UI unification of existing paths.

### Group C — Nice-to-have

1. **Device/browser frames** — fake Safari chrome or device bezels (Shots.so, Xnapper); build after B1.
2. **Multi-window combined capture** — `SCContentFilter(display:including:)` with an array of `SCWindow`s (Xnip).
3. **Spotlight/highlight + true blur + ellipse/line/freehand tools** — annotation parity with CleanShot; blur must be downscale-then-upscale so text isn't recoverable.
4. **Snagit-style Simplify tool** — `VNDetectRectanglesRequest` + flat fills; hard to make good, low priority.
5. **Combine screenshots / tutorial templates** — multiple captures into one laid-out image via `ImageRenderer`.
6. **Cloud/S3 upload with instant link** — user-supplied S3/custom endpoint first; avoid running a service.
7. **URL-scheme / Shortcuts automation** (`clipshot://capture-area?preset=x`) — `NSAppleEventManager` + App Intents.
8. **Hide desktop clutter** — exclude desktop-icon windows via `SCContentFilter(display:excludingWindows:)`.
9. **Editable project format** — save annotation layers (`Codable` + original image) for later re-editing.
10. **Auto-DND during recording** — no public Focus API; Shortcuts invocation is the only sanctioned route. Best-effort only.

**Permission summary:** everything in A/B except keystroke overlay reuses the existing Screen Recording permission; keystroke display → Input Monitoring, mic → Microphone, webcam → Camera, hover-text-grab → Accessibility. Isolate each behind its own opt-in.
