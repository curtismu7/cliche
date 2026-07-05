import AppKit
import ClicheKit
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let ignoreRulesURL: URL

    @State private var launchAtLogin = LoginItem.isEnabled
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Capture timer", selection: $settings.timerSeconds) {
                        Text("Off").tag(0)
                        Text("3 s").tag(3)
                        Text("5 s").tag(5)
                        Text("10 s").tag(10)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Show mouse pointer", isOn: $settings.showCursor)
                    Toggle("Window capture keeps shadow", isOn: $settings.windowShadow)
                }
                Section("Menu Bar") {
                    Picker("Icons", selection: $settings.menuBarStyle) {
                        Text("One combined icon").tag(AppSettings.MenuBarStyle.combined)
                        Text("Split: clipboard + capture").tag(AppSettings.MenuBarStyle.split)
                    }
                    Text(settings.menuBarStyle == .combined
                        ? "One icon opens everything."
                        : "Two icons: 📋 opens clipboard history & snippets, 📷 opens capture tools & screenshots.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 340, height: 500)
    }
}
