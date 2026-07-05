<p align="center">
  <img src="Assets/icon-200.png" width="128" alt="Cliché icon">
</p>

<h1 align="center">Cliché</h1>

<p align="center"><b>Clipboard history + screen capture for macOS, in one menu bar app.</b><br>
Think Maccy and CleanShot had a French child. Free, open source, 100% local — no accounts, no network, no telemetry.</p>

---

## Install

**Option 1 — download the app** (no developer tools needed):

1. Grab `Cliche-x.x.x.zip` from the [latest release](https://github.com/curtismu7/cliche/releases/latest).
2. Unzip it and double-click **`Install Cliché.command`**.
   - If macOS says it "cannot be opened because it is from an unidentified developer," right-click the file → **Open** → **Open**. This is normal for apps shared outside the App Store (Cliché isn't notarized — see [Signing](#signing)).
3. Done — Cliché appears in your menu bar and can start at login.

**Option 2 — build from source** (macOS 14+, Xcode Command Line Tools):

```sh
git clone https://github.com/curtismu7/cliche.git
cd cliche
make install    # builds, installs to ~/Applications, launches
```

**Permissions** (macOS asks once each): *Screen Recording* on your first screenshot, and *Accessibility* only if you use direct paste. Everything else works with no permissions at all.

## What it does

### 📋 Clipboard history
- Remembers your last **150 text snippets and 50 images** (both configurable in Settings) from anywhere on your Mac; history survives restarts.
- **Fuzzy search** — the panel opens with search focused; `hw` finds "hello world".
- **Keyboard-first** — `↑↓` select, `↩` copies, `⌘1–9` grab the first nine, `⌘⌫` deletes, `⌥P` pins, `⌥U` unpins.
- **Paste directly into the app you were using** — `⌥↩` or ⌥-click types the item where your cursor was.
- **Pin** anything to keep it forever — pins live in their own section at the top, above a "Recent" separator, with an **Unpin All** button; pinned items never count against history limits. Plus **edit text clips in place** and **preview** long text or images in a floating window with copy/pin/edit corners.
- **Images in a horizontal strip**, previewable, pinnable, annotatable.
- **Snippets** — reusable templates with `%DATE%`, `%TIME%`, `%CLIPBOARD%` variables.
- **Privacy built in** — anything copied from password managers (concealed/transient pasteboard types) is never recorded, with a user-editable ignore list.
- **⌥1 floating list** — Maccy-style popup at your cursor from anywhere.

### 📷 Screen capture
- **Region capture on a frozen screen** with a magnifier loupe, live pixel-size label, and Shift-to-square — plus window, full-screen, and timed (3/5/10 s) capture.
- **Repeat last region** with one hotkey — perfect for iterating on the same area.
- **OCR** — select any region, the text in it lands on your clipboard (on-device Vision).
- **Scrolling capture** — select a region, scroll the content, Cliché stitches one tall image.
- **Screen recording** — region to MP4, with optional GIF export.
- **Pixel ruler** — hover snaps to UI element edges and shows dimensions; drag measures; click copies.
- **Annotation editor** — arrows, boxes, text, pixelate, counter badges, **one-click auto-redaction** of emails/links/phone numbers/API keys, and **gradient backdrops** for social-ready shots.
- **Quick Access Overlay** — post-capture thumbnail you can drag into Slack/Mail or click to annotate; QR codes in captures get a "copy link" button.
- **Color picker** with hex copy and a WCAG contrast checker; before/after GIFs from any two captures.
- Screenshots land on the **Desktop + clipboard + Captures tab** (format and clipboard behavior configurable).

## Default shortcuts (all customizable in Settings)

| Shortcut | Action |
|---|---|
| `⌃⌥⌘C` | Open the clipboard panel |
| `⌥1` | Floating clipboard list at the cursor |
| `⌃⌥⌘4` | Capture a region |
| `⌃⌥⌘R` | Repeat the last region |
| `⌃⌥⌘5` | Capture a window |
| `⌃⌥⌘6` | Copy text from screen (OCR) |

The **?** button in the panel lists every in-panel shortcut; the **gear** opens Settings (menu bar style, history limits, image format, timer, hotkeys, launch at login, ignore rules).

## Signing

Cliché is ad-hoc signed — there's no Apple Developer certificate behind it, which is why Gatekeeper asks for a right-click → Open on first launch. The installer clears the quarantine flag for you. Build from source and there's no prompt at all.

## Uninstall

Quit Cliché from the panel, then delete `~/Applications/Cliche.app` and `~/Library/Application Support/Cliche/`, and remove it from System Settings → Login Items if enabled.

## Development

- `Sources/ClicheKit` — library: history store, clipboard monitor, screenshot engine, recorder, stitcher, OCR, annotation renderer
- `Sources/Cliche` — the menu bar app (AppKit shell + SwiftUI panels)
- `Sources/cliche-selftest` — assertion-based tests: `make test` (Command Line Tools ship no XCTest)
- `make install` — build + reinstall locally · `make dist` — shareable zip · `make release` — tag, push, and publish a GitHub release
- `docs/` — design spec, roadmap, and the feature research that drove the app

## License

[MIT](LICENSE)
