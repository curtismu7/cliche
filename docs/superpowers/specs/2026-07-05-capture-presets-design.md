# Capture Presets (B6) — Design

Date: 2026-07-05
Status: Approved as part of "do them" batch.

## Goal

Named capture profiles bundling **mode + image format + clipboard behavior
+ destination folder + filename pattern**, runnable in one click from a
presets menu in the capture bar. Research item **B6** (the last open item
in Group B).

## Scope decisions

- v1 has **no per-preset global hotkeys**: `HotkeyAction` is a fixed enum
  and dynamic Carbon registration is a separate project. Presets run from
  the menu.
- Filename tokens: `%DATE%` (yyyy-MM-dd) and `%TIME%` (HH.mm.ss). Default
  pattern reproduces today's naming: `Cliché %DATE% at %TIME%`.
- Destination nil = Desktop (today's behavior).

## Architecture

1. **`CapturePreset` (ClicheKit, Codable)** — `id, name, mode
   (region/window/fullScreen via existing CaptureMode — made Codable),
   format (AppSettings.ImageFormat), copyToClipboard, destinationPath:
   String? (nil = Desktop), filenamePattern`.
2. **`CaptureNaming` (pure)** — `outputURL(directory: URL, pattern:
   String, fileExtension: String, date: Date) -> URL`, token expansion,
   used by both the preset path and the existing default path (single
   source of naming truth).
3. **Persistence** — `AppSettings.capturePresets: [CapturePreset]` via the
   existing JSON encode/decode helpers.
4. **Delivery** — `CaptureDelivery.deliver` gains optional
   `directory`/`pattern` args (defaults keep today's behavior);
   `CaptureService.capture` gains an optional explicit `outputURL` for the
   CLI window path.
5. **AppDelegate** — `runPreset(_:)` routes preset.mode through the
   existing capture flows with the preset's delivery settings threaded
   through (engine paths + CLI window path).
6. **UI** — a "presets" menu button in the capture bar second row: one
   entry per preset (runs it), "New Preset…" (sheet: name, mode, format,
   clipboard toggle, folder picker, pattern field), and a Delete submenu.

## Testing

- `CaptureNaming` token expansion (both tokens, no tokens, custom text).
- `CapturePreset` JSON round-trip; `capturePresets` persistence.
- Default-path regression: naming for the non-preset path unchanged.
- Manual: run a preset with a custom folder + pattern; file lands there.
