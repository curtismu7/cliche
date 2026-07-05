import AppKit
import ClicheKit
import SwiftUI

/// Creates a capture preset: mode + format + clipboard + destination +
/// filename pattern, saved into AppSettings.
struct NewPresetSheet: View {
    let settings: AppSettings
    let onDone: () -> Void

    @State private var name = ""
    @State private var mode: CaptureMode = .region
    @State private var format: AppSettings.ImageFormat = .png
    @State private var copyToClipboard = true
    @State private var destinationPath = ""
    @State private var pattern = CaptureNaming.defaultPattern

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New capture preset")
                .font(.system(size: 13, weight: .semibold))

            TextField("Preset name", text: $name)

            Picker("Mode", selection: $mode) {
                Text("Region").tag(CaptureMode.region)
                Text("Window").tag(CaptureMode.window)
                Text("Full screen").tag(CaptureMode.fullScreen)
            }

            Picker("Format", selection: $format) {
                ForEach(AppSettings.ImageFormat.allCases, id: \.self) { format in
                    Text(format.label).tag(format)
                }
            }

            Toggle("Copy to clipboard", isOn: $copyToClipboard)

            HStack {
                TextField("Destination (empty = Desktop)", text: $destinationPath)
                Button("Browse…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.canCreateDirectories = true
                    if panel.runModal() == .OK, let url = panel.url {
                        destinationPath = url.path
                    }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                TextField("Filename pattern", text: $pattern)
                Text("Tokens: %DATE% and %TIME%")
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onDone)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    settings.capturePresets.append(CapturePreset(
                        name: name,
                        mode: mode,
                        format: format,
                        copyToClipboard: copyToClipboard,
                        destinationPath: destinationPath.isEmpty ? nil : destinationPath,
                        filenamePattern: pattern.isEmpty
                            ? CaptureNaming.defaultPattern : pattern))
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
        }
        .padding(14)
        .frame(width: 380)
    }
}
