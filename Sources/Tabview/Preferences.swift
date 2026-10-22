import AppKit
import Carbon.HIToolbox

/// A modifier the user can require alongside a gesture.
enum ModifierChoice: String, CaseIterable, Identifiable {
    case none, shift, control, option, command

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "No key"
        case .shift: "⇧ Shift"
        case .control: "⌃ Control"
        case .option: "⌥ Option"
        case .command: "⌘ Command"
        }
    }

    var cgFlag: CGEventFlags {
        switch self {
        case .none: []
        case .shift: .maskShift
        case .control: .maskControl
        case .option: .maskAlternate
        case .command: .maskCommand
        }
    }

    /// True when exactly this modifier (and no other) is held.
    func matches(_ flags: CGEventFlags) -> Bool {
        let all: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
        return flags.intersection(all) == cgFlag
    }
}

/// A recorded keyboard shortcut.
struct Shortcut: Equatable {
    var keyCode: UInt16
    var modifiers: NSEvent.ModifierFlags

    static let showAllTabs = Shortcut(keyCode: UInt16(kVK_ANSI_Backslash), modifiers: [.command, .shift])

    var carbonModifiers: UInt32 {
        var m: Int = 0
        if modifiers.contains(.command) { m |= cmdKey }
        if modifiers.contains(.shift) { m |= shiftKey }
        if modifiers.contains(.option) { m |= optionKey }
        if modifiers.contains(.control) { m |= controlKey }
        return UInt32(m)
    }

    var display: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + Shortcut.keyName(keyCode)
    }

    static func keyName(_ code: UInt16) -> String {
        let special: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋", kVK_Delete: "⌫",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let name = special[Int(code)] { return name }
        // Ask the current keyboard layout what character the key produces.
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "?" }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        data.withUnsafeBytes { raw in
            let layout = raw.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self)
            UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, 4, &length, &chars)
        }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

/// User settings, persisted in UserDefaults. Every trigger can be switched on or off independently.
@Observable
final class Preferences {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard

    var pinchEnabled: Bool { didSet { save("pinchEnabled", pinchEnabled) } }
    var pinchModifier: ModifierChoice { didSet { save("pinchModifier", pinchModifier.rawValue) } }
    /// 0 = needs a big pinch, 1 = the slightest pinch fires.
    var pinchSensitivity: Double { didSet { save("pinchSensitivity", pinchSensitivity) } }

    var shortcutEnabled: Bool { didSet { save("shortcutEnabled", shortcutEnabled) } }
    var shortcut: Shortcut {
        didSet {
            save("shortcutKey", Int(shortcut.keyCode))
            save("shortcutMods", Int(shortcut.modifiers.rawValue))
        }
    }

    var scrollEnabled: Bool { didSet { save("scrollEnabled", scrollEnabled) } }
    var scrollModifier: ModifierChoice { didSet { save("scrollModifier", scrollModifier.rawValue) } }

    var mouseButtonEnabled: Bool { didSet { save("mouseButtonEnabled", mouseButtonEnabled) } }
    /// CGEvent button number: 2 = middle, 3 = back, 4 = forward.
    var mouseButton: Int { didSet { save("mouseButton", mouseButton) } }

    var finderEnabled: Bool { didSet { save("finderEnabled", finderEnabled) } }
    var previewEnabled: Bool { didSet { save("previewEnabled", previewEnabled) } }

    func isEnabled(_ app: SupportedApp) -> Bool {
        switch app.bundleID {
        case SupportedApp.finder.bundleID: finderEnabled
        case SupportedApp.preview.bundleID: previewEnabled
        default: false
        }
    }

    /// Fires whenever anything that affects the triggers changes.
    var onChange: () -> Void = {}

    private init() {
        defaults.register(defaults: [
            "pinchEnabled": true, "pinchModifier": "none", "pinchSensitivity": 0.6,
            "shortcutEnabled": true,
            "shortcutKey": Int(Shortcut.showAllTabs.keyCode),
            "shortcutMods": Int(Shortcut.showAllTabs.modifiers.rawValue),
            "scrollEnabled": false, "scrollModifier": "option",
            "mouseButtonEnabled": false, "mouseButton": 2,
            "finderEnabled": true, "previewEnabled": true,
        ])
        finderEnabled = defaults.bool(forKey: "finderEnabled")
        previewEnabled = defaults.bool(forKey: "previewEnabled")
        pinchEnabled = defaults.bool(forKey: "pinchEnabled")
        pinchModifier = ModifierChoice(rawValue: defaults.string(forKey: "pinchModifier") ?? "") ?? .none
        pinchSensitivity = defaults.double(forKey: "pinchSensitivity")
        shortcutEnabled = defaults.bool(forKey: "shortcutEnabled")
        shortcut = Shortcut(keyCode: UInt16(defaults.integer(forKey: "shortcutKey")),
                            modifiers: NSEvent.ModifierFlags(rawValue: UInt(defaults.integer(forKey: "shortcutMods"))))
        scrollEnabled = defaults.bool(forKey: "scrollEnabled")
        scrollModifier = ModifierChoice(rawValue: defaults.string(forKey: "scrollModifier") ?? "") ?? .option
        mouseButtonEnabled = defaults.bool(forKey: "mouseButtonEnabled")
        mouseButton = defaults.integer(forKey: "mouseButton")
    }

    /// Cumulative magnification needed to count as a pinch.
    var pinchThreshold: CGFloat { CGFloat(0.30 - pinchSensitivity * 0.24) }

    private func save(_ key: String, _ value: Any) {
        defaults.set(value, forKey: key)
        onChange()
    }
}
