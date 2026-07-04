import AppKit
import Foundation
import ClipShotKit

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
        .appendingPathComponent("ClipShotTests-\(UUID().uuidString)", isDirectory: true)
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

// ocrRecognizesRenderedText
do {
    let size = NSSize(width: 700, height: 140)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()
    ("Hello ClipShot 42" as NSString).draw(
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
    expect(recognized.lowercased().contains("clipshot")
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
