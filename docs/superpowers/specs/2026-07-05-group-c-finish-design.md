# Group C Finish (C3, C9, C2, C5) — Design

Date: 2026-07-05
Status: Approved ("practical four"), ready for implementation
Skipped by decision: C4 Simplify, C10 auto-DND (research doc deprioritizes), C6 cloud upload.

Build order: C3 → C9 → C2 → C5 (C9 persists C3's model; C2/C5 independent).

## C3 — Annotation upgrades

New tools in the editor: **ellipse**, **line**, **freehand**, **highlight**
(translucent marker fill), and **true blur** (unrecoverable gaussian —
downscale-then-upscale, per the research doc; the existing pixelate stays).

- `Annotation.Kind` gains `ellipse`, `line`, `freehand(points: [CGPoint])`,
  `highlight`, `gaussianBlur`. `Annotation` (and `Kind`) become **Codable**
  (custom coding with a `type` discriminator; also required by C9).
- `AnnotationRenderer` draws each: stroked ellipse/line in the brand red;
  freehand = round-capped path through the points; highlight = 35%-alpha
  yellow fill; gaussian blur = crop → scale to 1/8 → scale back up with
  interpolation (content unrecoverable).
- Editor: five new `EditorTool` cases with SF Symbols; ellipse/line/
  highlight/blur drag like rectangle; freehand accumulates points during
  the drag.
- Tests: Codable round-trip for every kind incl. freehand points; renderer
  pixel checks (ellipse edge stroked, highlight tints, gaussian blur
  destroys a checkerboard's variance).

## C9 — Editable project format

Annotations survive Save so a capture can be re-edited non-destructively.

- `ProjectStore` (ClicheKit): sidecar per capture under
  `~/Library/Application Support/Cliche/Projects/<capture-filename>/` —
  `original.png` (the pre-annotation base, written once) +
  `project.json` (`annotations: [Annotation]`, `config: BeautifyConfig`).
- Editor `open`: if a project exists for the file, load the original base
  + saved layers instead of the flattened PNG. `Save`: write the flattened
  export to the capture path as today **and** persist the project.
- Deleting a capture in the Captures tab removes its project folder.
- Tests: save → load round-trips annotations + config; original base
  bytes stable across repeated saves; missing project → nil.

## C2 — Multi-window combined capture

Capture several chosen windows into one image, everything else excluded.

- `WindowPickerPanel` (Cliche): floating panel listing on-screen windows
  (layer 0, ≥ 80×80 pt, not Cliché's own) with app name + title and
  checkboxes; Capture button enabled when ≥ 1 selected.
- Engine: `ScreenshotEngine.captureWindows(_ windows: [SCWindow], displayID:scale:) -> CGImage`
  builds `SCContentFilter(display:including:)`, captures the display, and
  crops to the pixel union of the windows' frames (+ small margin).
- Pure helper for tests: `unionPixelRect(of frames: [CGRect], scale:, in display:) -> CGRect`.
- Entry: "windows" button in the capture bar's second row. Output goes
  through the normal `deliver` path (file, clipboard, overlay, history).

## C5 — Combine screenshots

Stitch several captures into one laid-out image.

- `Combiner` (ClicheKit, pure): `combine(_ images: [CGImage], layout:, gapFraction:, background: RGBAColor) -> CGImage?`
  with `Layout = .horizontal | .vertical | .grid`. Horizontal scales all
  to the min height; vertical to the min width; grid uses ⌈√n⌉ columns
  with uniform cells (max scaled dims), row-major, top-left first.
- UI: "Combine…" button in the Captures tab opens a sheet: checkboxes on
  the most recent 8 captures (pick 2–6), layout picker, gap toggle →
  result saved as a new capture (file + clipboard + history + overlay).
- Tests: output dimensions for known inputs in all three layouts;
  single-image and empty inputs return nil.

## Shared constraints

- Swift 6 (v5 mode), macOS 14+, no new dependencies; model/render in
  ClicheKit, UI in Cliche; `cliche-selftest` `expect` blocks.
- Existing behavior unchanged where a feature is unused (no project →
  editor behaves exactly as today; combine/multi-window are new buttons).
- README: one bullet per feature.
