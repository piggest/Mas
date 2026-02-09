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

// ショートカットの識別キー
enum HotkeyAction: String, CaseIterable {
    case fullScreen = "fullScreen"
    case region = "region"
    case frame = "frame"
    case gifRecording = "gifRecording"
    case history = "history"

    var label: String {
        switch self {
        case .fullScreen: return "全画面キャプチャ"
        case .region: return "範囲選択キャプチャ"
        case .frame: return "キャプチャ枠を表示"
        case .gifRecording: return "GIF録画"
        case .history: return "ライブラリ"
        }
    }

    var defaultKeyCode: UInt32 {
        switch self {
        case .fullScreen: return 20   // 3
        case .region: return 21       // 4
        case .frame: return 22        // 6
        case .gifRecording: return 26 // 7
        case .history: return 37      // L
        }
    }

    var defaultModifiers: UInt32 {
        UInt32(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue)
    }

    private var userDefaultsKeyCodeKey: String { "hotkey.\(rawValue).keyCode" }
    private var userDefaultsModifiersKey: String { "hotkey.\(rawValue).modifiers" }

    var keyCode: UInt32 {
        let stored = UserDefaults.standard.object(forKey: userDefaultsKeyCodeKey)
        return stored != nil ? UInt32(UserDefaults.standard.integer(forKey: userDefaultsKeyCodeKey)) : defaultKeyCode
    }

    var modifiers: UInt32 {
        let stored = UserDefaults.standard.object(forKey: userDefaultsModifiersKey)
        return stored != nil ? UInt32(UserDefaults.standard.integer(forKey: userDefaultsModifiersKey)) : defaultModifiers
    }

    func save(keyCode: UInt32, modifiers: UInt32) {
        UserDefaults.standard.set(Int(keyCode), forKey: userDefaultsKeyCodeKey)
        UserDefaults.standard.set(Int(modifiers), forKey: userDefaultsModifiersKey)
    }

    func resetToDefault() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKeyCodeKey)
        UserDefaults.standard.removeObject(forKey: userDefaultsModifiersKey)
    }

    var isCustomized: Bool {
        UserDefaults.standard.object(forKey: userDefaultsKeyCodeKey) != nil
    }

    /// 表示用文字列（例: "⌘⇧3"）
    var displayString: String {
        HotkeyDisplayHelper.displayString(keyCode: keyCode, modifiers: modifiers)
    }
}

struct HotkeyDisplayHelper {
    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        var result = ""
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        result += keyCodeToString(keyCode)
        return result
    }

    static func modifiersDisplayString(_ modifiers: UInt32) -> String {
        var result = ""
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        return result
    }

    static func keyCodeToString(_ keyCode: UInt32) -> String {
        let mapping: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G",
            6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q",
            13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
            18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
            24: "=", 25: "9", 26: "7", 27: "8", 28: "0", 29: "-",  // Note: 28 is 0 on keyboard but used as key 8 shortcut
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
            43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
            48: "Tab", 49: "Space", 50: "`",
            51: "Delete", 53: "Esc",
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
            101: "F9", 103: "F11", 105: "F13", 107: "F14",
            109: "F10", 111: "F12", 113: "F15", 115: "Home",
            116: "PageUp", 117: "⌦", 118: "F4", 119: "End",
            120: "F2", 121: "PageDown", 122: "F1",
            123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        return mapping[keyCode] ?? "Key\(keyCode)"
    }
}

extension Notification.Name {
    static let hotkeySettingsChanged = Notification.Name("hotkeySettingsChanged")
}
