import AppKit
import Carbon.HIToolbox

class HotkeyManager {
    static let shared = HotkeyManager()

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var nextId: UInt32 = 1

    private init() {
        setupEventHandler()
    }

    deinit {
        removeAllHotkeys()
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
        }
    }

    private func setupEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { (_, event, userData) -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)

            if let handler = manager.handlers[hotKeyID.id] {
                DispatchQueue.main.async {
                    handler()
                }
            }

            return noErr
        }

        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, userData, &eventHandlerRef)
    }

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> UInt32 {
        let id = nextId
        nextId += 1

        let hotKeyID = EventHotKeyID(signature: OSType(0x4853_4B59), id: id)
        var hotKeyRef: EventHotKeyRef?

        let carbonModifiers = convertToCarbonModifiers(modifiers)

        let status = RegisterEventHotKey(keyCode, carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        if status == noErr, let ref = hotKeyRef {
            hotKeyRefs[id] = ref
            handlers[id] = handler
        }

        return id
    }

    func unregister(id: UInt32) {
        if let ref = hotKeyRefs[id] {
            UnregisterEventHotKey(ref)
            hotKeyRefs.removeValue(forKey: id)
            handlers.removeValue(forKey: id)
        }
    }

    func removeAllHotkeys() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        handlers.removeAll()
    }

    private func convertToCarbonModifiers(_ cocoaModifiers: UInt32) -> UInt32 {
        var carbonModifiers: UInt32 = 0

        if cocoaModifiers & UInt32(NSEvent.ModifierFlags.command.rawValue) != 0 {
            carbonModifiers |= UInt32(cmdKey)
        }
        if cocoaModifiers & UInt32(NSEvent.ModifierFlags.shift.rawValue) != 0 {
            carbonModifiers |= UInt32(shiftKey)
        }
        if cocoaModifiers & UInt32(NSEvent.ModifierFlags.option.rawValue) != 0 {
            carbonModifiers |= UInt32(optionKey)
        }
        if cocoaModifiers & UInt32(NSEvent.ModifierFlags.control.rawValue) != 0 {
            carbonModifiers |= UInt32(controlKey)
        }

        return carbonModifiers
    }
}

struct HotkeyConfig {
    static let fullScreenKeyCode: UInt32 = 20  // 3
    static let regionKeyCode: UInt32 = 21      // 4
    static let windowKeyCode: UInt32 = 23      // 5
    static let frameKeyCode: UInt32 = 22       // 6 (Cmd+Shift+6)
    static let gifRecordingKeyCode: UInt32 = 26  // 7 (Cmd+Shift+7)

    static let modifiers = UInt32(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue)
}
