import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Pastes clipboard history into the app that was frontmost before the panel
/// opened. Uses Accessibility to write into the focused field (username,
/// password, URL bar, etc.) when possible; falls back to synthesized ⌘V.
public enum PasteService {
    private static var savedFocusElement: AXUIElement?
    /// AXIsProcessTrustedWithOptions(prompt:true) opens System Settings on every call.
    private static var didPromptTrustThisSession = false

    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system Accessibility prompt at most once per session.
    @discardableResult
    public static func requestTrust() -> Bool {
        if isTrusted { return true }
        guard !didPromptTrustThisSession else { return false }
        didPromptTrustThisSession = true
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Remember the focused text field in `app` before the panel opens.
    public static func capturePasteTarget(from app: NSRunningApplication?) {
        savedFocusElement = focusedElement(in: app) ?? focusedElement()
    }

    public static func clearPasteTarget() {
        savedFocusElement = nil
    }

    /// Paste plain text into the saved target field, or synthesize ⌘V.
    public static func pasteText(
        _ text: String,
        into app: NSRunningApplication?,
        useFocusedField: Bool = true
    ) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let target = useFocusedField ? savedFocusElement : nil
        savedFocusElement = nil

        app?.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard isTrusted, let target else {
                synthesizePaste()
                return
            }

            focusElement(target)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                if insertText(text, into: target) {
                    return
                }
                focusElement(target)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    synthesizePaste()
                }
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

    /// Focused control in a specific app (preferred over system-wide query).
    private static func focusedElement(in app: NSRunningApplication?) -> AXUIElement? {
        guard let pid = app?.processIdentifier else { return nil }
        let appElement = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXFocusedUIElementAttribute as CFString, &value
        ) == .success, let value else { return nil }
        return (value as! AXUIElement)
    }

    private static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &value
        ) == .success, let value else { return nil }
        return (value as! AXUIElement)
    }

    /// Brings the saved field to the foreground before AX write or ⌘V.
    @discardableResult
    private static func focusElement(_ element: AXUIElement) -> Bool {
        _ = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        let focused = AXUIElementSetAttributeValue(
            element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        return focused == .success
    }

    /// Writes text into a text field via Accessibility (HTML inputs, native fields).
    private static func insertText(_ text: String, into element: AXUIElement) -> Bool {
        focusElement(element)

        // Selected text respects cursor position; value keys replace the whole field.
        let attributeKeys: [CFString] = [
            kAXSelectedTextAttribute as CFString,
            kAXValueAttribute as CFString,
            "AXValue" as CFString,
            "AXText" as CFString,
        ]
        for key in attributeKeys {
            if AXUIElementSetAttributeValue(element, key, text as CFTypeRef) == .success {
                return true
            }
        }
        return false
    }
}
