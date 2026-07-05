import AppKit
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
