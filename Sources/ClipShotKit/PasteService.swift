import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Pastes the current clipboard into another app by synthesizing ⌘V.
/// Requires the Accessibility permission; request it lazily so copy-only
/// users are never prompted.
public enum PasteService {
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system Accessibility prompt (once) if not yet trusted.
    @discardableResult
    public static func requestTrust() -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Posts ⌘V key events to the session. The target app must already be
    /// frontmost and the clipboard already populated.
    public static func synthesizePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(
            keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let keyUp = CGEvent(
            keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
