# Browser/Device Frames (C1) — Design

Date: 2026-07-05
Status: Approved, ready for planning

## Goal

Wrap a capture in presentation chrome — Safari-style browser bar (light or
dark, with editable URL text), a plain macOS window bar, or a generic
phone/tablet hardware bezel — as part of the existing beautify pipeline.
Research item **C1** in `docs/CAPTURE-RESEARCH.md`, sequenced after B1.

## Decisions (from brainstorm)

- Styles: browser light, browser dark, macOS window bar, phone bezel,
  tablet bezel — plus none. All drawn **procedurally** in Core Graphics;
  no image assets, no pixel-exact hardware replicas.
- Browser URL text is user-editable in the inspector; empty renders a
  blank pill.
- Frames are part of `BeautifyConfig`, so presets capture them and the
  live editor preview shows them.

## Architecture

### 1. Model (ClicheKit)

```swift
public enum FrameStyle: String, Codable, CaseIterable {
    case none, browserLight, browserDark, macWindow, phone, tablet
    public var label: String   // "None", "Browser · Light", … "Tablet"
    public var isBrowser: Bool // browserLight/browserDark
}
```

`BeautifyConfig` gains two fields with **backward-compatible decoding**
(existing users have persisted configs without these keys):

```swift
public var frame: FrameStyle   // default .none
public var frameURL: String    // default ""
```

Custom `init(from:)` uses `decodeIfPresent` with those defaults; all other
fields decode as before. Encoding always writes both keys.

### 2. Rendering (ClicheKit)

New `FrameRenderer` enum, separate file, so `BeautifyRenderer` stays
focused:

```swift
public enum FrameRenderer {
    /// Extra space the chrome needs around the screenshot, in pixels,
    /// given the screenshot's min dimension.
    public static func chromeInsets(_ style: FrameStyle, minDimension: CGFloat) -> NSEdgeInsets
    /// Draws the chrome around `screenshotRect` (which already excludes
    /// the insets). `plateRect` = screenshotRect + insets.
    public static func draw(_ style: FrameStyle, urlText: String,
                            plateRect: CGRect, screenshotRect: CGRect,
                            cornerRadius: CGFloat, in ctx: CGContext)
}
```

Chrome metrics (fractions of the screenshot min dimension):

- `browserLight`/`browserDark`/`macWindow`: top inset ≈ 0.055 (bar),
  0 elsewhere. Bar background light gray / dark gray / window gray;
  three traffic-light dots; browser styles add a rounded URL pill
  (centered, ~60% width) with `frameURL` in system font, mid-gray.
- `phone`: uniform bezel ≈ 0.045 all around, near-black fill, a small
  camera dot centered in the top bezel.
- `tablet`: uniform bezel ≈ 0.06, near-black, camera dot.
- `none`: zero insets, draws nothing.

Integration into `BeautifyRenderer.render`/`layout`:

- `layout` adds the chrome insets between the (optional) inset matte and
  the screenshot: plate size = screenshot + chrome insets (+ inset matte),
  so `screenshotRect` shifts inside the plate. Because the annotation
  editor's gesture mapping already routes through `layout`, clicks keep
  landing on the screenshot with a frame active — no editor changes needed
  beyond the inspector section.
- `render` draws: gradient → shadow plate → inset matte → **frame chrome**
  → screenshot (clipped to its own rounded corners only when frameless;
  with a frame, the outer plate keeps the corner rounding and the
  screenshot is clipped square inside the chrome).
- A frame with an identity background still renders (frame-only export is
  valid): if `frame != .none`, the config is no longer identity.
  `isIdentity` becomes `background.isEmpty && frame == .none`.

### 3. Inspector (Cliche)

`BeautifyInspector` gains a **FRAME STYLE** group between BACKGROUND and
FRAME: a `Picker` over `FrameStyle.allCases` plus, when
`config.frame.isBrowser`, a `TextField("example.com", text: $config.frameURL)`.
Presets and `lastBeautifyConfig` persistence pick the fields up for free.

### 4. Testing (cliche-selftest)

- `FrameStyle` labels unique/non-empty; raw-value Codable round-trip.
- Legacy JSON: a `BeautifyConfig` encoded **without** `frame`/`frameURL`
  keys decodes with `.none`/`""` (hand-built JSON literal).
- `chromeInsets`: top-only for bar styles, uniform for bezels, zero for none.
- `layout` with a browser frame yields a taller output than the same
  config frameless, by exactly the top inset.
- `render` with `browserLight` on a solid image: output dimensions match
  layout, and a sampled pixel in the bar region differs from the
  screenshot color.
- `isIdentity` false when only a frame is set.
- Manual: pick each style in the editor, check live preview, URL text,
  annotations landing on content, Save output.

## Non-Goals

- Pixel-exact device artwork, screen-corner masking to bezel radius,
  or per-device aspect enforcement — the bezel wraps whatever was
  captured.
- Frame-specific hotkeys or per-frame padding controls.

## Success Criteria

- All five styles render in the live preview and exported PNG.
- Editable URL appears in browser frames.
- Old persisted configs and presets keep decoding (no reset for users).
- Selftest green; existing beautify tests unaffected.
