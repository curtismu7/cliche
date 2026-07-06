import AppKit
import ClicheKit
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let ignoreRulesURL: URL
    var historyStore: HistoryStore? = nil

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var importMessage: String?
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
                Section("Menu Bar") {
                    Picker("Icons", selection: $settings.menuBarStyle) {
                        Text("One combined icon").tag(AppSettings.MenuBarStyle.combined)
                        Text("Split: clipboard + capture").tag(AppSettings.MenuBarStyle.split)
                    }
                    Text(settings.menuBarStyle == .combined
                        ? "One icon opens everything."
                        : "Two icons: 📋 opens clipboard history & snippets, 📷 opens capture tools & screenshots.")
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
        .frame(width: 360, height: 820)
        .background(Color.white)
        .environment(\.colorScheme, .light)
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
        do {
            let result = try importer.importAll(into: historyStore)
            importMessage = result.summary
        } catch {
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
