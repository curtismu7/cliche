import AppKit
import ClicheKit
import SwiftUI

/// Right-hand panel of the annotation editor: background, frame, shadow,
/// canvas size, and preset management. Binds a BeautifyConfig the editor
/// composites live.
struct BeautifyInspector: View {
    @Binding var config: BeautifyConfig
    let settings: AppSettings
    @State private var presetName = ""
    @State private var showingSave = false

    private var gradientStart: Binding<Color> {
        Binding(
            get: { config.background.stops.first.map { Color(cgColor: $0.color.cgColor) } ?? .black },
            set: { setStop(0, $0) })
    }
    private var gradientEnd: Binding<Color> {
        Binding(
            get: { config.background.stops.last.map { Color(cgColor: $0.color.cgColor) } ?? .black },
            set: { setStop(config.background.stops.count - 1, $0) })
    }

    private func setStop(_ index: Int, _ color: Color) {
        guard let rgba = color.rgba else { return }
        if config.background.stops.isEmpty {
            config.background.stops = [
                GradientStop(color: rgba, location: 0),
                GradientStop(color: rgba, location: 1)]
        } else if config.background.stops.indices.contains(index) {
            config.background.stops[index].color = rgba
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                presetSection
                Divider()
                backgroundSection
                Divider()
                frameSection
                Divider()
                shadowSection
                Divider()
                canvasSection
            }
            .padding(14)
        }
        .frame(width: 288)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var presetSection: some View {
        HStack(spacing: 8) {
            Menu(currentPresetName) {
                Section("Built-in") {
                    ForEach(BeautifyConfig.builtInPresets) { preset in
                        Button(preset.name) { config = preset.config }
                    }
                }
                if !settings.beautifyPresets.isEmpty {
                    Section("Yours") {
                        ForEach(settings.beautifyPresets) { preset in
                            Button(preset.name) { config = preset.config }
                        }
                    }
                }
            }
            Button {
                presetName = ""
                showingSave = true
            } label: { Image(systemName: "plus") }
                .help("Save as preset…")

            if let match = settings.beautifyPresets.first(where: { $0.config == config }) {
                Button {
                    settings.beautifyPresets.removeAll { $0.id == match.id }
                } label: { Image(systemName: "trash") }
                    .help("Delete this preset")
            }
        }
        .sheet(isPresented: $showingSave) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Preset name", text: $presetName).frame(width: 220)
                HStack {
                    Spacer()
                    Button("Cancel") { showingSave = false }
                        .keyboardShortcut(.cancelAction)
                    Button("Save") {
                        if !presetName.isEmpty {
                            settings.beautifyPresets.append(
                                NamedBeautifyConfig(name: presetName, config: config))
                        }
                        showingSave = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(presetName.isEmpty)
                }
            }.padding(14)
        }
    }

    private var currentPresetName: String {
        BeautifyConfig.builtInPresets.first { $0.config == config }?.name
            ?? settings.beautifyPresets.first { $0.config == config }?.name
            ?? "Custom"
    }

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("BACKGROUND").sectionLabel()
            HStack {
                ColorPicker("", selection: gradientStart).labelsHidden()
                ColorPicker("", selection: gradientEnd).labelsHidden()
                Spacer()
            }
            slider("Angle", value: $config.background.angleDegrees, range: 0...360, unit: "°")
        }
    }

    private var frameSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("FRAME").sectionLabel()
            slider("Padding", value: $config.padding, range: 0...0.4, unit: "%", scale: 100)
            slider("Corner", value: $config.cornerRadius, range: 0...0.1, unit: "%", scale: 100)
            Toggle("Inset matte", isOn: Binding(
                get: { config.inset != nil },
                set: { config.inset = $0
                    ? InsetFrame(width: 0.03, color: RGBAColor(1, 1, 1))
                    : nil }))
        }
    }

    private var shadowSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("SHADOW").sectionLabel()
            slider("Blur", value: $config.shadow.blur, range: 0...0.12, unit: "%", scale: 100)
            slider("Offset", value: $config.shadow.yOffsetFraction, range: 0...0.08, unit: "%", scale: 100)
            slider("Opacity", value: $config.shadow.opacity, range: 0...1, unit: "%", scale: 100)
        }
    }

    private var canvasSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("CANVAS").sectionLabel()
            Picker("", selection: $config.canvas) {
                ForEach(Array(CanvasSize.socialPresets.enumerated()), id: \.offset) { _, size in
                    Text(size.label).tag(size)
                }
            }
            .labelsHidden()
            Toggle("Auto-balance", isOn: $config.autoBalance)
        }
    }

    private func slider(_ name: String, value: Binding<Double>,
                        range: ClosedRange<Double>, unit: String = "",
                        scale: Double = 1) -> some View {
        HStack(spacing: 8) {
            Text(name).frame(width: 62, alignment: .leading)
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Slider(value: value, in: range)
            Text("\(Int((value.wrappedValue * scale).rounded()))\(unit)")
                .font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(.tertiary).frame(width: 34, alignment: .trailing)
        }
    }
}

private extension Text {
    func sectionLabel() -> some View {
        self.font(.system(size: 10.5, weight: .bold))
            .tracking(0.7).foregroundStyle(.tertiary)
    }
}

extension Color {
    /// sRGB components for persistence; nil if the color can't be resolved.
    var rgba: RGBAColor? {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return RGBAColor(Double(c.redComponent), Double(c.greenComponent),
                         Double(c.blueComponent), Double(c.alphaComponent))
    }
}
