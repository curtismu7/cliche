import AppKit
import ClipShotKit
import SwiftUI

struct HistoryView: View {
    let store: HistoryStore
    let capturesStore: CapturesStore
    let ignoreRulesURL: URL
    let onCopy: (ClipItem) -> Void
    let onCapture: (CaptureMode) -> Void
    let onQuit: () -> Void

    private enum Tab: String, CaseIterable {
        case clipboard = "Clipboard"
        case captures = "Captures"
    }

    @State private var tab: Tab = .clipboard
    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var launchAtLogin = LoginItem.isEnabled
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
            }
            Divider()
            footer
        }
        .frame(width: 340, height: 460)
        .background(shortcutButtons)
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
            launchAtLogin = LoginItem.isEnabled
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
            CaptureButton(title: "Window", symbol: "macwindow") {
                onCapture(.window)
            }
            CaptureButton(title: "Screen", symbol: "display") {
                onCapture(.fullScreen)
            }
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
            Menu {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                Button("Edit Ignore Rules…") {
                    NSWorkspace.shared.open(ignoreRulesURL)
                }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .onChange(of: launchAtLogin) { _, wanted in
                let actual = LoginItem.setEnabled(wanted)
                if actual != wanted { launchAtLogin = actual }
            }

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
        .help("Capture \(title.lowercased())")
    }
}

private struct ItemRow: View {
    let item: ClipItem
    let isSelected: Bool
    let shortcutNumber: Int?
    let imageData: () -> Data?
    let onCopy: () -> Void
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
                if isImage {
                    RowButton(symbol: "pip", help: "Float on top", action: onFloat)
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
        .onTapGesture(perform: onCopy)
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
                        HStack(spacing: 10) {
                            RowButton(symbol: "doc.on.doc", help: "Copy") {
                                if let data = try? Data(contentsOf: URL(fileURLWithPath: capture.path)) {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setData(data, forType: .png)
                                }
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
