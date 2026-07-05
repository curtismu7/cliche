import AppKit
import ClicheKit
import SwiftUI

extension Color {
    /// Readable "secondary" ink on the white panels (replaces washed-out
    /// system .secondary/.tertiary styles).
    static let ink = Color(white: 0.25)
}

enum PanelLayout {
    /// Everything in one panel (combined menu bar icon).
    case full
    /// Clipboard + snippets only (split mode, clipboard icon).
    case clipboardOnly
    /// Capture toolbar + captures grid only (split mode, capture icon).
    case captureOnly
}

struct HistoryView: View {
    var layout: PanelLayout = .full
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
    let onAllInOne: () -> Void
    let onMultiWindow: () -> Void
    let onPickColor: () -> Void
    let onRepeatRegion: () -> Void
    let onRuler: () -> Void
    let onScrollCapture: () -> Void
    let onRecord: () -> Void
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
    @State private var hostWindow: NSWindow?
    @State private var pinKeyMonitor: Any?
    @FocusState private var searchFocused: Bool

    /// Pinned first, then recent, both fuzzy-filtered.
    private var visibleItems: [ClipItem] {
        let filtered = FuzzyMatcher.filter(store.items, query: query)
        return filtered.filter(\.pinned) + filtered.filter { !$0.pinned }
    }

    /// Vertical list + keyboard navigation operate on text items.
    private var textItems: [ClipItem] {
        visibleItems.filter { if case .text = $0.kind { return true }; return false }
    }

    /// Images render as a horizontal strip above the text list.
    private var imageItems: [ClipItem] {
        visibleItems.filter { if case .image = $0.kind { return true }; return false }
    }

    private func pinSelection(pin: Bool) {
        guard textItems.indices.contains(selectedIndex),
              textItems[selectedIndex].pinned != pin else { return }
        store.togglePin(textItems[selectedIndex])
    }

    /// ⌥P/⌥U must be swallowed before the search field turns them into
    /// "π"/"¨" text — SwiftUI keyboardShortcut can't intercept option-combos,
    /// so use an event monitor scoped to this panel's window.
    private func installPinKeyMonitor() {
        guard pinKeyMonitor == nil else { return }
        pinKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.option),
                  !event.modifierFlags.contains(.command),
                  let eventWindow = event.window, eventWindow.isKeyWindow,
                  // Scope to this panel's window; if attachment reporting
                  // hasn't landed yet, fall back to the key window.
                  hostWindow == nil || eventWindow === hostWindow,
                  effectiveTab == .clipboard,
                  let key = event.charactersIgnoringModifiers?.lowercased()
            else { return event }
            switch key {
            case "p":
                pinSelection(pin: true)
                return nil
            case "u":
                pinSelection(pin: false)
                return nil
            default:
                return event
            }
        }
    }

    private func removePinKeyMonitor() {
        if let pinKeyMonitor {
            NSEvent.removeMonitor(pinKeyMonitor)
        }
        pinKeyMonitor = nil
    }

    private func openPreview(_ item: ClipItem) {
        PreviewWindow.show(item: item, store: store, onCopy: { onCopy(item) })
    }

    private var availableTabs: [Tab] {
        switch layout {
        case .full: return [.clipboard, .captures, .snippets]
        case .clipboardOnly: return [.clipboard, .snippets]
        case .captureOnly: return [.captures]
        }
    }

    /// The state `tab` can be outside this layout's tabs (fresh default);
    /// fall back to the first available.
    private var effectiveTab: Tab {
        availableTabs.contains(tab) ? tab : availableTabs[0]
    }

    private var headerTitle: String {
        switch layout {
        case .full: return "Cliché"
        case .clipboardOnly: return "Cliché — Clipboard"
        case .captureOnly: return "Cliché — Image Capture"
        }
    }

    /// Red brand bar pinned at the very top of every panel; also keeps real
    /// content clear of the popover's arrow region.
    private var headerBar: some View {
        HStack {
            Text(headerTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(red: 0.78, green: 0.16, blue: 0.15))
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            if layout != .clipboardOnly {
                captureBar
            }
            if availableTabs.count > 1 {
                Picker("", selection: $tab) {
                    ForEach(availableTabs, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 10)
                .padding(.vertical, layout == .clipboardOnly ? 8 : 0)
                .padding(.bottom, layout == .clipboardOnly ? 0 : 8)
            }
            Divider()
            switch effectiveTab {
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
        .frame(width: 340, height: layout == .captureOnly ? 455 : (layout == .full ? 530 : 490))
        .background(Color.white)
        .environment(\.colorScheme, .light)
        .background(shortcutButtons)
        .background(WindowAccessor { hostWindow = $0 })
        .onAppear(perform: installPinKeyMonitor)
        .onDisappear(perform: removePinKeyMonitor)
        .sheet(isPresented: $showingHelp) { HelpView(settings: settings) }
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
            if !imageItems.isEmpty {
                imageStrip
                Divider()
            }
            if textItems.isEmpty && imageItems.isEmpty {
                emptyState
            } else {
                itemList
            }
            Text("↩ copy · ⌥↩ paste into app · ⌘1–9 quick copy · ⌘⌫ delete · ⌥P pin · ⌥U unpin")
                .font(.system(size: 12))
                .foregroundStyle(Color.ink)
                .padding(.vertical, 4)
        }
    }

    /// Horizontal row of image clips: click copies, ⌥-click pastes; hover
    /// buttons preview, pin, and delete.
    private var imageStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 6) {
                ForEach(imageItems) { item in
                    ImageStripCell(
                        item: item,
                        imageData: { store.imageData(for: item) },
                        onCopy: { onCopy(item) },
                        onPaste: { onPaste(item) },
                        onPreview: { openPreview(item) },
                        onPin: { store.togglePin(item) },
                        onDelete: { store.remove(item) })
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(height: 84)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.ink)
            TextField("Search history", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit {
                    guard textItems.indices.contains(selectedIndex) else { return }
                    onCopy(textItems[selectedIndex])
                }
                .onKeyPress(.return) {
                    // ⌥Return pastes into the previous app; plain Return
                    // falls through to onSubmit (copy).
                    guard NSEvent.modifierFlags.contains(.option) else { return .ignored }
                    guard textItems.indices.contains(selectedIndex) else { return .handled }
                    onPaste(textItems[selectedIndex])
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    selectedIndex = min(selectedIndex + 1, textItems.count - 1)
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
                .foregroundStyle(Color.ink)
            Text(query.isEmpty ? "Clipboard history appears here" : "No matches")
                .foregroundStyle(Color.ink)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var pinnedCount: Int {
        textItems.prefix(while: \.pinned).count
    }

    private var pinnedHeader: some View {
        HStack(spacing: 4) {
            Image(systemName: "pin.fill")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
            Text("Pinned")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.ink)
            Spacer()
            Button("Unpin All") { store.unpinAll() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Color.ink)
                .help("Remove all pins (items rejoin normal history)")
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
    }

    private var recentSeparator: some View {
        HStack(spacing: 6) {
            Rectangle().fill(Color.black.opacity(0.15)).frame(height: 1)
            Text("Recent")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.ink)
                .fixedSize()
            Rectangle().fill(Color.black.opacity(0.15)).frame(height: 1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }

    private var itemList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    if pinnedCount > 0 {
                        pinnedHeader
                    }
                    ForEach(Array(textItems.enumerated()), id: \.element.id) { index, item in
                        if index == pinnedCount, pinnedCount > 0 {
                            recentSeparator
                        }
                        ItemRow(
                            item: item,
                            isSelected: index == selectedIndex,
                            shortcutNumber: index < 9 ? index + 1 : nil,
                            onCopy: { onCopy(item) },
                            onPaste: { onPaste(item) },
                            onPreview: { openPreview(item) },
                            onEdit: {
                                if case .text(let text) = item.kind {
                                    editText = text
                                    editingItem = item
                                }
                            },
                            onPin: { store.togglePin(item) },
                            onDelete: { store.remove(item) }
                        )
                        .id(item.id)
                    }
                }
                .padding(6)
            }
            .onChange(of: selectedIndex) {
                guard textItems.indices.contains(selectedIndex) else { return }
                proxy.scrollTo(textItems[selectedIndex].id)
            }
        }
    }

    // MARK: Chrome

    private var captureBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                labeledCapture("rectangle.dashed",
                               settings.combo(for: .captureRegion).display,
                               "Capture region  \(settings.combo(for: .captureRegion).display)") {
                    onCapture(.region)
                }
                labeledCapture("arrow.counterclockwise.square",
                               settings.combo(for: .repeatRegion).display,
                               "Repeat last region  \(settings.combo(for: .repeatRegion).display)",
                               action: onRepeatRegion)
                labeledCapture("macwindow",
                               settings.combo(for: .captureWindow).display,
                               "Capture window  \(settings.combo(for: .captureWindow).display)") {
                    onCapture(.window)
                }
                labeledCapture("display", "screen", "Capture full screen") {
                    onCapture(.fullScreen)
                }
                labeledCapture("text.viewfinder",
                               settings.combo(for: .captureText).display,
                               "Copy text from screen (OCR)  \(settings.combo(for: .captureText).display)",
                               action: onCaptureText)
                labeledCapture("square.grid.2x2",
                               settings.combo(for: .allInOne).display,
                               "All-in-one capture — mode strip  \(settings.combo(for: .allInOne).display)",
                               action: onAllInOne)
                Spacer()
            }
            HStack(spacing: 4) {
                labeledCapture("eyedropper", "color",
                               "Pick a color — hex + contrast checker", action: onPickColor)
                labeledCapture("ruler", "ruler",
                               "Pixel ruler — measure anything on screen", action: onRuler)
                labeledCapture("rectangle.expand.vertical", "scroll",
                               "Scrolling capture — you scroll, Cliché stitches",
                               action: onScrollCapture)
                labeledCapture("record.circle", "record",
                               "Record region to MP4 (optional GIF)", action: onRecord)
                labeledCapture("macwindow.on.rectangle", "multi",
                               "Capture several windows together", action: onMultiWindow)
                Spacer()
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func labeledCapture(
        _ symbol: String, _ label: String, _ help: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 1) {
            CaptureButton(symbol: symbol, action: action)
                .help(help)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.ink)
        }
    }

    private var footerCount: String {
        switch effectiveTab {
        case .clipboard: return "\(store.items.count) items"
        case .captures: return "\(capturesStore.captures.count) screenshots"
        case .snippets: return "\(snippetsStore.snippets.count) snippets"
        }
    }

    private var footer: some View {
        HStack {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.ink)
            .help("Settings")

            Button {
                showingHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.ink)
            .help("Shortcuts & help")

            Text(footerCount)
                .font(.system(size: 12))
                .foregroundStyle(Color.ink)
            Spacer()
            if effectiveTab == .clipboard {
                Button("Clear History") { store.clear() }
                    .font(.system(size: 12))
            }
            Button("Quit", action: onQuit)
                .font(.system(size: 12))
                .keyboardShortcut("q", modifiers: .command)
                .help("Quit Cliché (⌘Q)")
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
                    guard textItems.indices.contains(index) else { return }
                    onCopy(textItems[index])
                }
                .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
            }
            Button("") {
                guard textItems.indices.contains(selectedIndex) else { return }
                store.remove(textItems[selectedIndex])
                selectedIndex = min(selectedIndex, max(textItems.count - 2, 0))
            }
            .keyboardShortcut(.delete, modifiers: .command)
            Button("") {
                // ⌘P kept as a toggle (⌥P/⌥U are handled by the key monitor —
                // SwiftUI shortcuts can't claim option-combos from a text field)
                guard textItems.indices.contains(selectedIndex) else { return }
                store.togglePin(textItems[selectedIndex])
            }
            .keyboardShortcut("p", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }
}

private struct CaptureButton: View {
    let symbol: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .frame(width: 30, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isHovering ? Color.primary.opacity(0.1) : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct ItemRow: View {
    let item: ClipItem
    let isSelected: Bool
    let shortcutNumber: Int?
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onPreview: () -> Void
    let onEdit: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            content
            Spacer(minLength: 4)
            if isHovering {
                RowButton(symbol: "eye", help: "Preview", action: onPreview)
                RowButton(
                    symbol: "arrow.turn.down.left",
                    help: "Paste into previous app (⌥Return)",
                    action: onPaste)
                RowButton(symbol: "pencil", help: "Edit text", action: onEdit)
                RowButton(
                    symbol: item.pinned ? "pin.slash" : "pin",
                    help: item.pinned ? "Unpin" : "Pin",
                    action: onPin)
                RowButton(symbol: "trash", help: "Delete", action: onDelete)
            } else {
                if item.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }
                if let number = shortcutNumber {
                    Text("⌘\(number)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.ink)
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 5)
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
        if case .text(let text) = item.kind {
            Text(text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ⏎ "))
                .lineLimit(1)
                .font(.system(size: 14))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Cell in the horizontal image strip.
private struct ImageStripCell: View {
    let item: ClipItem
    let imageData: () -> Data?
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onPreview: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let data = imageData(), let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 100, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.black.opacity(0.15)))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(width: 100, height: 70)
                    .overlay(Image(systemName: "photo"))
            }
            if isHovering {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.black.opacity(0.45))
                    .frame(width: 100, height: 70)
                HStack(spacing: 8) {
                    RowButton(symbol: "eye", help: "Preview", color: .white, action: onPreview)
                    RowButton(
                        symbol: item.pinned ? "pin.slash" : "pin",
                        help: item.pinned ? "Unpin" : "Pin",
                        color: .white,
                        action: onPin)
                    RowButton(symbol: "trash", help: "Delete", color: .white, action: onDelete)
                }
                .foregroundStyle(.white)
                .frame(width: 100, height: 70)
            } else if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .padding(4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.option) {
                onPaste()
            } else {
                onCopy()
            }
        }
        .onHover { isHovering = $0 }
        .help("Click to copy · ⌥-click to paste")
    }
}
private struct RowButton: View {
    let symbol: String
    let help: String
    var color: Color = .ink
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(.plain)
        .foregroundStyle(color)
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
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ink)
                Spacer()
                Button {
                    editing = SnippetsStore.Snippet(name: "", template: "")
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.ink)
                .help("New snippet")
            }
            .padding(8)
            if store.snippets.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "text.badge.plus")
                        .font(.largeTitle)
                        .foregroundStyle(Color.ink)
                    Text("Reusable text templates live here")
                        .foregroundStyle(Color.ink)
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
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ink)
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
                .font(.system(size: 12))
                .foregroundStyle(Color.ink)
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

    @State private var showingCombine = false

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
                    .foregroundStyle(Color.ink)
                Text("Screenshots you take appear here")
                    .foregroundStyle(Color.ink)
                Text("⌃⌥⌘4 for a region, or use the buttons above")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ink)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 0) {
                if store.captures.count >= 2 {
                    HStack {
                        Spacer()
                        Button {
                            showingCombine = true
                        } label: {
                            Label("Combine…", systemImage: "square.grid.2x1")
                                .font(.system(size: 11.5))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.ink)
                        .help("Stitch several captures into one image")
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                        ForEach(Array(store.captures.enumerated()), id: \.element.id) { index, capture in
                            CaptureCell(
                                capture: capture,
                                older: index + 1 < store.captures.count
                                    ? store.captures[index + 1] : nil,
                                store: store)
                        }
                    }
                    .padding(8)
                }
            }
            .sheet(isPresented: $showingCombine) {
                CombineSheet(store: store) { showingCombine = false }
            }
        }
    }

    private struct CaptureCell: View {
        let capture: CapturesStore.Capture
        let older: CapturesStore.Capture?
        let store: CapturesStore

        @State private var isHovering = false

        /// Two-frame before/after GIF: the older capture first, this one second.
        private func makeBeforeAfterGIF() {
            guard let older,
                  let before = NSImage(contentsOfFile: older.path)?
                      .cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let after = NSImage(contentsOfFile: capture.path)?
                      .cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let gif = GIFBuilder.gifData(frames: [before, after], frameDelay: 0.8)
            else { return }
            let url = CaptureService.outputURL(fileExtension: "gif")
            do {
                try gif.write(to: url)
                store.add(path: url.path)
                InfoHUD.show("Before/after GIF saved to Desktop")
            } catch {
                NSLog("Cliche: failed to write GIF: \(error)")
            }
        }

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
                        VStack(spacing: 7) {
                            HStack(spacing: 9) {
                                ShareLink(item: URL(fileURLWithPath: capture.path)) {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                .buttonStyle(.plain)
                                .help("Share…")
                                RowButton(symbol: "doc.on.doc", help: "Copy", color: .white) {
                                    if let data = try? Data(contentsOf: URL(fileURLWithPath: capture.path)) {
                                        ClipboardWriter.writeImage(pngData: data)
                                    }
                                }
                                RowButton(symbol: "pencil.tip.crop.circle", help: "Annotate", color: .white) {
                                    AnnotationEditor.open(
                                        fileURL: URL(fileURLWithPath: capture.path))
                                }
                                RowButton(symbol: "pip", help: "Float on top", color: .white) {
                                    if let image = NSImage(contentsOfFile: capture.path) {
                                        FloatingImageWindow.show(image: image)
                                    }
                                }
                            }
                            HStack(spacing: 9) {
                                RowButton(symbol: "magnifyingglass", help: "Show in Finder", color: .white) {
                                    NSWorkspace.shared.activateFileViewerSelecting(
                                        [URL(fileURLWithPath: capture.path)])
                                }
                                if older != nil {
                                    RowButton(
                                        symbol: "film.stack",
                                        help: "Before/after GIF with previous capture",
                                        color: .white,
                                        action: makeBeforeAfterGIF)
                                }
                                RowButton(symbol: "trash", help: "Move to Trash", color: .white) {
                                    store.remove(capture, deleteFile: true)
                                }
                            }
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                    }
                }
                Text(CapturesGrid.dateFormat.string(from: capture.date))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ink)
            }
            .onHover { isHovering = $0 }
        }
    }
}


/// Reports the hosting NSWindow so views can scope event monitors to it.
/// Fires every time the view moves into a window (popovers attach late).
private struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> WindowReportingView {
        let view = WindowReportingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ view: WindowReportingView, context: Context) {
        view.onWindow = onWindow
        view.onWindow?(view.window)
    }
}

private final class WindowReportingView: NSView {
    var onWindow: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindow?(window)
    }
}
