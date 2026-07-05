import AppKit
import ClipShotKit
import SwiftUI

/// The post-capture markup window: arrows, rectangles, text, blur, counters.
/// Save overwrites the capture's PNG and refreshes the clipboard, so history
/// and the Captures tab stay in sync.
enum AnnotationEditor {
    private static var window: NSWindow?

    static func open(fileURL: URL) {
        guard let nsImage = NSImage(contentsOf: fileURL),
              let base = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }

        window?.close()

        let view = AnnotationEditorView(
            base: base,
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
            width: max(520, imageSize.width * scale),
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
    case arrow, rectangle, text, blur, counter

    var symbol: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .text: return "textformat"
        case .blur: return "circle.grid.3x3.fill"
        case .counter: return "1.circle"
        }
    }

    var help: String {
        switch self {
        case .arrow: return "Arrow — drag"
        case .rectangle: return "Rectangle — drag"
        case .text: return "Text — click to place"
        case .blur: return "Pixelate — drag over what to hide"
        case .counter: return "Counter badge — click to place"
        }
    }
}

struct AnnotationEditorView: View {
    let base: CGImage
    let onCopy: (CGImage) -> Void
    let onSave: (CGImage) -> Void

    @State private var tool: EditorTool = .arrow
    @State private var annotations: [Annotation] = []
    @State private var draft: Annotation?
    @State private var nextCounter = 1
    @State private var pendingTextPoint: CGPoint?
    @State private var textInput = ""

    private var flattened: CGImage {
        AnnotationRenderer.render(
            base: base, annotations: annotations + (draft.map { [$0] } ?? []))
            ?? base
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            GeometryReader { geometry in
                canvas(in: geometry.size)
            }
            .background(Color(nsColor: .underPageBackgroundColor))
        }
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

            Spacer()

            Button("Copy") { onCopy(flattened) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .help("Copy annotated image to clipboard")
            Button("Save") { onSave(flattened) }
                .keyboardShortcut(.defaultAction)
                .help("Overwrite the capture file and copy to clipboard")
        }
        .padding(10)
    }

    private func canvas(in available: CGSize) -> some View {
        let imageWidth = CGFloat(base.width)
        let imageHeight = CGFloat(base.height)
        let scale = min(available.width / imageWidth, available.height / imageHeight)
        let displayed = CGSize(width: imageWidth * scale, height: imageHeight * scale)
        let origin = CGPoint(
            x: (available.width - displayed.width) / 2,
            y: (available.height - displayed.height) / 2)

        func imagePoint(_ viewPoint: CGPoint) -> CGPoint {
            CGPoint(
                x: min(max((viewPoint.x - origin.x) / scale, 0), imageWidth),
                y: min(max(imageHeight - (viewPoint.y - origin.y) / scale, 0), imageHeight))
        }

        return Image(nsImage: NSImage(
            cgImage: flattened,
            size: NSSize(width: imageWidth, height: imageHeight)))
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
                        case .rectangle:
                            draft = Annotation(kind: .rectangle, start: start, end: current)
                        case .blur:
                            draft = Annotation(kind: .blur, start: start, end: current)
                        case .text, .counter:
                            break
                        }
                    }
                    .onEnded { value in
                        let point = imagePoint(value.location)
                        switch tool {
                        case .arrow, .rectangle, .blur:
                            if let finished = draft,
                               hypot(finished.end.x - finished.start.x,
                                     finished.end.y - finished.start.y) > 4 {
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
