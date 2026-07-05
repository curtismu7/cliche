# Beautify Pipeline (B1) — Design

Date: 2026-07-05
Status: Approved, ready for planning

## Goal

Turn Cliché's minimal fixed-preset backdrop feature into the full "social-ready"
beautify pipeline described as **B1** in `docs/CAPTURE-RESEARCH.md`: adjustable
padding, editable linear-gradient backgrounds, rounded corners, drop shadow,
optional inset matte, auto-balance centering, named user presets, and fixed
social canvas sizes — all previewed live in the annotation editor.

## Current State

`Sources/ClicheKit/BeautifyRenderer.swift` exposes a `BeautifyStyle` enum with
`none` + 5 fixed gradients. `BeautifyRenderer.apply(_:to:)` composites the image
onto a padded gradient plate with hardcoded padding (9% of the min dimension),
corner radius, and shadow. It is wired into `AnnotationEditorView` as a single
dropdown (`Sources/Cliche/AnnotationEditor.swift`). Two gaps drive this work:

1. Everything is fixed — no adjustable padding/corner/shadow, one gradient set,
   no presets, no output sizing.
2. The editor canvas previews the *flattened annotated* image but **not** the
   backdrop, so the user picks a backdrop blind and only sees it after Copy/Save.

## Non-Goals

- Mesh gradients, solid-color-only, image/wallpaper backgrounds (explicitly out;
  backgrounds are editable linear gradients only — a solid is a gradient with
  equal stops).
- Device/browser frames (Group C).
- A new hotkey or standalone window. Beautify stays a feature of the annotation
  editor, reachable everywhere the editor already opens (Captures tab,
  post-capture overlay).

## Architecture

Follows the existing `Annotation` / `AnnotationRenderer` split: a `Codable`
value-type config plus a stateless pure renderer.

### 1. Data model — `BeautifyConfig` (ClicheKit)

Replaces `BeautifyStyle`. A `Codable`, `Equatable` struct:

```
struct BeautifyConfig: Codable, Equatable {
    var background: Gradient      // stops + angle; the whole background
    var padding: CGFloat          // outer gradient margin, fraction of screenshot min-dimension
    var inset: InsetFrame?        // optional colored matte around the screenshot; nil = off
    var cornerRadius: CGFloat     // screenshot corner rounding, fraction of min-dimension
    var shadow: Shadow            // blur, yOffsetFraction, opacity (opacity 0 = no shadow)
    var canvas: CanvasSize        // .free or a fixed social target
    var autoBalance: Bool         // trim uniform screenshot margins before centering

    static let identity: BeautifyConfig   // no background → returns image unchanged
}

struct Gradient: Codable, Equatable {
    var stops: [Stop]             // Stop { color: RGBAColor; location: CGFloat }
    var angleDegrees: CGFloat
    var isEmpty: Bool             // no stops / fully transparent → identity render
}

struct RGBAColor: Codable, Equatable { var r, g, b, a: CGFloat }   // sRGB, JSON-friendly
struct InsetFrame: Codable, Equatable { var width: CGFloat; var color: RGBAColor }
struct Shadow: Codable, Equatable { var blur, yOffsetFraction, opacity: CGFloat }

enum CanvasSize: Codable, Equatable {
    case free
    case fixed(width: Int, height: Int, label: String)
    static let socialPresets: [CanvasSize]   // see §5
}
```

Colors are stored as sRGB component structs (not `CGColor`/`NSColor`) so configs
round-trip through JSON cleanly.

### 2. Renderer — `BeautifyRenderer` (ClicheKit)

Two pure functions; `layout` is the single source of geometric truth so the UI
and the renderer agree on where the screenshot lands.

```
struct BeautifyLayout {
    var outputSize: CGSize        // final pixel dimensions
    var screenshotRect: CGRect    // where the (post-auto-balance) screenshot is drawn, in output px
    var sourceCrop: CGRect        // region of the input drawn (full image unless auto-balanced)
}

static func layout(_ config: BeautifyConfig, imageSize: CGSize) -> BeautifyLayout
static func render(_ config: BeautifyConfig, to image: CGImage) -> CGImage?
```

`render` pipeline:
1. If `config` is identity (empty gradient), return the image unchanged.
2. Compute `sourceCrop` — full image, or the auto-balance trimmed rect when
   `autoBalance` is on (trim uniform-color margins via per-scanline variance).
3. From `layout`, allocate the output context at `outputSize`.
4. Draw the linear gradient across the whole output at `background.angleDegrees`.
5. Draw the rounded shadow plate (opaque) under `screenshotRect` when
   `shadow.opacity > 0`.
6. If `inset != nil`, fill the matte band around the screenshot inside the
   rounded corners.
7. Clip to the rounded rect and draw the cropped screenshot into `screenshotRect`.

Geometry:
- **`.free` canvas:** `outputSize = screenshotCrop + 2·padding (+ inset width)`.
  Screenshot centered. Matches today's behavior when the config mirrors a preset.
- **Fixed canvas:** `outputSize` is exactly the target. The padded screenshot
  (crop + padding + inset) is uniformly scaled to fit inside and centered
  (fit-and-center). `autoBalance` trims first so centering reads optically.

Padding, cornerRadius, shadow blur/offset are all expressed as fractions of the
screenshot's min dimension (as the current code does) so results are
resolution-independent.

### 3. Editor UI (Cliche)

`AnnotationEditorView` gains a collapsible right-hand **Beautify inspector**
(`BeautifyInspector` view). Toolbar keeps annotation tools; the old backdrop
dropdown is removed in favor of the inspector.

Inspector controls:
- Preset menu: built-ins + user presets, **Save as preset…**, delete user preset.
- Background: gradient stop editor (add/remove/recolor stops) + angle slider.
- Sliders: padding, inset width (0 = off) + inset color well, corner radius,
  shadow blur / offset / opacity.
- Canvas-size menu (`.free` + social presets).
- Auto-balance toggle.

The canvas renders the **composited `exported` image live** (annotations +
beautify). Gesture→pixel mapping routes through `BeautifyRenderer.layout`:
a view point maps to output pixels, then into `screenshotRect` → `sourceCrop`
image pixels, so annotations always land on the screenshot, never the padding.
When the config is identity, `layout` is the identity transform and annotation
behavior is unchanged from today.

`exported` remains `BeautifyRenderer.render(config, to: flattened)`; order is
base → annotations flattened → beautify composite (unchanged pipeline shape).

### 4. Presets & persistence (ClicheKit `AppSettings`)

- `beautifyPresets: [NamedBeautifyConfig]` — user presets, persisted as JSON in
  UserDefaults (same idiom as existing keys).
- `lastBeautifyConfig: BeautifyConfig` — the editor opens with this; persisted.
- Built-in presets: a static array re-expressing the current 5 gradients
  (Indigo/Sunset/Ocean/Forest/Slate) as full configs, plus `identity` ("None"),
  so nothing visually regresses. Built-ins are selectable and tweakable live but
  not editable in place; **Save as preset…** captures the current config under a
  user-chosen name. User presets are deletable.

### 5. Canvas sizes

`CanvasSize.socialPresets` — `.free` plus fixed targets:
- X / Twitter — 1600×900
- Square — 1080×1080
- Instagram Portrait — 1080×1350
- (final list confirmed in the plan; the enum makes adding sizes trivial)

Fixed sizes produce exactly those output dimensions via fit-and-center (§2).

### 6. Testing

Extend the existing `cliche-selftest` harness (Sources/cliche-selftest/main.swift;
not XCTest), matching current style:
- identity config returns the image unchanged (dimensions + pixels).
- padding on `.free` yields the expected larger dimensions.
- a fixed canvas yields exactly the target `outputSize`.
- `autoBalance` trims a synthetic bordered image to the expected `sourceCrop`.
- `BeautifyConfig` JSON encode→decode round-trips to an equal value.
- `layout` maps a known view/output point back to the correct screenshot pixel.

Manual: build via `make`/`swift run`, open the editor on a real capture, confirm
live preview and that annotations land correctly with a backdrop active, before
claiming done.

## Migration

`BeautifyStyle` is removed. Its only non-test consumers are `AnnotationEditor`
(re-worked here) and the self-test (rewritten). The persisted
`lastBeautifyConfig` defaults to `identity` when absent, so existing users see
no change until they open the inspector.

## Success Criteria

- Editor shows a live composited preview; backdrop is never picked blind.
- All controls (padding, inset, corner, shadow, gradient stops+angle, canvas
  size, auto-balance) affect the preview and the exported PNG.
- Built-in presets reproduce today's 5 gradients; user can save/load/delete
  named presets that survive a relaunch.
- Fixed canvas sizes export exactly the target dimensions, fit-and-centered.
- Annotations map correctly onto the screenshot with any backdrop active.
- `cliche-selftest` passes, including the new beautify assertions.
