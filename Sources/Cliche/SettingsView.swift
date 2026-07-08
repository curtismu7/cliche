import AppKit
import ClicheKit
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let ignoreRulesURL: URL
    var historyStore: HistoryStore? = nil

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var importMessage: String?
    @State private var screenRecordingGranted = ScreenCapturePermission.isGranted
    @State private var headerBarColor = Color.red
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
            Divider()
            Form {
                Section("Screenshots") {
                    Picker("Image format", selection: $settings.captureFormat) {
                        ForEach(AppSettings.ImageFormat.allCases, id: \.self) { format in
                            Text(format.label).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Copy captures to clipboard", isOn: $settings.copyCapturesToClipboard)
                    Text(settings.copyCapturesToClipboard
                        ? "Screenshots (including whole-screen) go to the Desktop and the clipboard, ready to ⌘V."
                        : "Screenshots are saved to the Desktop only — the clipboard is left untouched.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ink)
                    Picker("Capture timer", selection: $settings.timerSeconds) {
                        Text("Off").tag(0)
                        Text("3 s").tag(3)
                        Text("5 s").tag(5)
                        Text("10 s").tag(10)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Show mouse pointer", isOn: $settings.showCursor)
                    Toggle("Hide desktop icons in captures", isOn: $settings.hideDesktopIcons)
                    Toggle("Window capture keeps shadow", isOn: $settings.windowShadow)
                }
                Section("History Limits") {
                    Picker("Text entries", selection: $settings.maxTextEntries) {
                        ForEach([100, 250, 500, 1000, 2000], id: \.self) { Text("\($0)").tag($0) }
                    }
                    Picker("Images", selection: $settings.maxImageEntries) {
                        ForEach([50, 100, 200, 500, 1000], id: \.self) { Text("\($0)").tag($0) }
                    }
                    Text("Oldest unpinned items are dropped when a limit is reached; pinned items never count. The panel shows everything — scroll or search.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ink)
                }
                Section("Global Hotkeys") {
                    ForEach(HotkeyAction.allCases, id: \.self) { action in
                        HotkeyRecorderRow(action: action, settings: settings)
                    }
                    Text("Click a shortcut, then press the new keys (needs at least one of ⌃⌥⇧⌘; Esc cancels). ⟲ restores the default.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ink)
                }
                Section("Panel Appearance") {
                    Picker("Color mode", selection: $settings.panelColorScheme) {
                        Text("Light").tag(AppSettings.PanelColorScheme.light)
                        Text("Dark").tag(AppSettings.PanelColorScheme.dark)
                    }
                    .pickerStyle(.segmented)
                    ColorPicker("Header bar color", selection: $headerBarColor, supportsOpacity: false)
                        .onChange(of: headerBarColor) { _, color in
                            syncHeaderColor(from: color)
                        }
                    Button("Reset header color") {
                        settings.headerBarColorHex = ColorUtil.defaultHeaderBarHex
                        headerBarColor = Self.color(fromHex: settings.headerBarColorHex)
                    }
                    Text("Applies to the panel title bar. Text color adjusts automatically for contrast.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ink)
                }
                Section("Menu Bar") {
                    Toggle("Show menu bar icons", isOn: $settings.showMenuBarIcons)
                    Picker("Icon layout", selection: $settings.menuBarStyle) {
                        Text("One combined icon").tag(AppSettings.MenuBarStyle.combined)
                        Text("Split: clipboard + capture").tag(AppSettings.MenuBarStyle.split)
                    }
                    .disabled(!settings.showMenuBarIcons)
                    if settings.showMenuBarIcons {
                        Text(settings.menuBarStyle == .combined
                            ? "One icon opens everything. If you don't see it, check the ◂ overflow at the left of the menu bar (notched MacBooks) or drag Cliché left in the bar."
                            : "Two icons: clipboard history and capture tools. Hidden under the notch? Use ⌥1 and ⌥2 instead.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.ink)
                    } else {
                        Text("Icons hidden — use ⌥1 for clipboard history and ⌥2 for capture. Open Settings from the panel's gear icon.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.ink)
                    }
                }
                Section("Permissions") {
                    HStack {
                        Text("Screen Recording")
                        Spacer()
                        if screenRecordingGranted {
                            Label("Enabled", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button("Enable…") {
                                Task { @MainActor in
                                    _ = ScreenCapturePermission.requestAccessUserInitiated()
                                    screenRecordingGranted = ScreenCapturePermission.isGranted
                                }
                            }
                        }
                    }
                    if !screenRecordingGranted {
                        Text("Required for screenshots and recording. If Cliché is missing from the list, click Enable — macOS will prompt or open Settings. Toggle Cliché ON, then quit and reopen the app.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.ink)
                    }
                }
                Section("Clipboard") {
                    Toggle("Paste into focused field", isOn: $settings.pasteIntoFocusedField)
                    Text(settings.pasteIntoFocusedField
                        ? "Return or click fills the text field you were in when the panel opened (username, password, URL bar, etc.). Requires Accessibility permission."
                        : "Return or click copies to the clipboard and sends ⌘V to the previous app — classic paste behavior.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ink)
                }
                Section("General") {
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, wanted in
                            let actual = LoginItem.setEnabled(wanted)
                            if actual != wanted { launchAtLogin = actual }
                        }
                    Button("Edit Ignore Rules…") {
                        NSWorkspace.shared.open(ignoreRulesURL)
                    }
                    Text("Ignore rules block apps (e.g. password managers) from ever entering clipboard history.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ink)
                    let availableImporters = ClipboardImporters.available
                    if availableImporters.isEmpty {
                        Text("No supported clipboard manager found to import from (Maccy, Paste, or Clipy).")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.ink)
                    } else {
                        Text("Import history from:")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.ink)
                        ForEach(availableImporters.indices, id: \.self) { index in
                            let importer = availableImporters[index]
                            Button("Import from \(importer.name)…") {
                                runImporter(importer)
                            }
                        }
                        if let importMessage {
                            Text(importMessage)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.ink)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 360, height: 940)
        .background(PanelTheme.panelBackground(settings))
        .environment(\.colorScheme, PanelTheme.swiftUIColorScheme(settings))
        .onAppear {
            headerBarColor = Self.color(fromHex: settings.headerBarColorHex)
        }
        .onChange(of: settings.headerBarColorHex) { _, hex in
            headerBarColor = Self.color(fromHex: hex)
        }
    }

    private func syncHeaderColor(from color: Color) {
        let nsColor = NSColor(color)
        guard let rgb = nsColor.usingColorSpace(.sRGB) else { return }
        settings.headerBarColorHex = ColorUtil.hex(
            fromRGB: rgb.redComponent,
            green: rgb.greenComponent,
            blue: rgb.blueComponent)
    }

    private static func color(fromHex hex: String) -> Color {
        guard let rgb = ColorUtil.rgb(fromHex: hex) else {
            return Color(red: 0.78, green: 0.16, blue: 0.15)
        }
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    @MainActor
    private func runImporter(_ importer: ClipboardImporter) {
        guard let historyStore else {
            importMessage = "History store not available."
            return
        }
        let alert = NSAlert()
        alert.messageText = "Import from \(importer.name)?"
        alert.informativeText = """
        Cliché will copy your \(importer.name) clipboard history into Cliché. \
        Duplicates are skipped. This does not change \(importer.name).
        """
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        // Temporarily raise caps so imported items aren't evicted as they arrive,
        // then apply the user's configured limits (which may trim overflow).
        historyStore.setLimits(maxTexts: 5000, maxImages: 2000)
        do {
            let result = try importer.importAll(into: historyStore)
            historyStore.setLimits(
                maxTexts: settings.maxTextEntries,
                maxImages: settings.maxImageEntries)
            importMessage = result.summary
        } catch {
            historyStore.setLimits(
                maxTexts: settings.maxTextEntries,
                maxImages: settings.maxImageEntries)
            importMessage = "Import failed: \(error.localizedDescription)"
        }
    }
}


/// One row of the hotkeys table: click the shortcut chip, press new keys.
private struct HotkeyRecorderRow: View {
    let action: HotkeyAction
    let settings: AppSettings

    @State private var combo: HotkeyCombo?
    @State private var isRecording = false
    @State private var conflict: String?
    @State private var monitor: Any?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(action.label)
                if let conflict {
                    Text(conflict)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(isRecording ? "Type shortcut…" : (combo ?? settings.combo(for: action)).display)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isRecording ? Color.red.opacity(0.15) : Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            Button {
                settings.setCombo(nil, for: action)
                combo = settings.combo(for: action)
                conflict = nil
            } label: {
                Image(systemName: "arrow.uturn.backward.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.ink)
            .help("Restore default")
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        isRecording = true
        conflict = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            defer {}
            if event.keyCode == 53 {  // Esc — cancel
                stopRecording()
                return nil
            }
            let flags = event.modifierFlags
                .intersection([.command, .option, .control, .shift])
            guard !flags.isEmpty else {
                NSSound.beep()
                return nil
            }
            let key = prettyKey(event)
            guard !key.isEmpty else { return nil }
            let candidate = HotkeyCombo(
                keyCode: UInt32(event.keyCode),
                carbonModifiers: HotkeyCombo.carbonModifiers(from: flags),
                display: HotkeyCombo.displaySymbols(for: flags) + key)
            if let owner = settings.action(using: candidate), owner != action {
                conflict = "Already used by “\(owner.label)”"
                NSSound.beep()
                return nil
            }
            settings.setCombo(candidate, for: action)
            combo = candidate
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func prettyKey(_ event: NSEvent) -> String {
        if event.keyCode == 49 { return "Space" }
        guard let characters = event.charactersIgnoringModifiers?.uppercased(),
              let scalar = characters.unicodeScalars.first,
              scalar.value >= 0x20, scalar.value != 0x7F
        else { return "" }
        return characters
    }
}
