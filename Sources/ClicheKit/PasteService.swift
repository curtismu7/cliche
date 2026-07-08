import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Pastes clipboard history into the app that was frontmost before the panel
/// opened. Uses Accessibility to write into the focused field (username,
/// password, URL bar, etc.) when possible; falls back to synthesized ⌘V.
public enum PasteService {
    private static var savedFocusElement: AXUIElement?

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

    /// Remember the focused text field before the panel opens and steals focus.
    public static func capturePasteTarget() {
        savedFocusElement = focusedElement()
    }

    public static func clearPasteTarget() {
        savedFocusElement = nil
    }

    /// Paste plain text into the saved target field, or synthesize ⌘V.
    public static func pasteText(_ text: String, into app: NSRunningApplication?) {
        guard isTrusted else {
            requestTrust()
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let target = savedFocusElement
        savedFocusElement = nil

        app?.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let target, insertText(text, into: target) {
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                synthesizePaste()
            }
        }
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

    private static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &value
        ) == .success, let value else { return nil }
        return (value as! AXUIElement)
    }

    /// Writes text into a text field via Accessibility (works for many HTML inputs).
    private static func insertText(_ text: String, into element: AXUIElement) -> Bool {
        _ = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        _ = AXUIElementSetAttributeValue(
            element, kAXFocusedAttribute as CFString, kCFBooleanTrue)

        if AXUIElementSetAttributeValue(
            element, kAXValueAttribute as CFString, text as CFTypeRef
        ) == .success {
            return true
        }
        if AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFTypeRef
        ) == .success {
            return true
        }
        return false
    }
}
