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
    private static let trustedExecutableModKey = "accessibilityGrantedExecutableMod"
    private static let enableAttemptedKey = "accessibilityEnableAttempted"

    public static var applicationPath: String { Bundle.main.bundlePath }

    public static var standardInstallPath: String {
        ScreenCapturePermission.standardInstallPath
    }

    public static var isRunningFromStandardInstall: Bool {
        applicationPath == standardInstallPath
    }

    public static var enableAttempted: Bool {
        get { UserDefaults.standard.bool(forKey: enableAttemptedKey) }
        set { UserDefaults.standard.set(newValue, forKey: enableAttemptedKey) }
    }

    public static var isTrusted: Bool {
        if hasAccessibilityAccess() {
            noteTrustedExecutableIfNeeded()
            enableAttempted = false
            return true
        }
        return false
    }

    /// AXIsProcessTrusted can lag after toggling in System Settings; probe the API.
    private static func hasAccessibilityAccess() -> Bool {
        if AXIsProcessTrusted() { return true }
        let system = AXUIElementCreateSystemWide()
        var appValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            system, kAXFocusedApplicationAttribute as CFString, &appValue) == .success {
            return true
        }
        var focusValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            system, kAXFocusedUIElementAttribute as CFString, &focusValue) == .success {
            return true
        }
        return false
    }

    /// Why Accessibility may still look off after enabling in System Settings.
    public static var trustDiagnostics: String? {
        guard !isTrusted else { return nil }
        var lines: [String] = ["Running: \(applicationPath)"]
        if !isRunningFromStandardInstall {
            lines.append("Open only \(standardInstallPath) and enable that copy in Accessibility.")
        }
        if executableWasRebuiltSinceLastTrust {
            lines.append("This build changed since Accessibility last worked — toggle Cliché OFF then ON.")
        } else if enableAttempted {
            lines.append("If Cliché is ON in System Settings, quit completely (⌘Q) and reopen.")
        }
        return lines.joined(separator: "\n")
    }

    public static var executableWasRebuiltSinceLastTrust: Bool {
        let stored = UserDefaults.standard.double(forKey: trustedExecutableModKey)
        guard stored > 0, let current = executableModificationDate() else { return false }
        return current.timeIntervalSince1970 > stored + 1
    }

    private static func noteTrustedExecutableIfNeeded() {
        guard hasAccessibilityAccess(), let mod = executableModificationDate() else { return }
        UserDefaults.standard.set(mod.timeIntervalSince1970, forKey: trustedExecutableModKey)
    }

    private static func executableModificationDate() -> Date? {
        guard let url = Bundle.main.executableURL else { return nil }
        return (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
    }

    /// Shows the system Accessibility prompt at most once per session.
    @discardableResult
    public static func requestTrust() -> Bool {
        enableAttempted = true
        if isTrusted { return true }
        guard !didPromptTrustThisSession else { return false }
        didPromptTrustThisSession = true
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Opens the Accessibility pane in System Settings.
    public static func openSettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
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

        let targetApp = app ?? FrontmostAppTracker.lastApplication
        let savedTarget = useFocusedField ? savedFocusElement : nil
        savedFocusElement = nil

        guard let targetApp else {
            NotificationCenter.default.post(name: pasteFailedNotification, object: nil)
            return
        }

        activate(targetApp) {
            let focused = savedTarget
                ?? (useFocusedField ? focusedElement(in: targetApp) ?? focusedElement() : nil)

            if isTrusted, let focused, insertText(text, into: focused) {
                return
            }

            if let focused, isTrusted {
                focusElement(focused)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                synthesizePaste()
            }
            if !isTrusted {
                NotificationCenter.default.post(
                    name: pasteRequiresAccessibilityNotification, object: nil)
            }
        }
    }

    /// Paste whatever is already on the pasteboard (images, files, rich content).
    public static func pasteClipboard(into app: NSRunningApplication?) {
        let targetApp = app ?? FrontmostAppTracker.lastApplication
        savedFocusElement = nil

        guard let targetApp else {
            NotificationCenter.default.post(name: pasteFailedNotification, object: nil)
            return
        }

        activate(targetApp) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                synthesizePaste()
            }
            if !isTrusted {
                NotificationCenter.default.post(
                    name: pasteRequiresAccessibilityNotification, object: nil)
            }
        }
    }

    public static let pasteRequiresAccessibilityNotification = Notification.Name(
        "ClichePasteRequiresAccessibility")
    public static let pasteFailedNotification = Notification.Name("ClichePasteFailed")

    private static func activate(_ app: NSRunningApplication, then work: @escaping () -> Void) {
        app.activate(options: [.activateAllWindows])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier
                != app.processIdentifier {
                app.activate(options: [.activateAllWindows])
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
                return
            }
            work()
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
