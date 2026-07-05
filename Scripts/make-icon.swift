// Renders the Cliché app icon (red gradient rounded square, white scissors
// + clipboard glyphs) at 1024px. Run via Scripts/make-icon.sh.
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// macOS icons float inside a margin (~10%).
let inset: CGFloat = size * 0.09
let squircle = NSBezierPath(
    roundedRect: NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2),
    xRadius: size * 0.2, yRadius: size * 0.2)
let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.88, green: 0.22, blue: 0.20, alpha: 1),
    ending: NSColor(calibratedRed: 0.62, green: 0.08, blue: 0.12, alpha: 1))!
gradient.draw(in: squircle, angle: -60)

func drawSymbol(_ name: String, pointSize: CGFloat, at center: NSPoint, alpha: CGFloat) {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
    guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) else { return }
    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus()
    symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    NSColor.white.withAlphaComponent(alpha).set()
    NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
    tinted.unlockFocus()
    tinted.draw(at: NSPoint(x: center.x - symbol.size.width / 2,
                            y: center.y - symbol.size.height / 2),
                from: .zero, operation: .sourceOver, fraction: 1)
}

// Clipboard behind, scissors front — the two halves of the app.
drawSymbol("doc.on.clipboard.fill", pointSize: 400,
           at: NSPoint(x: size * 0.44, y: size * 0.52), alpha: 0.55)
drawSymbol("scissors", pointSize: 330,
           at: NSPoint(x: size * 0.60, y: size * 0.42), alpha: 1)

image.unlockFocus()

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let png = NSBitmapImageRep(data: image.tiffRepresentation!)!
    .representation(using: .png, properties: [:])!
try! png.write(to: output)
print("wrote \(output.path)")
