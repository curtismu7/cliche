import AppKit
import ClipShotKit
import SwiftUI

struct HistoryView: View {
    let store: HistoryStore
    let onCopy: (ClipItem) -> Void
    let onCapture: (CaptureMode) -> Void
    let onQuit: () -> Void

    private var pinnedItems: [ClipItem] { store.items.filter(\.pinned) }
    private var recentItems: [ClipItem] { store.items.filter { !$0.pinned } }

    var body: some View {
        VStack(spacing: 0) {
            captureBar
            Divider()
            if store.items.isEmpty {
                emptyState
            } else {
                itemList
            }
            Divider()
            footer
        }
        .frame(width: 340, height: 440)
    }

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

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "doc.on.clipboard")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Clipboard history appears here")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var itemList: some View {
        ScrollView {
            LazyVStack(spacing: 2, pinnedViews: []) {
                if !pinnedItems.isEmpty {
                    sectionHeader("Pinned")
                    ForEach(pinnedItems) { item in
                        row(for: item)
                    }
                }
                if !recentItems.isEmpty {
                    if !pinnedItems.isEmpty { sectionHeader("Recent") }
                    ForEach(recentItems) { item in
                        row(for: item)
                    }
                }
            }
            .padding(6)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
    }

    private func row(for item: ClipItem) -> some View {
        ItemRow(
            item: item,
            imageData: { store.imageData(for: item) },
            onCopy: { onCopy(item) },
            onPin: { store.togglePin(item) },
            onDelete: { store.remove(item) }
        )
    }

    private var footer: some View {
        HStack {
            Text("\(store.items.count) items")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Clear History") { store.clear() }
                .font(.caption)
        }
        .padding(8)
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
    let imageData: () -> Data?
    let onCopy: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            content
            Spacer(minLength: 4)
            if isHovering {
                Button(action: onPin) {
                    Image(systemName: item.pinned ? "pin.slash" : "pin")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(item.pinned ? "Unpin" : "Pin")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Delete")
            } else if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? Color.primary.opacity(0.08) : Color.clear)
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
