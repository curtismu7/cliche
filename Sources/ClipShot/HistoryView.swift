import AppKit
import ClipShotKit
import SwiftUI

struct HistoryView: View {
    let store: HistoryStore
    let capturesStore: CapturesStore
    let snippetsStore: SnippetsStore
    let settings: AppSettings
    let ignoreRulesURL: URL
    let onCopy: (ClipItem) -> Void
    let onPaste: (ClipItem) -> Void
    let onCopySnippet: (SnippetsStore.Snippet) -> Void
    let onPasteSnippet: (SnippetsStore.Snippet) -> Void
    let onCapture: (CaptureMode) -> Void
    let onCaptureText: () -> Void
    let onPickColor: () -> Void
    let onQuit: () -> Void

    private enum Tab: String, CaseIterable {
        case clipboard = "Clipboard"
        case captures = "Captures"
        case snippets = "Snippets"
    }

    @State private var tab: Tab = .clipboard
    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var showingHelp = false
    @State private var showingSettings = false
    @State private var editingItem: ClipItem?
    @State private var editText = ""
    @FocusState private var searchFocused: Bool

    /// Pinned first, then recent, both fuzzy-filtered — the order rows render
    /// in, shared by mouse and keyboard selection.
    private var visibleItems: [ClipItem] {
        let filtered = FuzzyMatcher.filter(store.items, query: query)
        return filtered.filter(\.pinned) + filtered.filter { !$0.pinned }
    }

    var body: some View {
        VStack(spacing: 0) {
            captureBar
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
            Divider()
            switch tab {
            case .clipboard: clipboardTab
            case .captures: CapturesGrid(store: capturesStore)
            case .snippets:
                SnippetsList(
                    store: snippetsStore,
                    onCopy: onCopySnippet,
                    onPaste: onPasteSnippet)
            }
            Divider()
            footer
        }
        .frame(width: 340, height: 460)
        .background(shortcutButtons)
        .sheet(isPresented: $showingHelp) { HelpView() }
        .sheet(isPresented: $showingSettings) {
            SettingsView(settings: settings, ignoreRulesURL: ignoreRulesURL)
        }
        .sheet(item: $editingItem) { item in
            VStack(alignment: .leading, spacing: 10) {
                Text("Edit Clip")
                    .font(.headline)
                TextEditor(text: $editText)
                    .font(.body)
                    .frame(width: 280, height: 110)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
                HStack {
                    Spacer()
                    Button("Cancel") { editingItem = nil }
                        .keyboardShortcut(.cancelAction)
                    Button("Save") {
                        store.updateText(item, to: editText)
                        editingItem = nil
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(editText.isEmpty)
                }
            }
            .padding(14)
        }
    }

    // MARK: Clipboard tab

    private var clipboardTab: some View {
        VStack(spacing: 0) {
            searchField
            if visibleItems.isEmpty {
                emptyState
            } else {
                itemList
            }
            Text("↩ copy · ⌥↩ paste into app · ⌘1–9 quick copy · ⌘⌫ delete · ⌘P pin")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.vertical, 4)
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search history", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit {
                    guard visibleItems.indices.contains(selectedIndex) else { return }
                    onCopy(visibleItems[selectedIndex])
                }
                .onKeyPress(.return) {
                    // ⌥Return pastes into the previous app; plain Return
                    // falls through to onSubmit (copy).
                    guard NSEvent.modifierFlags.contains(.option) else { return .ignored }
                    guard visibleItems.indices.contains(selectedIndex) else { return .handled }
                    onPaste(visibleItems[selectedIndex])
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    selectedIndex = min(selectedIndex + 1, visibleItems.count - 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    selectedIndex = max(selectedIndex - 1, 0)
                    return .handled
                }
        }
        .padding(8)
        .onAppear {
            query = ""
            selectedIndex = 0
            DispatchQueue.main.async { searchFocused = true }
        }
        .onChange(of: query) { selectedIndex = 0 }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(query.isEmpty ? "Clipboard history appears here" : "No matches")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var itemList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                        ItemRow(
                            item: item,
                            isSelected: index == selectedIndex,
                            shortcutNumber: index < 9 ? index + 1 : nil,
                            imageData: { store.imageData(for: item) },
                            onCopy: { onCopy(item) },
                            onPaste: { onPaste(item) },
                            onEdit: {
                                if case .text(let text) = item.kind {
                                    editText = text
                                    editingItem = item
                                }
                            },
                            onPin: { store.togglePin(item) },
                            onFloat: {
                                if let data = store.imageData(for: item),
                                   let image = NSImage(data: data) {
                                    FloatingImageWindow.show(image: image)
                                }
                            },
                            onDelete: { store.remove(item) }
                        )
                        .id(item.id)
                    }
                }
                .padding(6)
            }
            .onChange(of: selectedIndex) {
                guard visibleItems.indices.contains(selectedIndex) else { return }
                proxy.scrollTo(visibleItems[selectedIndex].id)
            }
        }
    }

    // MARK: Chrome

    private var captureBar: some View {
        HStack(spacing: 8) {
            CaptureButton(title: "Region", symbol: "rectangle.dashed") {
                onCapture(.region)
            }
            .help("Capture region  ⌃⌥⌘4")
            CaptureButton(title: "Window", symbol: "macwindow") {
                onCapture(.window)
            }
            .help("Capture window  ⌃⌥⌘5")
            CaptureButton(title: "Screen", symbol: "display") {
                onCapture(.fullScreen)
            }
            .help("Capture full screen")
            CaptureButton(title: "Text", symbol: "text.viewfinder", action: onCaptureText)
                .help("Copy text from screen (OCR)  ⌃⌥⌘6")
            CaptureButton(title: "Color", symbol: "eyedropper", action: onPickColor)
                .help("Pick a color — hex code goes to the clipboard")
            Spacer()
            Button(action: onQuit) {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Quit ClipShot")
        }
        .padding(10)
    }

    private var footer: some View {
        HStack {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings")

            Button {
                showingHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Shortcuts & help")

            Text("\(store.items.count) items")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if tab == .clipboard {
                Button("Clear History") { store.clear() }
                    .font(.caption)
            }
        }
        .padding(8)
    }

    /// Invisible buttons carrying the panel's key equivalents:
    /// ⌘1–⌘9 copy the nth visible item, ⌘⌫ deletes and ⌘P pins the selection.
    private var shortcutButtons: some View {
        Group {
            ForEach(1...9, id: \.self) { number in
                Button("") {
                    let index = number - 1
                    guard visibleItems.indices.contains(index) else { return }
                    onCopy(visibleItems[index])
                }
                .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
            }
            Button("") {
                guard visibleItems.indices.contains(selectedIndex) else { return }
                store.remove(visibleItems[selectedIndex])
                selectedIndex = min(selectedIndex, max(visibleItems.count - 2, 0))
            }
            .keyboardShortcut(.delete, modifiers: .command)
            Button("") {
                guard visibleItems.indices.contains(selectedIndex) else { return }
                store.togglePin(visibleItems[selectedIndex])
            }
            .keyboardShortcut("p", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }
}

private struct CaptureButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                Text(title).font(.caption2)
            }
            .frame(width: 52)
        }
    }
}

private struct ItemRow: View {
    let item: ClipItem
    let isSelected: Bool
    let shortcutNumber: Int?
    let imageData: () -> Data?
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onEdit: () -> Void
    let onPin: () -> Void
    let onFloat: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    private var isImage: Bool {
        if case .image = item.kind { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 8) {
            content
            Spacer(minLength: 4)
            if isHovering {
                RowButton(
                    symbol: "arrow.turn.down.left",
                    help: "Paste into previous app (⌥Return)",
                    action: onPaste)
                if isImage {
                    RowButton(symbol: "pip", help: "Float on top", action: onFloat)
                } else {
                    RowButton(symbol: "pencil", help: "Edit text", action: onEdit)
                }
                RowButton(
                    symbol: item.pinned ? "pin.slash" : "pin",
                    help: item.pinned ? "Unpin" : "Pin",
                    action: onPin)
                RowButton(symbol: "trash", help: "Delete", action: onDelete)
            } else {
                if item.pinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let number = shortcutNumber {
                    Text("⌘\(number)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected
                    ? Color.accentColor.opacity(0.25)
                    : isHovering ? Color.primary.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // ⌥-click pastes into the previous app; plain click copies.
            if NSEvent.modifierFlags.contains(.option) {
                onPaste()
            } else {
                onCopy()
            }
        }
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text(let text):
            Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                .lineLimit(2)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .image:
            if let data = imageData(), let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 64)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Label("Image unavailable", systemImage: "photo")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct RowButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }
}

// MARK: Snippets tab

private struct SnippetsList: View {
    let store: SnippetsStore
    let onCopy: (SnippetsStore.Snippet) -> Void
    let onPaste: (SnippetsStore.Snippet) -> Void

    @State private var editing: SnippetsStore.Snippet?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Click to copy · ⌥-click to paste · %DATE% %TIME% %CLIPBOARD%")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    editing = SnippetsStore.Snippet(name: "", template: "")
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("New snippet")
            }
            .padding(8)
            if store.snippets.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "text.badge.plus")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("Reusable text templates live here")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(store.snippets) { snippet in
                            SnippetRow(
                                snippet: snippet,
                                onCopy: { onCopy(snippet) },
                                onPaste: { onPaste(snippet) },
                                onEdit: { editing = snippet },
                                onDelete: { store.remove(snippet) })
                        }
                    }
                    .padding(6)
                }
            }
        }
        .sheet(item: $editing) { snippet in
            SnippetEditor(snippet: snippet) { edited in
                if store.snippets.contains(where: { $0.id == edited.id }) {
                    store.update(edited)
                } else {
                    store.add(name: edited.name, template: edited.template)
                }
            }
        }
    }
}

private struct SnippetRow: View {
    let snippet: SnippetsStore.Snippet
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.name.isEmpty ? "Untitled" : snippet.name)
                    .font(.callout.weight(.medium))
                Text(snippet.template)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isHovering {
                RowButton(
                    symbol: "arrow.turn.down.left",
                    help: "Paste into previous app",
                    action: onPaste)
                RowButton(symbol: "pencil", help: "Edit", action: onEdit)
                RowButton(symbol: "trash", help: "Delete", action: onDelete)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? Color.primary.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.option) {
                onPaste()
            } else {
                onCopy()
            }
        }
        .onHover { isHovering = $0 }
    }
}

private struct SnippetEditor: View {
    @State private var draft: SnippetsStore.Snippet
    let onSave: (SnippetsStore.Snippet) -> Void
    @Environment(\.dismiss) private var dismiss

    init(snippet: SnippetsStore.Snippet, onSave: @escaping (SnippetsStore.Snippet) -> Void) {
        _draft = State(initialValue: snippet)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Name", text: $draft.name)
            TextEditor(text: $draft.template)
                .font(.body)
                .frame(height: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(.quaternary))
            Text("Variables: %DATE%, %TIME%, %CLIPBOARD%")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.template.isEmpty)
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}

// MARK: Captures tab

private struct CapturesGrid: View {
    let store: CapturesStore

    private static let dateFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        if store.captures.isEmpty {
            VStack(spacing: 6) {
                Spacer()
                Image(systemName: "camera")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("Screenshots you take appear here")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                    ForEach(store.captures) { capture in
                        CaptureCell(capture: capture, store: store)
                    }
                }
                .padding(8)
            }
        }
    }

    private struct CaptureCell: View {
        let capture: CapturesStore.Capture
        let store: CapturesStore

        @State private var isHovering = false

        var body: some View {
            VStack(spacing: 2) {
                ZStack {
                    if let image = NSImage(contentsOfFile: capture.path) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.quaternary)
                            .frame(height: 72)
                            .overlay(Image(systemName: "photo"))
                    }
                    if isHovering {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.black.opacity(0.5))
                            .frame(height: 72)
                        HStack(spacing: 8) {
                            ShareLink(item: URL(fileURLWithPath: capture.path)) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .buttonStyle(.plain)
                            .help("Share…")
                            RowButton(symbol: "doc.on.doc", help: "Copy") {
                                if let data = try? Data(contentsOf: URL(fileURLWithPath: capture.path)) {
                                    ClipboardWriter.writeImage(pngData: data)
                                }
                            }
                            RowButton(symbol: "pencil.tip.crop.circle", help: "Annotate") {
                                AnnotationEditor.open(
                                    fileURL: URL(fileURLWithPath: capture.path))
                            }
                            RowButton(symbol: "pip", help: "Float on top") {
                                if let image = NSImage(contentsOfFile: capture.path) {
                                    FloatingImageWindow.show(image: image)
                                }
                            }
                            RowButton(symbol: "magnifyingglass", help: "Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting(
                                    [URL(fileURLWithPath: capture.path)])
                            }
                            RowButton(symbol: "trash", help: "Move to Trash") {
                                store.remove(capture, deleteFile: true)
                            }
                        }
                        .foregroundStyle(.white)
                    }
                }
                Text(CapturesGrid.dateFormat.string(from: capture.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .onHover { isHovering = $0 }
        }
    }
}
