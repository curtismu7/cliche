import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Menu bar utility: no Dock icon (the bundled app also sets LSUIElement).
app.setActivationPolicy(.accessory)
app.run()
