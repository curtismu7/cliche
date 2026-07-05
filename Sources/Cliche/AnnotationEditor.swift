import AppKit
import ClicheKit
import SwiftUI

/// The post-capture markup window: arrows, rectangles, text, blur, counters.
/// Save overwrites the capture's PNG and refreshes the clipboard, so history
/// and the Captures tab stay in sync.
enum AnnotationEditor {
    private static var window: NSWindow?

    static func open(fileURL: URL, settings: AppSettings = AppSettings()) {
        guard let nsImage = NSImage(contentsOf: fileURL),
              let base = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }

        window?.close()

        let view = AnnotationEditorView(
            base: base,
            settings: settings,
            onCopy: { flattened in
                copyToClipboard(flattened)
            },
            onSave: { flattened in
                if let data = CaptureDelivery.pngData(from: flattened) {
                    try? data.write(to: fileURL)
                }
                copyToClipboard(flattened)
                window?.close()
                window = nil
            })

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let maxSize = NSSize(
            width: screen.visibleFrame.width * 0.75,
            height: screen.visibleFrame.height * 0.75)
        let imageSize = nsImage.size
        let scale = min(1, maxSize.width / imageSize.width,
                        maxSize.height / imageSize.height)
        let contentSize = NSSize(
            width: max(520, imageSize.width * scale) + 288,  // + inspector
            height: imageSize.height * scale + 48)  // toolbar row

        let editorWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false)
        editorWindow.title = "Annotate — \(fileURL.lastPathComponent)"
        editorWindow.isReleasedWhenClosed = false
        editorWindow.contentViewController = NSHostingController(rootView: view)
        editorWindow.center()
        editorWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = editorWindow
    }

    private static func copyToClipboard(_ image: CGImage) {
        guard let data = CaptureDelivery.pngData(from: image) else { return }
        ClipboardWriter.writeImage(pngData: data)
    }
}

private enum EditorTool: String, CaseIterable {
    case arrow, line, rectangle, ellipse, freehand, highlight, text, blur,
         gaussian, counter

    var symbol: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .freehand: return "scribble"
        case .highlight: return "highlighter"
        case .text: return "textformat"
        case .blur: return "circle.grid.3x3.fill"
        case .gaussian: return "drop.halffull"
        case .counter: return "1.circle"
        }
    }

    var help: String {
        switch self {
        case .arrow: return "Arrow — drag"
        case .line: return "Line — drag"
        case .rectangle: return "Rectangle — drag"
        case .ellipse: return "Ellipse — drag"
        case .freehand: return "Freehand — draw"
        case .highlight: return "Highlighter — drag"
        case .text: return "Text — click to place"
        case .blur: return "Pixelate — drag over what to hide"
        case .gaussian: return "Blur — drag (unrecoverable)"
        case .counter: return "Counter badge — click to place"
        }
    }
}

struct AnnotationEditorView: View {
    let base: CGImage
    let settings: AppSettings
    let onCopy: (CGImage) -> Void
    let onSave: (CGImage) -> Void

    init(base: CGImage, settings: AppSettings,
         onCopy: @escaping (CGImage) -> Void,
         onSave: @escaping (CGImage) -> Void) {
        self.base = base
        self.settings = settings
        self.onCopy = onCopy
        self.onSave = onSave
        _config = State(initialValue: settings.lastBeautifyConfig)
    }

    @State private var tool: EditorTool = .arrow
    @State private var annotations: [Annotation] = []
    @State private var draft: Annotation?
    @State private var nextCounter = 1
    @State private var pendingTextPoint: CGPoint?
    @State private var textInput = ""
    @State private var config: BeautifyConfig
    @State private var isRedacting = false

    private var flattened: CGImage {
        AnnotationRenderer.render(
            base: base, annotations: annotations + (draft.map { [$0] } ?? []))
            ?? base
    }

    /// What Copy/Save produce: annotations plus the chosen backdrop.
    private var exported: CGImage {
        BeautifyRenderer.render(config, to: flattened) ?? flattened
    }

    /// One-click blur over everything that looks sensitive (emails, links,
    /// phone numbers, API-key-shaped tokens).
    private func redactSensitive() {
        isRedacting = true
        let image = base
        DispatchQueue.global(qos: .userInitiated).async {
            let rects = SensitiveTextDetector.detect(in: image)
            DispatchQueue.main.async {
                isRedacting = false
                guard !rects.isEmpty else {
                    NSSound.beep()
                    return
                }
                annotations += rects.map {
                    Annotation(kind: .blur, start: $0.origin,
                               end: CGPoint(x: $0.maxX, y: $0.maxY))
                }
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                toolbar
                Divider()
                GeometryReader { geometry in
                    canvas(in: geometry.size)
                }
                .background(Color(nsColor: .underPageBackgroundColor))
            }
            Divider()
            BeautifyInspector(config: $config, settings: settings)
        }
        .onChange(of: config) { settings.lastBeautifyConfig = config }
        .sheet(isPresented: Binding(
            get: { pendingTextPoint != nil },
            set: { if !$0 { pendingTextPoint = nil } }
        )) {
            textSheet
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $tool) {
                ForEach(EditorTool.allCases, id: \.self) { tool in
                    Image(systemName: tool.symbol)
                        .help(tool.help)
                        .tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Button {
                if !annotations.isEmpty {
                    if case .counter = annotations.last!.kind { nextCounter -= 1 }
                    annotations.removeLast()
                }
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(annotations.isEmpty)
            .help("Undo (⌘Z)")

            Button {
                redactSensitive()
            } label: {
                if isRedacting {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "eye.slash")
                }
            }
            .disabled(isRedacting)
            .help("Auto-redact sensitive text (emails, links, phone numbers, keys)")

            Spacer()

            Button("Copy") { onCopy(exported) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .help("Copy annotated image to clipboard")
            Button("Save") { onSave(exported) }
                .keyboardShortcut(.defaultAction)
                .help("Overwrite the capture file and copy to clipboard")
        }
        .padding(10)
    }

    private func canvas(in available: CGSize) -> some View {
        let display = exported
        let baseW = CGFloat(flattened.width), baseH = CGFloat(flattened.height)
        // For "None", `exported` is the untouched flattened image, so geometry
        // must be identity too — layout() would otherwise report a padded size.
        let identity = config.isIdentity
        let crop = identity
            ? CGRect(x: 0, y: 0, width: baseW, height: baseH)
            : BeautifyRenderer.sourceCrop(config, in: flattened)
        let croppedSize = CGSize(width: crop.width, height: crop.height)
        let l = identity
            ? BeautifyRenderer.BeautifyLayout(
                outputSize: CGSize(width: baseW, height: baseH),
                screenshotRect: CGRect(x: 0, y: 0, width: baseW, height: baseH))
            : BeautifyRenderer.layout(config, croppedSize: croppedSize)
        let outW = l.outputSize.width, outH = l.outputSize.height
        let scale = min(available.width / outW, available.height / outH)
        let displayed = CGSize(width: outW * scale, height: outH * scale)
        let origin = CGPoint(
            x: (available.width - displayed.width) / 2,
            y: (available.height - displayed.height) / 2)
        let shot = l.screenshotRect  // output pixels, bottom-left origin

        // Map a SwiftUI view point (top-left origin) to base-image pixels in
        // bottom-left origin (what Annotation coordinates use), routing through
        // the beautify layout so gestures land on the screenshot, not padding.
        func imagePoint(_ viewPoint: CGPoint) -> CGPoint {
            let outX = (viewPoint.x - origin.x) / scale
            let outYFromBottom = outH - (viewPoint.y - origin.y) / scale
            let sx = shot.width / croppedSize.width
            let sy = shot.height / croppedSize.height
            let cropX = (outX - shot.minX) / sx
            let cropYFromBottom = (outYFromBottom - shot.minY) / sy
            // crop is top-left origin; convert to base bottom-left origin.
            let baseX = crop.minX + cropX
            let baseYFromBottom = baseH - crop.maxY + cropYFromBottom
            return CGPoint(
                x: min(max(baseX, 0), baseW),
                y: min(max(baseYFromBottom, 0), baseH))
        }

        return Image(nsImage: NSImage(
            cgImage: display,
            size: NSSize(width: outW, height: outH)))
            .resizable()
            .interpolation(.high)
            .frame(width: displayed.width, height: displayed.height)
            .position(
                x: origin.x + displayed.width / 2,
                y: origin.y + displayed.height / 2)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let start = imagePoint(value.startLocation)
                        let current = imagePoint(value.location)
                        switch tool {
                        case .arrow:
                            draft = Annotation(kind: .arrow, start: start, end: current)
                        case .line:
                            draft = Annotation(kind: .line, start: start, end: current)
                        case .rectangle:
                            draft = Annotation(kind: .rectangle, start: start, end: current)
                        case .ellipse:
                            draft = Annotation(kind: .ellipse, start: start, end: current)
                        case .highlight:
                            draft = Annotation(kind: .highlight, start: start, end: current)
                        case .blur:
                            draft = Annotation(kind: .blur, start: start, end: current)
                        case .gaussian:
                            draft = Annotation(kind: .gaussianBlur, start: start, end: current)
                        case .freehand:
                            if case .freehand(var points) = draft?.kind {
                                points.append(current)
                                draft = Annotation(
                                    kind: .freehand(points: points),
                                    start: draft!.start, end: current)
                            } else {
                                draft = Annotation(
                                    kind: .freehand(points: [start, current]),
                                    start: start, end: current)
                            }
                        case .text, .counter:
                            break
                        }
                    }
                    .onEnded { value in
                        let point = imagePoint(value.location)
                        switch tool {
                        case .arrow, .line, .rectangle, .ellipse, .highlight,
                             .blur, .gaussian, .freehand:
                            if let finished = draft, dragIsMeaningful(finished) {
                                annotations.append(finished)
                            }
                            draft = nil
                        case .counter:
                            annotations.append(Annotation(
                                kind: .counter(nextCounter), start: point, end: point))
                            nextCounter += 1
                        case .text:
                            textInput = ""
                            pendingTextPoint = point
                        }
                    })
    }

    /// Filters out accidental clicks: a drag counts if it moved, or if a
    /// freehand stroke gathered more than a couple of points.
    private func dragIsMeaningful(_ annotation: Annotation) -> Bool {
        if case .freehand(let points) = annotation.kind { return points.count > 2 }
        return hypot(annotation.end.x - annotation.start.x,
                     annotation.end.y - annotation.start.y) > 4
    }

    private var textSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Label text", text: $textInput)
                .frame(width: 240)
            HStack {
                Spacer()
                Button("Cancel") { pendingTextPoint = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    if let point = pendingTextPoint, !textInput.isEmpty {
                        annotations.append(Annotation(
                            kind: .text(textInput), start: point, end: point))
                    }
                    pendingTextPoint = nil
                }
                .keyboardShortcut(.defaultAction)
                .disabled(textInput.isEmpty)
            }
        }
        .padding(14)
    }
}
