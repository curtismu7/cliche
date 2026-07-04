import Carbon.HIToolbox

/// Global hotkeys via Carbon's RegisterEventHotKey — the one API that needs
/// no Accessibility permission.
public final class HotkeyManager {
    public struct Modifiers {
        public static let controlOptionCommand =
            UInt32(controlKey) | UInt32(optionKey) | UInt32(cmdKey)
    }

    private var handlers: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandlerRef: EventHandlerRef?

    public init() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID)
                let manager = Unmanaged<HotkeyManager>
                    .fromOpaque(userData).takeUnretainedValue()
                manager.handlers[hotKeyID.id]?()
                return noErr
            },
            1,
            &eventSpec,
            selfPointer,
            &eventHandlerRef)
    }

    @discardableResult
    public func register(
        keyCode: Int,
        modifiers: UInt32 = Modifiers.controlOptionCommand,
        handler: @escaping () -> Void
    ) -> Bool {
        let id = nextID
        nextID += 1
        handlers[id] = handler

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C_5348), id: id)  // 'CLSH'
        let status = RegisterEventHotKey(
            UInt32(keyCode), modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &ref)
        hotKeyRefs.append(ref)
        if status != noErr {
            NSLog("ClipShot: failed to register hotkey (code \(keyCode)): \(status)")
        }
        return status == noErr
    }
}
