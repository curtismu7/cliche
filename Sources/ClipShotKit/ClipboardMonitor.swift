import AppKit

/// Watches the general pasteboard by polling `changeCount` (macOS offers no
/// change notification) and feeds new text/image contents into a HistoryStore.
public final class ClipboardMonitor {
    private let store: HistoryStore
    private let ignoreRules: IgnoreRules
    private let frontmostBundleID: () -> String?
    private let pasteboard = NSPasteboard.general
    private var timer: Timer?
    private var lastChangeCount: Int

    public init(
        store: HistoryStore,
        ignoreRules: IgnoreRules = .default,
        frontmostBundleID: @escaping () -> String? = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }
    ) {
        self.store = store
        self.ignoreRules = ignoreRules
        self.frontmostBundleID = frontmostBundleID
        self.lastChangeCount = pasteboard.changeCount
    }

    public func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Writes a history item back to the pasteboard. The next poll sees the
    /// change and moves the item to the front of history via dedupe.
    public func copyToPasteboard(_ item: ClipItem) {
        pasteboard.clearContents()
        switch item.kind {
        case .text(let text):
            pasteboard.setString(text, forType: .string)
        case .image:
            if let data = store.imageData(for: item) {
                pasteboard.setData(data, forType: .png)
            }
        }
    }

    private func check() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        let types = (pasteboard.types ?? []).map(\.rawValue)
        guard !ignoreRules.shouldIgnore(
            types: types, frontmostBundleID: frontmostBundleID())
        else { return }

        if let png = pasteboard.data(forType: .png) {
            store.addImage(png)
        } else if let tiff = pasteboard.data(forType: .tiff),
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) {
            store.addImage(png)
        } else if let text = pasteboard.string(forType: .string),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.addText(text)
        }
    }
}
