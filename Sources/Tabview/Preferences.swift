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

/// How one app summons the grid. Each supported app gets its own set, so Preview can leave pinch to zooming
/// while Finder keeps it, or each app can use a different shortcut.
struct AppTriggers: Equatable {
    var pinchEnabled = true
    var pinchModifier: ModifierChoice = .none
    /// 0 = needs a big pinch, 1 = the slightest pinch fires.
    var pinchSensitivity = 0.6

    var shortcutEnabled = true
    var shortcut: Shortcut = .showAllTabs

    var scrollEnabled = false
    var scrollModifier: ModifierChoice = .option

    var mouseButtonEnabled = false
    /// CGEvent button number: 2 = middle, 3 = back, 4 = forward.
    var mouseButton = 2

    /// Cumulative magnification needed to count as a pinch.
    var pinchThreshold: CGFloat { CGFloat(0.30 - pinchSensitivity * 0.24) }

    /// Preview zooms with a pinch, so out of the box it only listens to the shortcut.
    static func defaults(for app: SupportedApp) -> AppTriggers {
        var t = AppTriggers()
        if app == .preview { t.pinchEnabled = false }
        return t
    }
}

/// User settings, persisted in UserDefaults. Every trigger can be switched on or off independently, per app.
@Observable
final class Preferences {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard

    var finderEnabled: Bool { didSet { save("finderEnabled", finderEnabled) } }
    var previewEnabled: Bool { didSet { save("previewEnabled", previewEnabled) } }

    var finder: AppTriggers { didSet { save(finder, for: .finder) } }
    var preview: AppTriggers { didSet { save(preview, for: .preview) } }

    func isEnabled(_ app: SupportedApp) -> Bool {
        switch app.bundleID {
        case SupportedApp.finder.bundleID: finderEnabled
        case SupportedApp.preview.bundleID: previewEnabled
        default: false
        }
    }

    func triggers(for app: SupportedApp) -> AppTriggers {
        app == .preview ? preview : finder
    }

    func setTriggers(_ triggers: AppTriggers, for app: SupportedApp) {
        if app == .preview { preview = triggers } else { finder = triggers }
    }

    /// Fires whenever anything that affects the triggers changes.
    var onChange: () -> Void = {}

    private init() {
        defaults.register(defaults: ["finderEnabled": true, "previewEnabled": true])
        finderEnabled = defaults.bool(forKey: "finderEnabled")
        previewEnabled = defaults.bool(forKey: "previewEnabled")
        finder = Self.load(.finder, from: defaults)
        preview = Self.load(.preview, from: defaults)
    }

    /// Keys are "<bundle id>.<setting>". Before triggers were per app they were stored without the prefix;
    /// those older values seed Finder, and Preview too (except pinch, which fought Preview's zoom).
    private static func load(_ app: SupportedApp, from defaults: UserDefaults) -> AppTriggers {
        func value(_ key: String) -> Any? {
            defaults.object(forKey: "\(app.bundleID).\(key)") ?? (app == .preview && key == "pinchEnabled"
                ? nil : defaults.object(forKey: key))
        }
        var t = AppTriggers.defaults(for: app)
        if let v = value("pinchEnabled") as? Bool { t.pinchEnabled = v }
        if let v = value("pinchModifier") as? String, let m = ModifierChoice(rawValue: v) { t.pinchModifier = m }
        if let v = value("pinchSensitivity") as? Double { t.pinchSensitivity = v }
        if let v = value("shortcutEnabled") as? Bool { t.shortcutEnabled = v }
        if let key = value("shortcutKey") as? Int, let mods = value("shortcutMods") as? Int {
            t.shortcut = Shortcut(keyCode: UInt16(key), modifiers: NSEvent.ModifierFlags(rawValue: UInt(mods)))
        }
        if let v = value("scrollEnabled") as? Bool { t.scrollEnabled = v }
        if let v = value("scrollModifier") as? String, let m = ModifierChoice(rawValue: v) { t.scrollModifier = m }
        if let v = value("mouseButtonEnabled") as? Bool { t.mouseButtonEnabled = v }
        if let v = value("mouseButton") as? Int { t.mouseButton = v }
        return t
    }

    private func save(_ t: AppTriggers, for app: SupportedApp) {
        let values: [String: Any] = [
            "pinchEnabled": t.pinchEnabled, "pinchModifier": t.pinchModifier.rawValue,
            "pinchSensitivity": t.pinchSensitivity,
            "shortcutEnabled": t.shortcutEnabled,
            "shortcutKey": Int(t.shortcut.keyCode), "shortcutMods": Int(t.shortcut.modifiers.rawValue),
            "scrollEnabled": t.scrollEnabled, "scrollModifier": t.scrollModifier.rawValue,
            "mouseButtonEnabled": t.mouseButtonEnabled, "mouseButton": t.mouseButton,
        ]
        for (key, value) in values { defaults.set(value, forKey: "\(app.bundleID).\(key)") }
        onChange()
    }

    private func save(_ key: String, _ value: Any) {
        defaults.set(value, forKey: key)
        onChange()
    }
}
