import SwiftUI

/// Shortcuts & help sheet, opened from the ? button in the panel footer.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Cliché Shortcuts & Help")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    section("Global Hotkeys (work anywhere)", rows: [
                        ("⌃⌥⌘C", "Open / close this panel"),
                        ("⌃⌥⌘4", "Capture a region"),
                        ("⌃⌥⌘R", "Repeat the last region capture (no UI)"),
                        ("⌃⌥⌘5", "Capture a window"),
                        ("⌃⌥⌘6", "Copy text from screen (OCR)"),
                    ])
                    section("Region Selection", rows: [
                        ("frozen screen", "The display freezes while you select; a loupe magnifies pixels at the cursor"),
                        ("⇧ while dragging", "Lock the selection to a square"),
                        ("size label", "Live pixel dimensions of the selection"),
                        ("esc", "Cancel"),
                    ])
                    section("Clipboard Tab", rows: [
                        ("type", "Search history (fuzzy — \"hw\" finds \"hello world\")"),
                        ("↑ / ↓", "Move selection"),
                        ("↩", "Copy selection, close panel"),
                        ("⌥↩ / ⌥-click", "Paste straight into the previous app"),
                        ("⌘1 – ⌘9", "Copy the numbered item"),
                        ("⌘⌫", "Delete selection"),
                        ("⌘P", "Pin / unpin selection"),
                        ("hover", "Row buttons: paste ↵, edit ✏️ (text), float (image), pin, delete"),
                    ])
                    section("Captures Tab", rows: [
                        ("click thumbnail overlay", "After a capture: click to annotate, or drag it into another app"),
                        ("hover a capture", "Share, copy, annotate ✏️, float, show in Finder, trash"),
                    ])
                    section("Color Picker", rows: [
                        ("eyedropper button", "Magnifier loupe — click any pixel; its hex code (#3A7BD5) is copied"),
                        ("pick twice", "Consecutive picks show the WCAG contrast ratio between the two colors"),
                    ])
                    section("More Capture Tools", rows: [
                        ("timer", "Settings → capture timer (3/5/10 s countdown) for menus and hover states"),
                        ("QR codes", "If a capture contains a QR code, the thumbnail overlay offers Copy Link"),
                        ("film button", "On a capture: before/after GIF with the previous capture"),
                        ("cursor / shadow", "Settings toggles: show mouse pointer, keep window shadow"),
                    ])
                    section("Annotation Editor", rows: [
                        ("drag", "Arrow, rectangle, or pixelate (by tool)"),
                        ("click", "Place text label or numbered counter"),
                        ("⌘Z", "Undo"),
                        ("⇧⌘C", "Copy annotated image"),
                        ("↩", "Save (overwrites the capture file)"),
                    ])
                    section("Snippets Tab", rows: [
                        ("click", "Copy rendered snippet"),
                        ("⌥-click", "Paste it into the previous app"),
                        ("%DATE% %TIME% %CLIPBOARD%", "Variables replaced at copy time"),
                    ])
                    section("Good to Know", rows: [
                        ("Screenshots", "Saved to the Desktop + clipboard + Captures tab (format and clipboard behavior: gear → Settings)"),
                        ("History", "Keeps 150 texts and 50 images; pinned items are never evicted"),
                        ("Privacy", "Password-manager copies are never recorded (gear → Edit Ignore Rules…)"),
                        ("Permissions", "Screen Recording: needed for captures. Accessibility: only for direct paste"),
                    ])
                }
                .padding(12)
            }
        }
        .frame(width: 380, height: 460)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private func section(_ title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            ForEach(rows, id: \.0) { key, description in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(key)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(0.08)))
                        .frame(minWidth: 88, alignment: .leading)
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
