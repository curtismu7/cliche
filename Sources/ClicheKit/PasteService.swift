import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Pastes clipboard history into the app that was frontmost before the panel
/// opened. Closes the panel first, then synthesizes ⌘V into the target app.
public enum PasteService {
    private static var savedFocusElement: AXUIElement?
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
        let trusted = AXIsProcessTrusted()
        if trusted {
            noteTrustedExecutableIfNeeded()
            enableAttempted = false
        }
        return trusted
    }

    public static var accessibilityNeedsRestart: Bool {
        enableAttempted && !AXIsProcessTrusted()
    }

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
        guard AXIsProcessTrusted(), let mod = executableModificationDate() else { return }
        UserDefaults.standard.set(mod.timeIntervalSince1970, forKey: trustedExecutableModKey)
    }

    private static func executableModificationDate() -> Date? {
        guard let url = Bundle.main.executableURL else { return nil }
        return (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
    }

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

    public static func openSettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    public static func capturePasteTarget(
        from app: NSRunningApplication?, appOnly: Bool = false
    ) {
        if let app, let element = focusedElement(in: app) {
            savedFocusElement = element
            return
        }
        if !appOnly {
            savedFocusElement = focusedElement()
        }
    }

    public static func clearPasteTarget() {
        savedFocusElement = nil
    }

    public static func pasteText(
        _ text: String,
        into app: NSRunningApplication?,
        useFocusedField: Bool = true
    ) {
        writeTextToPasteboard(text)
        deliverPaste(into: app, useFocusedField: useFocusedField)
    }

    public static func pasteClipboard(into app: NSRunningApplication?) {
        deliverPaste(into: app, useFocusedField: false)
    }

    public static let pasteRequiresAccessibilityNotification = Notification.Name(
        "ClichePasteRequiresAccessibility")
    public static let pasteFailedNotification = Notification.Name("ClichePasteFailed")
    public static let pasteCopiedNotification = Notification.Name("ClichePasteCopied")

    private static func writeTextToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(text, forType: .string)
    }

    private static func deliverPaste(
        into app: NSRunningApplication?,
        useFocusedField: Bool
    ) {
        guard isTrusted else {
            NotificationCenter.default.post(
                name: pasteRequiresAccessibilityNotification, object: nil)
            return
        }

        let targetApp = app ?? FrontmostAppTracker.lastApplication
        guard let targetApp else {
            NotificationCenter.default.post(name: pasteFailedNotification, object: nil)
            return
        }

        let savedTarget = useFocusedField ? savedFocusElement : nil
        savedFocusElement = nil

        NSApp.hide(nil)
        runPaste(into: targetApp, focus: savedTarget, attempt: 0)
    }

    private static func runPaste(
        into app: NSRunningApplication,
        focus: AXUIElement?,
        attempt: Int
    ) {
        app.activate(options: [.activateAllWindows])

        if let focus {
            focusElement(focus)
        }

        let delay: TimeInterval = attempt == 0 ? 0.2 : 0.15
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if frontmost != app.processIdentifier, attempt < 4 {
                runPaste(into: app, focus: focus, attempt: attempt + 1)
                return
            }
            synthesizePaste(to: app)
            NotificationCenter.default.post(name: pasteCopiedNotification, object: nil)
        }
    }

    /// Sends ⌘V to the target process. `postToPid` works from menu-bar apps;
    /// session taps are a fallback for native fields.
    public static func synthesizePaste(to app: NSRunningApplication? = nil) {
        let cmdFlag = CGEventFlags(rawValue: UInt64(cmdKey) | 0x000008)
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval)

        let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(kVK_ANSI_V),
            keyDown: true)
        let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(kVK_ANSI_V),
            keyDown: false)
        keyDown?.flags = cmdFlag
        keyUp?.flags = cmdFlag

        if let pid = app?.processIdentifier {
            keyDown?.postToPid(pid_t(pid))
            keyUp?.postToPid(pid_t(pid))
        }

        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)
    }

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

    @discardableResult
    private static func focusElement(_ element: AXUIElement) -> Bool {
        _ = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        let focused = AXUIElementSetAttributeValue(
            element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        return focused == .success
    }
}
