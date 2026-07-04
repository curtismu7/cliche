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

// capsAtMaxItems
do {
    let store = HistoryStore(directory: makeTempDir(), maxItems: 3)
    for i in 1...5 { store.addText("item \(i)") }
    expect(store.items.count == 3
        && store.items[0].kind == .text("item 5")
        && store.items[2].kind == .text("item 3"), "caps at maxItems")
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
    let store = HistoryStore(directory: dir, maxItems: 1)
    store.addImage(pngData)
    store.addText("pushes image out")
    let images = (try? FileManager.default.contentsOfDirectory(
        atPath: dir.appendingPathComponent("images").path)) ?? []
    expect(store.items.count == 1 && images.isEmpty, "eviction deletes image file")
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
    let store = HistoryStore(directory: makeTempDir(), maxItems: 2)
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
