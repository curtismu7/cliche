import AppKit
import ClicheKit
import SwiftUI

/// Floating preview for a history item — full image or full text — with an
/// action icon in each corner: ✕ close (top-left), copy (top-right),
/// pin (bottom-left), edit (bottom-right).
enum PreviewWindow {
    private static var panel: NSPanel?

    static func show(
        item: ClipItem,
        store: HistoryStore,
        onCopy: @escaping () -> Void
    ) {
        close()

        var image: NSImage?
        if case .image = item.kind {
            image = store.imageData(for: item).flatMap(NSImage.init(data:))
        }

        let view = PreviewView(
            item: item,
            image: image,
            onCopy: onCopy,
            onPinToggle: { store.togglePin(item) },
            onEditImage: {
                if let url = store.imageFileURL(for: item) {
                    close()
                    AnnotationEditor.open(fileURL: url)
                }
            },
            onSaveText: { newText in store.updateText(item, to: newText) },
            onClose: { close() })

        let size = NSSize(width: 440, height: 360)
        let previewPanel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        previewPanel.level = .floating
        previewPanel.backgroundColor = .clear
        previewPanel.isOpaque = false
        previewPanel.hasShadow = true
        previewPanel.isReleasedWhenClosed = false
        previewPanel.isMovableByWindowBackground = true
        previewPanel.contentView = NSHostingView(rootView: view)
        previewPanel.center()
        previewPanel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel = previewPanel
    }

    static func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

/// Borderless panels refuse key status by default; the text editor needs it.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct PreviewView: View {
    let item: ClipItem
    let image: NSImage?
    let onCopy: () -> Void
    let onPinToggle: () -> Void
    let onEditImage: () -> Void
    let onSaveText: (String) -> Void
    let onClose: () -> Void

    @State private var text: String
    @State private var isEditingText = false
    @State private var pinned: Bool

    init(
        item: ClipItem, image: NSImage?,
        onCopy: @escaping () -> Void,
        onPinToggle: @escaping () -> Void,
        onEditImage: @escaping () -> Void,
        onSaveText: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.item = item
        self.image = image
        self.onCopy = onCopy
        self.onPinToggle = onPinToggle
        self.onEditImage = onEditImage
        self.onSaveText = onSaveText
        self.onClose = onClose
        if case .text(let value) = item.kind {
            _text = State(initialValue: value)
        } else {
            _text = State(initialValue: "")
        }
        _pinned = State(initialValue: item.pinned)
    }

    var body: some View {
        ZStack {
            content
                .padding(28)

            // One action per corner.
            VStack {
                HStack {
                    CornerButton(symbol: "xmark.circle.fill", help: "Close", action: onClose)
                    Spacer()
                    CornerButton(symbol: "doc.on.doc.fill", help: "Copy") {
                        if isEditingText { saveEdits() }
                        onCopy()
                    }
                }
                Spacer()
                HStack {
                    CornerButton(
                        symbol: pinned ? "pin.circle.fill" : "pin.circle",
                        help: pinned ? "Unpin" : "Pin to list"
                    ) {
                        pinned.toggle()
                        onPinToggle()
                    }
                    Spacer()
                    if image != nil {
                        CornerButton(symbol: "pencil.circle.fill", help: "Edit (annotate)",
                                     action: onEditImage)
                    } else {
                        CornerButton(
                            symbol: isEditingText ? "checkmark.circle.fill" : "pencil.circle.fill",
                            help: isEditingText ? "Save changes" : "Edit text"
                        ) {
                            if isEditingText {
                                saveEdits()
                            }
                            isEditingText.toggle()
                        }
                    }
                }
            }
            .padding(8)
        }
        .frame(width: 440, height: 360)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.black.opacity(0.15)))
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isEditingText {
            TextEditor(text: $text)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
        } else {
            ScrollView {
                Text(text)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func saveEdits() {
        if !text.isEmpty {
            onSaveText(text)
        }
    }
}

private struct CornerButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(Color(red: 0.78, green: 0.16, blue: 0.15))
                .background(Circle().fill(.white).padding(2))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
