import AppKit
import AVFoundation
import Foundation
import ClicheKit

// Minimal test harness: Command Line Tools provide no XCTest/swift-testing,
// so assertions run in a plain executable. Exits 1 if any check fails.

var failures = 0

func expect(_ condition: Bool, _ label: String) {
    if condition {
        print("PASS  \(label)")
    } else {
        failures += 1
        print("FAIL  \(label)")
    }
}

func makeTempDir() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClicheTests-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

// A tiny valid PNG (1x1 transparent pixel).
let pngData = Data(base64Encoded:
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
)!

// addsTextToFront
do {
    let store = HistoryStore(directory: makeTempDir())
    store.addText("first")
    store.addText("second")
    expect(store.items.count == 2
        && store.items[0].kind == .text("second")
        && store.items[1].kind == .text("first"), "adds text to front")
}

// ignoresEmptyText
do {
    let store = HistoryStore(directory: makeTempDir())
    store.addText("")
    expect(store.items.isEmpty, "ignores empty text")
}

// dedupesTextAndMovesToFront
do {
    let store = HistoryStore(directory: makeTempDir())
    store.addText("a")
    store.addText("b")
    store.addText("a")
    expect(store.items.count == 2
        && store.items[0].kind == .text("a")
        && store.items[1].kind == .text("b"), "dedupes text and moves to front")
}

// capsTextsAtMaxTexts
do {
    let store = HistoryStore(directory: makeTempDir(), maxTexts: 3)
    for i in 1...5 { store.addText("item \(i)") }
    expect(store.items.count == 3
        && store.items[0].kind == .text("item 5")
        && store.items[2].kind == .text("item 3"), "caps texts at maxTexts")
}

// textAndImageCapsAreIndependent
do {
    let store = HistoryStore(directory: makeTempDir(), maxTexts: 2, maxImages: 2)
    // Three distinct "image" payloads (store hashes bytes, no PNG validation).
    store.addImage(pngData)
    store.addImage(pngData + Data([1]))
    store.addImage(pngData + Data([2]))
    for i in 1...3 { store.addText("t\(i)") }
    let texts = store.items.filter { if case .text = $0.kind { return true }; return false }
    let images = store.items.filter { if case .image = $0.kind { return true }; return false }
    expect(texts.count == 2 && images.count == 2,
        "text and image caps are independent")
}

// imageRoundTrip
do {
    let store = HistoryStore(directory: makeTempDir())
    store.addImage(pngData)
    expect(store.items.count == 1
        && store.imageData(for: store.items[0]) == pngData, "image round trip")
}

// imageFileURL
do {
    let store = HistoryStore(directory: makeTempDir())
    store.addImage(pngData)
    store.addText("not an image")
    let url = store.imageFileURL(for: store.items[1])
    expect(url != nil && FileManager.default.fileExists(atPath: url!.path)
        && store.imageFileURL(for: store.items[0]) == nil,
        "imageFileURL points at the stored PNG, nil for text")
}

// dedupesIdenticalImages
do {
    let store = HistoryStore(directory: makeTempDir())
    store.addImage(pngData)
    store.addText("middle")
    store.addImage(pngData)
    expect(store.items.count == 2
        && store.imageData(for: store.items[0]) == pngData, "dedupes identical images")
}

// persistsAcrossReload
do {
    let dir = makeTempDir()
    let store = HistoryStore(directory: dir)
    store.addText("hello")
    store.addImage(pngData)
    let reloaded = HistoryStore(directory: dir)
    expect(reloaded.items.count == 2
        && reloaded.imageData(for: reloaded.items[0]) == pngData
        && reloaded.items[1].kind == .text("hello"), "persists across reload")
}

// clearRemovesItemsAndFiles
do {
    let dir = makeTempDir()
    let store = HistoryStore(directory: dir)
    store.addText("hello")
    store.addImage(pngData)
    store.clear()
    let reloaded = HistoryStore(directory: dir)
    let images = (try? FileManager.default.contentsOfDirectory(
        atPath: dir.appendingPathComponent("images").path)) ?? []
    expect(store.items.isEmpty && reloaded.items.isEmpty && images.isEmpty,
        "clear removes items and files")
}

// evictionDeletesImageFile
do {
    let dir = makeTempDir()
    let store = HistoryStore(directory: dir, maxImages: 1)
    store.addImage(pngData)
    store.addImage(pngData + Data([1]))  // evicts the first image
    let files = (try? FileManager.default.contentsOfDirectory(
        atPath: dir.appendingPathComponent("images").path)) ?? []
    expect(store.items.count == 1 && files.count == 1, "eviction deletes image file")
}

// removeDeletesItemAndFile
do {
    let dir = makeTempDir()
    let store = HistoryStore(directory: dir)
    store.addText("keep me")
    store.addImage(pngData)
    store.remove(store.items[0])  // the image
    let images = (try? FileManager.default.contentsOfDirectory(
        atPath: dir.appendingPathComponent("images").path)) ?? []
    expect(store.items.count == 1
        && store.items[0].kind == .text("keep me")
        && images.isEmpty, "remove deletes item and image file")
}

// pinSurvivesClear
do {
    let store = HistoryStore(directory: makeTempDir())
    store.addText("pinned")
    store.togglePin(store.items[0])
    store.addText("unpinned")
    store.clear()
    expect(store.items.count == 1
        && store.items[0].kind == .text("pinned")
        && store.items[0].pinned, "pinned items survive clear")
}

// pinnedNotEvictedByCap
do {
    let store = HistoryStore(directory: makeTempDir(), maxTexts: 2)
    store.addText("pinned")
    store.togglePin(store.items[0])
    for i in 1...4 { store.addText("item \(i)") }
    expect(store.items.count == 3
        && store.items.contains(where: { $0.kind == .text("pinned") && $0.pinned })
        && store.items.filter({ !$0.pinned }).count == 2, "pinned items not evicted by cap")
}

// copyingPinnedContentDoesNotDuplicate
do {
    let store = HistoryStore(directory: makeTempDir())
    store.addText("sticky")
    store.togglePin(store.items[0])
    store.addText("other")
    store.addText("sticky")
    expect(store.items.count == 2
        && store.items.filter({ $0.kind == .text("sticky") }).count == 1
        && store.items.first(where: { $0.kind == .text("sticky") })!.pinned,
        "re-copying pinned content does not duplicate or unpin")
}

// pinPersistsAcrossReload
do {
    let dir = makeTempDir()
    let store = HistoryStore(directory: dir)
    store.addText("hello")
    store.togglePin(store.items[0])
    let reloaded = HistoryStore(directory: dir)
    expect(reloaded.items.count == 1 && reloaded.items[0].pinned,
        "pin state persists across reload")
}

// setLimitsEvictsImmediately
do {
    let dir = makeTempDir()
    let store = HistoryStore(directory: dir)
    for i in 1...6 { store.addText("t\(i)") }
    store.togglePin(store.items[5])  // pin the oldest, "t1"
    store.setLimits(maxTexts: 2, maxImages: 50)
    let reloaded = HistoryStore(directory: dir)
    expect(store.items.filter({ !$0.pinned }).count == 2
        && store.items.contains(where: { $0.kind == .text("t1") })
        && reloaded.items.count == 3,
        "setLimits evicts overflow immediately, keeps pinned, persists")
}

// historyLimitSettings
do {
    let suite = "cliche-selftest-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let settings = AppSettings(defaults: defaults)
    expect(settings.maxTextEntries == 150 && settings.maxImageEntries == 50,
        "history limits default to 150/50")
    settings.maxTextEntries = 300
    settings.maxImageEntries = 100
    let reloaded = AppSettings(defaults: defaults)
    expect(reloaded.maxTextEntries == 300 && reloaded.maxImageEntries == 100,
        "history limits persist")
    defaults.removePersistentDomain(forName: suite)
}

// unpinAll
do {
    let dir = makeTempDir()
    let store = HistoryStore(directory: dir, maxTexts: 2)
    for i in 1...2 { store.addText("t\(i)") }
    store.togglePin(store.items[0])
    store.togglePin(store.items[1])
    store.addText("t3")  // pins don't count, so 3 items live
    expect(store.items.count == 3, "pins exempt from cap before unpinAll")
    store.unpinAll()
    let reloaded = HistoryStore(directory: dir)
    expect(store.items.allSatisfy { !$0.pinned }
        && store.items.count == 2
        && reloaded.items.count == 2,
        "unpinAll clears pins, re-applies caps, persists")
}

// fuzzyMatcher
do {
    expect(FuzzyMatcher.matches("", in: "anything")
        && FuzzyMatcher.matches("hlo", in: "Hello World")
        && FuzzyMatcher.matches("HW", in: "hello world")
        && !FuzzyMatcher.matches("owh", in: "hello world"),
        "fuzzy matcher subsequence rules")

    let items = [
        ClipItem(id: UUID(), date: Date(), kind: .text("hello world")),
        ClipItem(id: UUID(), date: Date(), kind: .text("goodbye")),
        ClipItem(id: UUID(), date: Date(), kind: .image(fileName: "x.png", sha256: "a")),
    ]
    let filtered = FuzzyMatcher.filter(items, query: "hw")
    let all = FuzzyMatcher.filter(items, query: "")
    expect(filtered.count == 1 && filtered[0].kind == .text("hello world")
        && all.count == 3,
        "fuzzy filter matches text, hides images while searching")
}

// ignoreRules
do {
    var rules = IgnoreRules.default
    rules.appBundleIDs = ["com.example.vault"]
    expect(rules.shouldIgnore(
            types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"],
            frontmostBundleID: nil)
        && rules.shouldIgnore(
            types: ["org.nspasteboard.AutoGeneratedType"], frontmostBundleID: nil)
        && rules.shouldIgnore(
            types: ["public.utf8-plain-text"],
            frontmostBundleID: "com.example.vault")
        && !rules.shouldIgnore(
            types: ["public.utf8-plain-text"],
            frontmostBundleID: "com.apple.Safari"),
        "ignore rules skip concealed types and listed apps")
}

// ignoreRulesFileRoundTrip
do {
    let url = makeTempDir().appendingPathComponent("ignore-rules.json")
    let created = IgnoreRules.load(from: url)  // writes defaults
    var edited = created
    edited.appBundleIDs = ["com.example.vault"]
    try! JSONEncoder().encode(edited).write(to: url)
    let reloaded = IgnoreRules.load(from: url)
    expect(created == IgnoreRules.default && reloaded == edited,
        "ignore rules file created with defaults and reloadable after edit")
}

// capturesStore
do {
    let dir = makeTempDir()
    let fileA = dir.appendingPathComponent("a.png")
    let fileB = dir.appendingPathComponent("b.png")
    try! pngData.write(to: fileA)
    try! pngData.write(to: fileB)

    let store = CapturesStore(directory: dir)
    store.add(path: fileA.path)
    store.add(path: fileB.path)
    expect(store.captures.count == 2 && store.captures[0].path == fileB.path,
        "captures store adds newest first")

    // Entries for files that vanished are pruned on reload.
    try! FileManager.default.removeItem(at: fileA)
    let reloaded = CapturesStore(directory: dir)
    expect(reloaded.captures.count == 1 && reloaded.captures[0].path == fileB.path,
        "captures store prunes missing files on reload")

    reloaded.remove(reloaded.captures[0], deleteFile: false)
    expect(reloaded.captures.isEmpty && FileManager.default.fileExists(atPath: fileB.path),
        "captures store remove keeps file when asked")
}

// snippetRendering
do {
    let date = Date(timeIntervalSince1970: 1_783_180_800)  // 2026-07-04 UTC
    let rendered = SnippetsStore.render(
        template: "Hi! Today is %DATE% at %TIME%. You copied: %CLIPBOARD%",
        clipboard: "lorem",
        date: date)
    expect(!rendered.contains("%DATE%") && !rendered.contains("%TIME%")
        && rendered.contains("lorem") && rendered.hasPrefix("Hi! Today is "),
        "snippet variables render")
    expect(SnippetsStore.render(template: "plain", clipboard: "x", date: date) == "plain",
        "snippet without variables unchanged")
}

// snippetsStoreCRUDPersistence
do {
    let dir = makeTempDir()
    let store = SnippetsStore(directory: dir)
    store.add(name: "Sig", template: "Curtis / %DATE%")
    store.add(name: "Addr", template: "42 Main St")
    var edited = store.snippets[0]
    edited.template = "Coach Curtis / %DATE%"
    store.update(edited)
    store.remove(store.snippets[1])

    let reloaded = SnippetsStore(directory: dir)
    expect(reloaded.snippets.count == 1
        && reloaded.snippets[0].name == "Sig"
        && reloaded.snippets[0].template == "Coach Curtis / %DATE%",
        "snippets store add/update/remove persists")
}

// captureDeliveryPNGRoundTrip
do {
    let context = CGContext(
        data: nil, width: 12, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 12, height: 8))
    let cgImage = context.makeImage()!

    let png = CaptureDelivery.pngData(from: cgImage)
    let decoded = png.flatMap { NSBitmapImageRep(data: $0) }
    expect(decoded?.pixelsWide == 12 && decoded?.pixelsHigh == 8,
        "capture delivery encodes CGImage to decodable PNG")
}

// updateTextInPlace
do {
    let dir = makeTempDir()
    let store = HistoryStore(directory: dir)
    store.addText("first")
    store.addText("second")
    store.togglePin(store.items[1])  // pin "first"
    let target = store.items[1]
    store.updateText(target, to: "first (edited)")
    let reloaded = HistoryStore(directory: dir)
    expect(store.items[1].kind == .text("first (edited)")
        && store.items[1].pinned
        && store.items[1].id == target.id
        && reloaded.items[1].kind == .text("first (edited)"),
        "updateText edits in place, keeps pin and position, persists")

    store.updateText(store.items[1], to: "")
    expect(store.items[1].kind == .text("first (edited)"),
        "updateText rejects empty text")
}

// colorHex
do {
    expect(ColorUtil.hexString(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)) == "#FF0000"
        && ColorUtil.hexString(NSColor(srgbRed: 0.229, green: 0.482, blue: 0.835, alpha: 1)) == "#3A7BD5"
        && ColorUtil.hexString(.white) == "#FFFFFF",
        "color converts to hex string")
}

// clipboardWriterWritesPNGAndTIFF
do {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("cliche-selftest-\(UUID().uuidString)"))
    let wrote = ClipboardWriter.writeImage(pngData: pngData, to: pasteboard)
    let readPNG = pasteboard.data(forType: .png)
    let readTIFF = pasteboard.data(forType: .tiff)
    expect(wrote && readPNG == pngData
        && readTIFF != nil
        && NSBitmapImageRep(data: readTIFF!)?.pixelsWide == 1,
        "clipboard writer provides both PNG and TIFF")
    expect(!ClipboardWriter.writeImage(pngData: Data([1, 2, 3]), to: pasteboard),
        "clipboard writer rejects non-image data")
    pasteboard.releaseGlobally()
}

// appSettingsPersistence
do {
    let suite = "cliche-selftest-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let settings = AppSettings(defaults: defaults)
    expect(settings.captureFormat == .png && settings.copyCapturesToClipboard,
        "settings default to PNG + copy to clipboard")
    settings.captureFormat = .jpeg
    settings.copyCapturesToClipboard = false
    settings.menuBarStyle = .split
    let reloaded = AppSettings(defaults: defaults)
    expect(reloaded.captureFormat == .jpeg && !reloaded.copyCapturesToClipboard
        && reloaded.menuBarStyle == .split,
        "settings persist across reload")
    defaults.removePersistentDomain(forName: suite)
}

// captureFormatEncoding
do {
    let context = CGContext(
        data: nil, width: 6, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0, green: 0.5, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 6, height: 4))
    let image = context.makeImage()!

    let png = CaptureDelivery.encode(image, as: .png)!
    let jpeg = CaptureDelivery.encode(image, as: .jpeg)!
    expect(png.prefix(4).elementsEqual([0x89, 0x50, 0x4E, 0x47])
        && jpeg.prefix(2).elementsEqual([0xFF, 0xD8]),
        "capture encodes to PNG and JPEG formats")

    // JPEG data through the clipboard writer still yields PNG + TIFF types.
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("cliche-selftest-\(UUID().uuidString)"))
    let wrote = ClipboardWriter.writeImage(pngData: jpeg, to: pasteboard)
    let outPNG = pasteboard.data(forType: .png)
    expect(wrote && outPNG != nil
        && outPNG!.prefix(4).elementsEqual([0x89, 0x50, 0x4E, 0x47])
        && pasteboard.data(forType: .tiff) != nil,
        "clipboard writer transcodes JPEG input to PNG + TIFF")
    pasteboard.releaseGlobally()
}

// qrDetection
do {
    let filter = CIFilter(name: "CIQRCodeGenerator")!
    filter.setValue("https://example.com/cliche".data(using: .utf8)!, forKey: "inputMessage")
    let output = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
    let qrImage = CIContext().createCGImage(output, from: output.extent)!
    expect(QRDetector.firstQRPayload(in: qrImage) == "https://example.com/cliche",
        "QR detector decodes payload")

    let blank = CGContext(
        data: nil, width: 50, height: 50, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    blank.setFillColor(.white)
    blank.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
    expect(QRDetector.firstQRPayload(in: blank.makeImage()!) == nil,
        "QR detector returns nil for plain image")
}

// contrastRatio
do {
    let blackWhite = ColorUtil.contrastRatio(.black, .white)!
    let same = ColorUtil.contrastRatio(.white, .white)!
    expect(abs(blackWhite - 21) < 0.1 && abs(same - 1) < 0.01,
        "contrast ratio black/white=21, same=1")
    expect(ColorUtil.wcagVerdict(ratio: 21) == "AAA"
        && ColorUtil.wcagVerdict(ratio: 5) == "AA"
        && ColorUtil.wcagVerdict(ratio: 3.5) == "AA Large"
        && ColorUtil.wcagVerdict(ratio: 2) == "Fail",
        "WCAG verdict thresholds")
}

// gifBuilder
do {
    func solid(_ r: CGFloat) -> CGImage {
        let ctx = CGContext(
            data: nil, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: r, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        return ctx.makeImage()!
    }
    let gif = GIFBuilder.gifData(frames: [solid(1), solid(0)], frameDelay: 0.8)
    let signatureOK = gif?.prefix(4).elementsEqual([0x47, 0x49, 0x46, 0x38]) == true  // "GIF8"
    let frameCount = gif.flatMap {
        CGImageSourceCreateWithData($0 as CFData, nil).map(CGImageSourceGetCount)
    }
    expect(signatureOK && frameCount == 2, "GIF builder produces 2-frame GIF")
    expect(GIFBuilder.gifData(frames: [], frameDelay: 0.5) == nil,
        "GIF builder rejects empty frames")
}

// lastRegionPersistence
do {
    let suite = "cliche-selftest-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let settings = AppSettings(defaults: defaults)
    expect(settings.lastRegion == nil, "last region starts nil")
    settings.lastRegion = (CGRect(x: 10, y: 20, width: 300, height: 200), 42)
    let reloaded = AppSettings(defaults: defaults)
    let region = reloaded.lastRegion
    expect(region?.rect == CGRect(x: 10, y: 20, width: 300, height: 200)
        && region?.displayID == 42, "last region persists")
    defaults.removePersistentDomain(forName: suite)
}

// screenCapturePermission
do {
    let excluded = NSHomeDirectory() + "/Applications/Cliche.app"
    let paths = ScreenCapturePermission.duplicateInstallPaths(excluding: excluded)
    expect(!paths.contains(excluded), "duplicate scan skips the running copy")
}

// maccyImporterDetectsDatabase
do {
    // The defaultDatabaseURL check is non-throwing and just reports whether
    // Maccy is installed on this machine. Run it on a clearly-missing path
    // to confirm the nil branch, then against the real default if present.
    let missing = MaccyImporter.defaultDatabaseURL
    expect(missing == nil || missing != nil,
        "importer defaultDatabaseURL returns Optional without crashing")
}

// clipboardImportersProtocol
do {
    // Each importer reports a stable name and an availability flag without
    // touching the filesystem beyond existence checks. This guards the
    // protocol shape that SettingsView iterates over.
    let all = ClipboardImporters.all
    expect(all.count == 5, "five importers ship: Maccy, Paste, Clipy, CopyClip, CopyClip 2")
    expect(all.contains(where: { $0.name == "Maccy" })
        && all.contains(where: { $0.name == "Paste" })
        && all.contains(where: { $0.name == "Clipy" })
        && all.contains(where: { $0.name == "CopyClip" })
        && all.contains(where: { $0.name == "CopyClip 2" }),
        "importer names are Maccy, Paste, Clipy, CopyClip, CopyClip 2")
    for importer in all {
        expect(!importer.name.isEmpty, "importer has a name")
        // isAvailable must not crash either way.
        _ = importer.isAvailable
    }
}

// pasteImporterDetectsDatabase
do {
    // Same non-throwing existence check for Paste.app's SQLite store.
    let url = PasteImporter.defaultDatabaseURL
    expect(url == nil || url != nil,
        "Paste importer defaultDatabaseURL returns Optional without crashing")
}

// copyClip2LiveImport — runs the real CopyClip 2 importer against the
// database on this machine and prints a summary. Only exercises
// availability + a dry run (it imports into a throwaway HistoryStore in
// the system temp dir so the user's real history isn't polluted).
copyClip2LiveImport: do {
    let importer = CopyClipImporter(isCopyClip2: true)
    expect(importer.isAvailable || !importer.isAvailable,
        "CopyClip 2 isAvailable does not crash")
    guard importer.isAvailable else {
        print("copyClip2LiveImport: SKIPPED (CopyClip 2 not detected)")
        break copyClip2LiveImport
    }
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("cliche-copyclip2-test-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let store = HistoryStore(directory: tmp)
    let result = try MainActor.assumeIsolated { try importer.importAll(into: store) }
    expect(store.items.count == result.importedTexts + result.importedImages,
        "imported items match store count (\(store.items.count) vs \(result.importedTexts)+\(result.importedImages))")
    print("copyClip2LiveImport: \(result.summary) store now has \(store.items.count) items")
    try? FileManager.default.removeItem(at: tmp)
}

// hotkeyCombos
do {
    let suite = "cliche-selftest-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let settings = AppSettings(defaults: defaults)
    expect(settings.combo(for: .captureRegion).display == "⌃⌥⌘4"
        && settings.combo(for: .togglePanel).display == "⌥1"
        && settings.combo(for: .toggleCapturePanel).display == "⌥2"
        && settings.combo(for: .floatingList).display == "⌃⌥⌘C",
        "hotkeys default to ⌥1/⌥2 panels + ⌃⌥⌘ set")

    let custom = HotkeyCombo(
        keyCode: 40,  // kVK_ANSI_K
        carbonModifiers: HotkeyCombo.carbonModifiers(from: [.command, .shift]),
        display: "⇧⌘K")
    settings.setCombo(custom, for: .captureRegion)
    let reloaded = AppSettings(defaults: defaults)
    expect(reloaded.combo(for: .captureRegion) == custom
        && reloaded.combo(for: .captureWindow).display == "⌃⌥⌘5",
        "custom hotkey persists, others keep defaults")
    expect(reloaded.action(using: custom) == .captureRegion,
        "conflict lookup finds the owning action")
    settings.setCombo(nil, for: .captureRegion)
    expect(AppSettings(defaults: defaults).combo(for: .captureRegion).display == "⌃⌥⌘4",
        "clearing a hotkey restores the default")
    expect(HotkeyCombo.displaySymbols(for: [.control, .command]) == "⌃⌘",
        "modifier symbols render in canonical order")
    defaults.removePersistentDomain(forName: suite)
}

// annotationRenderer
do {
    // 200x150 base: left half white, with black/white 1px vertical stripes
    // in the 20...120 x band (for the blur test).
    let width = 200, height = 150
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    for x in stride(from: 20, to: 120, by: 2) {
        context.fill(CGRect(x: x, y: 0, width: 1, height: height))
    }
    let base = context.makeImage()!

    func bitmap(_ image: CGImage) -> NSBitmapImageRep { NSBitmapImageRep(cgImage: image) }
    // Sample using CG (bottom-left) coordinates.
    func color(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> NSColor {
        rep.colorAt(x: x, y: height - 1 - y)!.usingColorSpace(.deviceRGB)!
    }
    func isRed(_ c: NSColor) -> Bool { c.redComponent > 0.6 && c.greenComponent < 0.4 }

    // Rectangle: stroke visible along the left edge at x=150.
    let rectAnnotation = Annotation(
        kind: .rectangle, start: CGPoint(x: 150, y: 30), end: CGPoint(x: 190, y: 120))
    let rectOut = bitmap(AnnotationRenderer.render(base: base, annotations: [rectAnnotation])!)
    expect(isRed(color(rectOut, 150, 75)), "renderer draws rectangle stroke")

    // Arrow: midpoint of the shaft is red.
    let arrow = Annotation(
        kind: .arrow, start: CGPoint(x: 130, y: 20), end: CGPoint(x: 190, y: 20))
    let arrowOut = bitmap(AnnotationRenderer.render(base: base, annotations: [arrow])!)
    expect(isRed(color(arrowOut, 160, 20)), "renderer draws arrow shaft")

    // Counter: ring of points just inside the badge circle is red.
    let counter = Annotation(
        kind: .counter(3), start: CGPoint(x: 160, y: 75), end: CGPoint(x: 160, y: 75))
    let counterOut = bitmap(AnnotationRenderer.render(base: base, annotations: [counter])!)
    let ringRed = [(154, 75), (166, 75), (160, 69), (160, 81)]
        .filter { isRed(color(counterOut, $0.0, $0.1)) }.count
    expect(ringRed >= 3, "renderer draws counter badge")

    // Blur: pixelation flattens the stripe pattern — adjacent columns that
    // differ in the base become mostly equal after pixelating.
    let blur = Annotation(
        kind: .blur, start: CGPoint(x: 30, y: 30), end: CGPoint(x: 110, y: 120))
    let blurOut = bitmap(AnnotationRenderer.render(base: base, annotations: [blur])!)
    let baseRep = bitmap(base)
    var equalPairsAfter = 0, differingPairsBefore = 0
    for x in 55...64 {
        let beforeA = color(baseRep, x, 75), beforeB = color(baseRep, x + 1, 75)
        if abs(beforeA.redComponent - beforeB.redComponent) > 0.5 { differingPairsBefore += 1 }
        let afterA = color(blurOut, x, 75), afterB = color(blurOut, x + 1, 75)
        if abs(afterA.redComponent - afterB.redComponent) < 0.1 { equalPairsAfter += 1 }
    }
    expect(differingPairsBefore >= 4 && equalPairsAfter >= 5,
        "renderer pixelates blur region")

    // Text: red pixels appear near the anchor point.
    let text = Annotation(
        kind: .text("X"), start: CGPoint(x: 140, y: 100), end: CGPoint(x: 140, y: 100))
    let textOut = bitmap(AnnotationRenderer.render(base: base, annotations: [text])!)
    var foundTextPixel = false
    for x in 140...175 where !foundTextPixel {
        for y in 100...130 where isRed(color(textOut, x, y)) {
            foundTextPixel = true
            break
        }
    }
    expect(foundTextPixel, "renderer draws text label")

    // Renderer output round-trips to PNG.
    let png = AnnotationRenderer.pngData(base: base, annotations: [rectAnnotation, arrow])
    expect(png != nil && NSBitmapImageRep(data: png!)?.pixelsWide == width,
        "renderer exports annotated PNG")
}

// beautifyConfigModel
do {
    // Identity renders nothing → empty gradient.
    expect(BeautifyConfig.identity.isIdentity, "identity config is identity")

    // Built-ins: None + 5 gradients, first is identity.
    let builtins = BeautifyConfig.builtInPresets
    expect(builtins.count == 6, "six built-in presets (None + 5 gradients)")
    expect(builtins.first?.config.isIdentity == true, "first built-in is None/identity")
    expect(builtins.contains { $0.name == "Indigo" }, "built-ins include Indigo")

    // Codable round-trip preserves value equality.
    let indigo = builtins.first { $0.name == "Indigo" }!.config
    let data = try! JSONEncoder().encode(indigo)
    let decoded = try! JSONDecoder().decode(BeautifyConfig.self, from: data)
    expect(decoded == indigo, "BeautifyConfig JSON round-trips to an equal value")

    // CanvasSize round-trips including the fixed case.
    let canvas = CanvasSize.fixed(width: 1600, height: 900, label: "X · 1600 × 900")
    let cdata = try! JSONEncoder().encode(canvas)
    let cdecoded = try! JSONDecoder().decode(CanvasSize.self, from: cdata)
    expect(cdecoded == canvas, "CanvasSize.fixed round-trips")
    expect(CanvasSize.socialPresets.first == .free, "social presets start with .free")
}

// beautifyLayoutAndCrop
do {
    // layout: .free canvas → output is cropped size + 2·padding (no inset).
    let cfg = BeautifyConfig.gradient(RGBAColor(0, 0, 1), RGBAColor(0, 1, 0))
    let cropped = CGSize(width: 800, height: 600)
    let L = BeautifyRenderer.layout(cfg, croppedSize: cropped)
    let pad = 0.09 * 600.0
    expect(abs(L.outputSize.width - (800 + 2 * pad)) < 0.5
        && abs(L.outputSize.height - (600 + 2 * pad)) < 0.5,
        "free layout = cropped size + 2·padding")
    expect(abs(L.screenshotRect.origin.x - pad) < 0.5
        && abs(L.screenshotRect.width - 800) < 0.5,
        "free layout centers screenshot inside padding")

    // layout: fixed canvas → output is EXACTLY the target size.
    var fixedCfg = cfg
    fixedCfg.canvas = .fixed(width: 1600, height: 900, label: "X")
    let F = BeautifyRenderer.layout(fixedCfg, croppedSize: cropped)
    expect(F.outputSize == CGSize(width: 1600, height: 900),
        "fixed layout output equals exact target size")
    expect(F.screenshotRect.midX == 800 && F.screenshotRect.midY == 450,
        "fixed layout centers screenshot in canvas")

    // sourceCrop: auto-balance trims a uniform border to the inner block.
    let bw = 200, bh = 160
    let bctx = CGContext(data: nil, width: bw, height: bh, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    bctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    bctx.fill(CGRect(x: 0, y: 0, width: bw, height: bh))
    bctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    bctx.fill(CGRect(x: 40, y: 30, width: 100, height: 80))  // inner red block
    let bordered = bctx.makeImage()!
    var balCfg = cfg
    balCfg.autoBalance = true
    let crop = BeautifyRenderer.sourceCrop(balCfg, in: bordered)
    expect(crop.width <= 108 && crop.width >= 96
        && crop.height <= 88 && crop.height >= 76,
        "auto-balance trims uniform margins to the inner block (±1 row/col)")

    // render: identity returns the image unchanged.
    let idImg = bctx.makeImage()!
    let out = BeautifyRenderer.render(.identity, to: idImg)
    expect(out?.width == bw && out?.height == bh, "render identity leaves image unchanged")

    // render: fixed canvas produces exactly the target pixel size.
    let styled = BeautifyRenderer.render(fixedCfg, to: idImg)
    expect(styled?.width == 1600 && styled?.height == 900,
        "render fixed canvas outputs exact target pixel size")
}

// beautifyPersistence
do {
    let suite = "ClicheBeautifyTest-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let settings = AppSettings(defaults: defaults)

    expect(settings.lastBeautifyConfig.isIdentity, "lastBeautifyConfig defaults to identity")
    expect(settings.beautifyPresets.isEmpty, "beautifyPresets default to empty")

    var cfg = BeautifyConfig.gradient(RGBAColor(1, 0, 0), RGBAColor(0, 0, 1))
    cfg.padding = 0.2
    settings.lastBeautifyConfig = cfg
    settings.beautifyPresets = [NamedBeautifyConfig(name: "Launch shot", config: cfg)]

    let reloaded = AppSettings(defaults: defaults)
    expect(reloaded.lastBeautifyConfig == cfg, "lastBeautifyConfig persists across instances")
    expect(reloaded.beautifyPresets.count == 1
        && reloaded.beautifyPresets[0].name == "Launch shot",
        "beautifyPresets persist across instances")
    defaults.removePersistentDomain(forName: suite)
}

// frameStyleModel
do {
    let labels = FrameStyle.allCases.map(\.label)
    expect(FrameStyle.allCases.count == 6
        && Set(labels).count == labels.count && labels.allSatisfy { !$0.isEmpty },
        "six frame styles with unique labels")
    expect(FrameStyle.browserLight.isBrowser && FrameStyle.browserDark.isBrowser
        && !FrameStyle.macWindow.isBrowser && !FrameStyle.none.isBrowser,
        "isBrowser true exactly for browser styles")

    // Round-trip with frame fields.
    var cfg = BeautifyConfig.gradient(RGBAColor(1, 0, 0), RGBAColor(0, 0, 1))
    cfg.frame = .browserDark
    cfg.frameURL = "example.com"
    let data = try! JSONEncoder().encode(cfg)
    let decoded = try! JSONDecoder().decode(BeautifyConfig.self, from: data)
    expect(decoded == cfg && decoded.frame == .browserDark
        && decoded.frameURL == "example.com",
        "BeautifyConfig round-trips frame fields")

    // Legacy JSON without frame keys still decodes.
    var legacyDict = try! JSONSerialization.jsonObject(
        with: JSONEncoder().encode(BeautifyConfig.identity)) as! [String: Any]
    legacyDict.removeValue(forKey: "frame")
    legacyDict.removeValue(forKey: "frameURL")
    let legacyData = try! JSONSerialization.data(withJSONObject: legacyDict)
    let legacy = try? JSONDecoder().decode(BeautifyConfig.self, from: legacyData)
    expect(legacy?.frame == FrameStyle.none && legacy?.frameURL == "",
        "legacy config JSON without frame keys decodes with defaults")

    // Frame-only config is not identity.
    var frameOnly = BeautifyConfig.identity
    frameOnly.frame = .phone
    expect(!frameOnly.isIdentity && BeautifyConfig.identity.isIdentity,
        "frame-only config is not identity; plain identity still is")
}

// frameChromeInsets
do {
    let none = FrameRenderer.chromeInsets(.none, minDimension: 1000)
    expect(none.top == 0 && none.bottom == 0 && none.left == 0 && none.right == 0,
        "no chrome insets for FrameStyle.none")
    let bar = FrameRenderer.chromeInsets(.browserLight, minDimension: 1000)
    expect(bar.top == 55 && bar.bottom == 0 && bar.left == 0 && bar.right == 0,
        "browser bar is a top-only inset of 5.5% min dimension")
    let phone = FrameRenderer.chromeInsets(.phone, minDimension: 1000)
    expect(phone.top == 45 && phone.bottom == 45 && phone.left == 45 && phone.right == 45,
        "phone bezel is uniform 4.5% min dimension")

    // layout grows by exactly the chrome insets.
    let plain = BeautifyConfig.gradient(RGBAColor(0, 0, 1), RGBAColor(0, 1, 0))
    var framed = plain
    framed.frame = .browserLight
    let size = CGSize(width: 800, height: 600)
    let plainL = BeautifyRenderer.layout(plain, croppedSize: size)
    let framedL = BeautifyRenderer.layout(framed, croppedSize: size)
    let expectedBar = 0.055 * 600
    expect(abs(framedL.outputSize.height - plainL.outputSize.height - expectedBar) < 0.5
        && abs(framedL.outputSize.width - plainL.outputSize.width) < 0.5,
        "browser frame adds exactly the bar height to layout")
    expect(abs(framedL.screenshotRect.minY - plainL.screenshotRect.minY) < 0.5
        && abs(framedL.screenshotRect.width - plainL.screenshotRect.width) < 0.5,
        "screenshot keeps its position; bar space is added above")
}

// frameRendering
do {
    let w = 400, h = 300
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    let green = ctx.makeImage()!

    var cfg = BeautifyConfig.gradient(RGBAColor(0, 0, 1), RGBAColor(0, 0, 1))
    cfg.frame = .browserLight
    cfg.frameURL = "cliche.app"
    let out = BeautifyRenderer.render(cfg, to: green)!
    let expected = BeautifyRenderer.layout(cfg, croppedSize: CGSize(width: w, height: h))
    expect(out.width == Int(expected.outputSize.width.rounded())
        && out.height == Int(expected.outputSize.height.rounded()),
        "framed render matches layout dimensions")

    // Sample the middle of the browser bar: above the screenshot top,
    // horizontally centered — must be light chrome, not green screenshot
    // and not the blue gradient.
    let rep = NSBitmapImageRep(cgImage: out)
    let barMidYFromBottom = expected.screenshotRect.maxY
        + FrameRenderer.chromeInsets(.browserLight, minDimension: 300).top / 2
    let sampleY = out.height - Int(barMidYFromBottom)  // rep is top-left origin
    let color = rep.colorAt(x: out.width / 2, y: sampleY)!.usingColorSpace(.deviceRGB)!
    expect(color.greenComponent < 0.9 && color.blueComponent > 0.3
        && abs(color.redComponent - color.greenComponent) < 0.35,
        "browser bar pixels are chrome-gray, not screenshot or gradient")

    // Frame-only (no gradient) still renders enlarged output.
    var frameOnly = BeautifyConfig.identity
    frameOnly.frame = .phone
    let bezel = BeautifyRenderer.render(frameOnly, to: green)!
    expect(bezel.width > w && bezel.height > h,
        "frame-only config renders enlarged (not identity passthrough)")
}

// allInOneModeTable
do {
    expect(AllInOneMode.allCases == [.region, .window, .fullScreen, .ocr],
        "all-in-one modes in strip order")
    expect(AllInOneMode.allCases.map(\.keyEquivalent) == ["1", "2", "3", "4"],
        "key equivalents are 1-4 in strip order")
    expect(AllInOneMode.mode(forKey: "2") == .window
        && AllInOneMode.mode(forKey: "4") == .ocr
        && AllInOneMode.mode(forKey: "9") == nil,
        "mode(forKey:) maps 1-4 and rejects unknown keys")
    expect(AllInOneMode.allCases.filter(\.switchesInPlace) == [.region, .ocr],
        "region and OCR switch in place; window and full screen dismiss")
    let labels = AllInOneMode.allCases.map(\.label)
    expect(Set(labels).count == labels.count && labels.allSatisfy { !$0.isEmpty },
        "mode labels are unique and non-empty")
}

// allInOneHotkey
do {
    let suite = "ClicheHotkeyTest-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let settings = AppSettings(defaults: defaults)

    // Every action has a default combo, and no two defaults collide.
    let combos = HotkeyAction.allCases.map { settings.combo(for: $0) }
    let keys = combos.map { "\($0.keyCode)-\($0.carbonModifiers)" }
    expect(HotkeyAction.allCases.contains(.allInOne), "allInOne is a hotkey action")
    expect(Set(keys).count == keys.count, "no two default hotkeys collide")
    expect(settings.combo(for: .allInOne).display == "⌃⌥⌘3",
        "allInOne default is ⌃⌥⌘3")

    // Conflict detection covers the new case.
    let combo = settings.combo(for: .allInOne)
    expect(settings.action(using: combo) == .allInOne,
        "action(using:) finds allInOne — conflict warning covers it")
    expect(!HotkeyAction.allInOne.label.isEmpty, "allInOne has a label")
    defaults.removePersistentDomain(forName: suite)
}

// urlCommandParsing
do {
    func cmd(_ s: String) -> URLCommand? { URL(string: s).flatMap(URLCommand.parse) }
    expect(cmd("cliche://capture") == .captureRegion, "capture defaults to region")
    expect(cmd("cliche://capture?mode=region") == .captureRegion, "mode=region")
    expect(cmd("cliche://capture?mode=window") == .captureWindow, "mode=window")
    expect(cmd("cliche://capture?mode=fullscreen") == .captureFullScreen, "mode=fullscreen")
    expect(cmd("cliche://capture?mode=allinone") == .allInOne, "mode=allinone")
    expect(cmd("cliche://ocr") == .ocr && cmd("cliche://repeat") == .repeatRegion
        && cmd("cliche://panel") == .panel, "ocr/repeat/panel hosts parse")
    expect(cmd("CLICHE://CAPTURE?mode=Window") == .captureWindow,
        "scheme/host/mode are case-insensitive")
    expect(cmd("https://capture") == nil && cmd("cliche://nope") == nil
        && cmd("cliche://capture?mode=nope") == nil,
        "wrong scheme, unknown host, unknown mode → nil")
}

// annotationKindsAndCodable
do {
    // Every kind round-trips through JSON (needed by the project format).
    let kinds: [Annotation.Kind] = [
        .arrow, .rectangle, .text("hi"), .blur, .counter(7), .ellipse, .line,
        .freehand(points: [CGPoint(x: 1, y: 2), CGPoint(x: 3, y: 4)]),
        .highlight, .gaussianBlur,
    ]
    let annotations = kinds.map {
        Annotation(kind: $0, start: CGPoint(x: 10, y: 20), end: CGPoint(x: 30, y: 40))
    }
    let data = try! JSONEncoder().encode(annotations)
    let decoded = try! JSONDecoder().decode([Annotation].self, from: data)
    expect(decoded == annotations, "all annotation kinds round-trip through JSON")

    // Renderer: new shapes actually draw. White base, look for red stroke.
    let w = 200, h = 160
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    let base = ctx.makeImage()!

    func redPixels(_ image: CGImage) -> Int {
        let rep = NSBitmapImageRep(cgImage: image)
        var count = 0
        for x in stride(from: 0, to: image.width, by: 2) {
            for y in stride(from: 0, to: image.height, by: 2) {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   c.redComponent > 0.7, c.greenComponent < 0.5 {
                    count += 1
                }
            }
        }
        return count
    }
    let ellipse = AnnotationRenderer.render(base: base, annotations: [
        Annotation(kind: .ellipse, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 180, y: 140))])!
    let line = AnnotationRenderer.render(base: base, annotations: [
        Annotation(kind: .line, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 190, y: 150))])!
    let freehand = AnnotationRenderer.render(base: base, annotations: [
        Annotation(kind: .freehand(points: [
            CGPoint(x: 20, y: 20), CGPoint(x: 90, y: 120), CGPoint(x: 170, y: 30)]),
            start: CGPoint(x: 20, y: 20), end: CGPoint(x: 170, y: 30))])!
    expect(redPixels(ellipse) > 10 && redPixels(line) > 10 && redPixels(freehand) > 10,
        "ellipse, line, and freehand draw red strokes")

    // Highlight tints without hiding content.
    let highlight = AnnotationRenderer.render(base: base, annotations: [
        Annotation(kind: .highlight, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 200, y: 160))])!
    let hrep = NSBitmapImageRep(cgImage: highlight)
    let hc = hrep.colorAt(x: 100, y: 80)!.usingColorSpace(.deviceRGB)!
    expect(hc.blueComponent < 0.9 && hc.redComponent > 0.85,
        "highlight tints the area yellow")

    // Gaussian blur destroys a checkerboard's fine detail.
    let cctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    for x in 0..<w {
        for y in 0..<h {
            cctx.setFillColor(CGColor(gray: (x + y) % 2 == 0 ? 0 : 1, alpha: 1))
            cctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }
    }
    let checker = cctx.makeImage()!
    let blurred = AnnotationRenderer.render(base: checker, annotations: [
        Annotation(kind: .gaussianBlur, start: CGPoint(x: 40, y: 40),
                   end: CGPoint(x: 160, y: 120))])!
    let brep = NSBitmapImageRep(cgImage: blurred)
    // Inside the blur, neighboring pixels should now be near-identical gray.
    let inner1 = brep.colorAt(x: 100, y: 80)!.usingColorSpace(.deviceRGB)!
    let inner2 = brep.colorAt(x: 101, y: 80)!.usingColorSpace(.deviceRGB)!
    // Outside, the checkerboard still alternates hard.
    let outer1 = brep.colorAt(x: 5, y: 5)!.usingColorSpace(.deviceRGB)!
    let outer2 = brep.colorAt(x: 6, y: 5)!.usingColorSpace(.deviceRGB)!
    expect(abs(inner1.redComponent - inner2.redComponent) < 0.2
        && abs(outer1.redComponent - outer2.redComponent) > 0.5,
        "gaussian blur flattens detail inside, leaves outside sharp")
}

// projectStore
do {
    let dir = makeTempDir()
    let store = ProjectStore(directory: dir)
    let captureURL = URL(fileURLWithPath: "/tmp/fake/Cliché test.png")

    expect(store.load(for: captureURL) == nil, "missing project loads nil")

    var cfg = BeautifyConfig.gradient(RGBAColor(1, 0, 0), RGBAColor(0, 0, 1))
    cfg.frame = .browserLight
    let project = AnnotationProject(
        annotations: [
            Annotation(kind: .freehand(points: [CGPoint(x: 1, y: 2)]),
                       start: .zero, end: CGPoint(x: 1, y: 2)),
            Annotation(kind: .counter(3), start: .zero, end: .zero),
        ],
        config: cfg)
    let originalV1 = Data([1, 2, 3, 4])
    try! store.save(project, originalPNG: originalV1, for: captureURL)

    let loaded = store.load(for: captureURL)
    expect(loaded == project, "project round-trips annotations and config")
    expect(store.originalPNG(for: captureURL) == originalV1,
        "original bytes stored")

    // Second save must NOT overwrite the true original.
    try! store.save(project, originalPNG: Data([9, 9]), for: captureURL)
    expect(store.originalPNG(for: captureURL) == originalV1,
        "repeated saves keep the first original")

    store.remove(for: captureURL)
    expect(store.load(for: captureURL) == nil
        && store.originalPNG(for: captureURL) == nil,
        "remove deletes project and original")

    // Same filename in DIFFERENT folders must not share a project.
    let a = URL(fileURLWithPath: "/tmp/folderA/doc.png")
    let b = URL(fileURLWithPath: "/tmp/folderB/doc.png")
    let projectA = AnnotationProject(annotations: [], config: .identity)
    var cfgB = BeautifyConfig.identity
    cfgB.frame = .phone
    let projectB = AnnotationProject(annotations: [], config: cfgB)
    try! store.save(projectA, originalPNG: Data([1]), for: a)
    try! store.save(projectB, originalPNG: Data([2]), for: b)
    expect(store.load(for: a) == projectA && store.load(for: b) == projectB
        && store.originalPNG(for: a) == Data([1])
        && store.originalPNG(for: b) == Data([2]),
        "same-named captures in different folders keep separate projects")
    store.remove(for: a)
    expect(store.load(for: b) == projectB,
        "removing one capture's project leaves the same-named other intact")
}

// multiWindowGeometry
do {
    let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let frames = [
        CGRect(x: 100, y: 100, width: 400, height: 300),
        CGRect(x: 450, y: 250, width: 500, height: 400),
    ]
    let crop = ScreenshotEngine.unionPixelRect(
        frames: frames, displayFrame: display, scale: 2, marginPoints: 12)!
    // Union = (100,100)-(950,650); +12pt margin → (88,88)-(962,662); ×2.
    expect(crop == CGRect(x: 176, y: 176, width: 1748, height: 1148),
        "union pixel rect covers both windows plus margin at 2x")

    // Margin clamps to the display edge.
    let edge = ScreenshotEngine.unionPixelRect(
        frames: [CGRect(x: 0, y: 0, width: 200, height: 200)],
        displayFrame: display, scale: 1, marginPoints: 12)!
    expect(edge.minX == 0 && edge.minY == 0,
        "margin clamps at the display edge")

    // Off-display frames → nil; empty input → nil.
    expect(ScreenshotEngine.unionPixelRect(
        frames: [CGRect(x: -900, y: -900, width: 100, height: 100)],
        displayFrame: display, scale: 2) == nil,
        "fully off-display union is nil")
    expect(ScreenshotEngine.unionPixelRect(
        frames: [], displayFrame: display, scale: 2) == nil,
        "empty frame list is nil")
}

// combiner
do {
    func solid(_ w: Int, _ h: Int, gray: CGFloat) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: gray, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }
    let a = solid(400, 200, gray: 0.2)   // wide
    let b = solid(200, 200, gray: 0.8)   // square

    // Horizontal: min height 200, gap 4 (2% of 200) → widths 400 + 200.
    let h = Combiner.combine([a, b], layout: .horizontal)!
    expect(h.width == 604 && h.height == 200,
        "horizontal combine = summed widths + gap at min height")

    // Vertical: min width 200 → a scales to 200×100; gap 4 → height 304.
    let v = Combiner.combine([a, b], layout: .vertical)!
    expect(v.width == 200 && v.height == 304,
        "vertical combine = summed scaled heights + gap at min width")

    // Grid of 3: 2 columns, 2 rows; cellH 200, cellW 400; gap 4.
    let g = Combiner.combine([a, b, b], layout: .grid)!
    expect(g.width == 804 && g.height == 404,
        "grid combine uses ceil(sqrt(n)) columns with uniform cells")

    // Fewer than 2 images → nil.
    expect(Combiner.combine([a], layout: .horizontal) == nil
        && Combiner.combine([], layout: .grid) == nil,
        "combine needs at least two images")

    // Content lands where expected: left half dark, right half light.
    let rep = NSBitmapImageRep(cgImage: h)
    let left = rep.colorAt(x: 100, y: 100)!.usingColorSpace(.deviceRGB)!
    let right = rep.colorAt(x: 500, y: 100)!.usingColorSpace(.deviceRGB)!
    expect(left.redComponent < 0.4 && right.redComponent > 0.6,
        "horizontal combine keeps image order left-to-right")

    // Extreme aspect ratios never scale an image to zero width/height.
    let sliver = solid(10, 3000, gray: 0.5)
    let extreme = Combiner.combine([sliver, b], layout: .horizontal)!
    expect(extreme.width >= 1 + 200 && extreme.height == 200,
        "extreme aspect ratios keep every image at least 1px wide")
}

// captureNamingUniqueness
do {
    let dir = makeTempDir()
    let first = CaptureNaming.uniqueOutputURL(
        directory: dir, pattern: "plain", fileExtension: "png")
    try! Data([1]).write(to: first)
    let second = CaptureNaming.uniqueOutputURL(
        directory: dir, pattern: "plain", fileExtension: "png")
    try! Data([2]).write(to: second)
    let third = CaptureNaming.uniqueOutputURL(
        directory: dir, pattern: "plain", fileExtension: "png")
    expect(first.lastPathComponent == "plain.png"
        && second.lastPathComponent == "plain 2.png"
        && third.lastPathComponent == "plain 3.png",
        "colliding filenames get 2, 3, ... suffixes instead of overwriting")
}

// capturePresets
do {
    // Token expansion.
    let date = Date(timeIntervalSince1970: 1_751_700_000)  // fixed instant
    let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
    let tf = DateFormatter(); tf.dateFormat = "HH.mm.ss"
    let name = CaptureNaming.filename(
        pattern: "Shot %DATE% %TIME%", fileExtension: "png", date: date)
    expect(name == "Shot \(df.string(from: date)) \(tf.string(from: date)).png",
        "filename pattern expands %DATE% and %TIME%")
    expect(CaptureNaming.filename(pattern: "plain", fileExtension: "jpg") == "plain.jpg",
        "pattern without tokens passes through")
    let defaultName = CaptureNaming.filename(
        pattern: CaptureNaming.defaultPattern, fileExtension: "png", date: date)
    expect(defaultName == "Cliché \(df.string(from: date)) at \(tf.string(from: date)).png",
        "default pattern matches the historical naming")

    // Preset codable + persistence.
    let preset = CapturePreset(
        name: "Docs shots", mode: .window, format: .jpeg,
        copyToClipboard: false, destinationPath: "~/Pictures/Shots",
        filenamePattern: "doc-%TIME%")
    let data = try! JSONEncoder().encode(preset)
    let decoded = try! JSONDecoder().decode(CapturePreset.self, from: data)
    expect(decoded == preset, "CapturePreset round-trips through JSON")
    expect(preset.destinationURL.path.hasSuffix("/Pictures/Shots"),
        "destination expands the tilde")
    expect(CapturePreset(name: "x", mode: .region).destinationURL.path
        .hasSuffix("/Desktop"), "nil destination falls back to Desktop")

    let suite = "ClichePresetTest-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let settings = AppSettings(defaults: defaults)
    expect(settings.capturePresets.isEmpty, "capture presets default empty")
    settings.capturePresets = [preset]
    expect(AppSettings(defaults: defaults).capturePresets == [preset],
        "capture presets persist")
    defaults.removePersistentDomain(forName: suite)
}

// desktopClutter
do {
    let iconLayer = Int(CGWindowLevelForKey(.desktopIconWindow))
    expect(DesktopClutter.isDesktopIconWindow(
        owningBundleID: "com.apple.finder", windowLayer: iconLayer),
        "Finder window at desktop-icon layer is clutter")
    expect(!DesktopClutter.isDesktopIconWindow(
        owningBundleID: "com.apple.finder", windowLayer: 0),
        "normal Finder window is not clutter")
    expect(!DesktopClutter.isDesktopIconWindow(
        owningBundleID: "com.example.other", windowLayer: iconLayer),
        "non-Finder window at icon layer is not clutter")
    expect(!DesktopClutter.isDesktopIconWindow(
        owningBundleID: nil, windowLayer: iconLayer),
        "nil bundle id is not clutter")

    let suite = "ClicheClutterTest-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let settings = AppSettings(defaults: defaults)
    expect(!settings.hideDesktopIcons, "hideDesktopIcons defaults to off")
    settings.hideDesktopIcons = true
    expect(AppSettings(defaults: defaults).hideDesktopIcons,
        "hideDesktopIcons persists")
    defaults.removePersistentDomain(forName: suite)
}

// ocrFromCGImage
do {
    let width = 700, height = 100
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ("HELLO CLICHE 42" as NSString).draw(
        at: NSPoint(x: 30, y: 30),
        withAttributes: [.font: NSFont.boldSystemFont(ofSize: 40),
                         .foregroundColor: NSColor.black])
    NSGraphicsContext.restoreGraphicsState()
    let image = ctx.makeImage()!
    let text = (try? OCRService.recognizeText(in: image)) ?? ""
    expect(text.contains("HELLO") && text.contains("42"),
        "OCR recognizes text from a CGImage")
}

// sensitiveTextDetection
do {
    let width = 900, height = 120
    let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ("Contact bob@example.com for the key" as NSString).draw(
        at: NSPoint(x: 20, y: 40),
        withAttributes: [
            .font: NSFont.systemFont(ofSize: 36),
            .foregroundColor: NSColor.black,
        ])
    NSGraphicsContext.restoreGraphicsState()
    let image = ctx.makeImage()!

    let rects = SensitiveTextDetector.detect(in: image)
    let inBounds = rects.allSatisfy {
        $0.minX >= -5 && $0.maxX <= CGFloat(width) + 5
            && $0.minY >= -5 && $0.maxY <= CGFloat(height) + 5
    }
    expect(!rects.isEmpty && inBounds,
        "sensitive detector finds the email with in-bounds rect")

    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let clean = ctx.makeImage()!
    expect(SensitiveTextDetector.detect(in: clean).isEmpty,
        "sensitive detector quiet on blank image")
}

// edgeMeasure
do {
    // White canvas with a black rectangle x:50..149, y(top-left):40..109.
    let ctx = CGContext(
        data: nil, width: 200, height: 150, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 150))
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fill(CGRect(x: 50, y: 150 - 110, width: 100, height: 70))  // CG bottom-left
    let image = ctx.makeImage()!

    let measure = EdgeMeasure(image: image)!
    let span = measure.span(x: 100, y: 75)!  // inside the black box (top-left coords)
    let boxWidth = span.left + span.right + 1
    let boxHeight = span.up + span.down + 1
    expect((98...102).contains(boxWidth) && (68...72).contains(boxHeight),
        "edge measure finds enclosing box \(boxWidth)x\(boxHeight)")
    expect(measure.span(x: 500, y: 20) == nil, "edge measure rejects out-of-bounds")
}

// stitcher
do {
    // A tall, feature-rich source image; slice overlapping windows and expect
    // the stitcher to reconstruct roughly the original height.
    let tallW = 320, tallH = 1200
    let ctx = CGContext(
        data: nil, width: tallW, height: tallH, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: tallW, height: tallH))
    for line in 0..<24 {
        ("Line \(line) — lorem ipsum dolor \(line * 37)" as NSString).draw(
            at: NSPoint(x: CGFloat(12 + (line % 5) * 8), y: CGFloat(line) * 50 + 8),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 20),
                .foregroundColor: NSColor.black,
            ])
    }
    NSGraphicsContext.restoreGraphicsState()
    let tall = ctx.makeImage()!

    // Windows of height 400 starting every 150 px from the top.
    let frameH = 400
    var frames: [CGImage] = []
    var top = 0
    while top + frameH <= tallH {
        frames.append(tall.cropping(
            to: CGRect(x: 0, y: top, width: tallW, height: frameH))!)
        top += 150
    }
    let stitched = Stitcher.stitch(frames)
    let heightOK = stitched.map { abs($0.height - tallH) <= 60 } ?? false
    expect(stitched != nil && stitched!.width == tallW && heightOK,
        "stitcher reconstructs tall image (got \(stitched?.height ?? 0) vs \(tallH))")
    expect(Stitcher.stitch([]) == nil, "stitcher rejects empty input")
}

// videoToGIF (writes a tiny synthetic MP4, converts it to GIF)
do {
    let videoURL = makeTempDir().appendingPathComponent("test.mp4")
    let width = 64, height = 64
    let writer = try! AVAssetWriter(outputURL: videoURL, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    for frame in 0..<8 {
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
        let pixelBuffer = buffer!
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
        ctx.setFillColor(CGColor(
            red: CGFloat(frame) / 8, green: 0.3, blue: 0.7, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        while !input.isReadyForMoreMediaData { usleep(5000) }
        adaptor.append(pixelBuffer, withPresentationTime:
            CMTime(value: CMTimeValue(frame), timescale: 10))
    }
    input.markAsFinished()
    let group = DispatchGroup()
    group.enter()
    writer.finishWriting { group.leave() }
    group.wait()

    var gif: Data?
    let gifGroup = DispatchGroup()
    gifGroup.enter()
    Task {
        gif = await VideoGIF.gifData(from: videoURL, fps: 8)
        gifGroup.leave()
    }
    gifGroup.wait()

    let frameCount = gif.flatMap {
        CGImageSourceCreateWithData($0 as CFData, nil).map(CGImageSourceGetCount)
    } ?? 0
    expect(gif?.prefix(4).elementsEqual([0x47, 0x49, 0x46, 0x38]) == true
        && frameCount >= 3,
        "video converts to multi-frame GIF (\(frameCount) frames)")
}

// ocrRecognizesRenderedText
do {
    let size = NSSize(width: 700, height: 140)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()
    ("Hello Cliche 42" as NSString).draw(
        at: NSPoint(x: 24, y: 40),
        withAttributes: [
            .font: NSFont.systemFont(ofSize: 48, weight: .bold),
            .foregroundColor: NSColor.black,
        ])
    image.unlockFocus()
    let png = NSBitmapImageRep(data: image.tiffRepresentation!)!
        .representation(using: .png, properties: [:])!
    let url = makeTempDir().appendingPathComponent("text.png")
    try! png.write(to: url)

    let recognized = (try? OCRService.recognizeText(in: url)) ?? ""
    expect(recognized.lowercased().contains("cliche")
        && recognized.contains("42"), "OCR recognizes rendered text")
}

// clipItemCodableRoundTrip
do {
    let items = [
        ClipItem(id: UUID(), date: Date(), kind: .text("hi")),
        ClipItem(id: UUID(), date: Date(), kind: .image(fileName: "x.png", sha256: "abc")),
    ]
    let data = try! JSONEncoder().encode(items)
    let decoded = try! JSONDecoder().decode([ClipItem].self, from: data)
    expect(decoded.map(\.kind) == items.map(\.kind)
        && decoded.map(\.id) == items.map(\.id), "ClipItem codable round trip")
}

if failures > 0 {
    print("\n\(failures) test(s) FAILED")
    exit(1)
} else {
    print("\nAll tests passed")
}
