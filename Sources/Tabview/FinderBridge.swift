import AppKit
import ApplicationServices

/// One tab in the front Finder window.
struct FinderTab: Identifiable {
    let id: Int              // position in the tab bar
    let title: String
    let url: URL?            // folder the tab is showing (nil for Recents, AirDrop, …)
    let isActive: Bool
    let button: AXUIElement  // the tab's radio button in Finder's tab bar
}

/// Reads and drives Finder's tab bar.
/// Accessibility gives the exact tabs of the front window, in order, and can press them.
/// AppleScript fills in the folder each tab points at (Finder scripts every tab as a "window").
enum FinderBridge {
    static let bundleID = "com.apple.finder"

    static var finderApp: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    static var finderIsFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
    }

    /// Tabs of Finder's front window plus that window's frame in Cocoa screen coordinates.
    static func frontWindowTabs() -> (tabs: [FinderTab], frame: CGRect)? {
        guard let finder = finderApp else { return nil }
        let app = AXUIElementCreateApplication(finder.processIdentifier)
        guard let window: AXUIElement = attribute(app, kAXFocusedWindowAttribute)
                ?? attribute(app, kAXMainWindowAttribute),
              let frame = frame(of: window) else { return nil }

        let paths = tabPaths()
        var used = Set<Int>()
        var tabs: [FinderTab] = []

        let buttons = tabButtons(in: window)
        for (i, button) in buttons.enumerated() {
            let title: String = attribute(button, kAXTitleAttribute) ?? "Untitled"
            let selected = (attribute(button, kAXValueAttribute) as NSNumber?)?.boolValue ?? false
            // Match on name; duplicates (two tabs on the same folder) are consumed in order.
            var url: URL?
            if let hit = paths.enumerated().first(where: { !used.contains($0.offset) && $0.element.name == title }) {
                used.insert(hit.offset)
                url = hit.element.url
            }
            tabs.append(FinderTab(id: i, title: title, url: url, isActive: selected, button: button))
        }

        // A window with a single tab has no tab bar; describe it from AppleScript instead.
        if tabs.isEmpty {
            let title: String = attribute(window, kAXTitleAttribute) ?? "Finder"
            let url = paths.first(where: { $0.name == title })?.url
            tabs = [FinderTab(id: 0, title: title, url: url, isActive: true, button: window)]
        }
        return (tabs, frame)
    }

    static func select(_ tab: FinderTab) {
        finderApp?.activate()
        AXUIElementPerformAction(tab.button, kAXPressAction as CFString)
    }

    /// Closes a tab by bringing it forward and sending ⌘W to Finder.
    static func close(_ tab: FinderTab) {
        AXUIElementPerformAction(tab.button, kAXPressAction as CFString)
        sendKey(13 /* W */, flags: .maskCommand)
    }

    static func newTab() {
        finderApp?.activate()
        sendKey(17 /* T */, flags: .maskCommand)
    }

    // MARK: - Accessibility helpers

    private static func tabButtons(in window: AXUIElement) -> [AXUIElement] {
        let children: [AXUIElement] = attribute(window, kAXChildrenAttribute) ?? []
        guard let group = children.first(where: { (attribute($0, kAXRoleAttribute) as String?) == "AXTabGroup" })
        else { return [] }
        let items: [AXUIElement] = attribute(group, kAXChildrenAttribute) ?? []
        return items.filter { (attribute($0, kAXRoleAttribute) as String?) == "AXRadioButton" }
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        guard let posValue: AXValue = attribute(window, kAXPositionAttribute),
              let sizeValue: AXValue = attribute(window, kAXSizeAttribute) else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(posValue, .cgPoint, &pos)
        AXValueGetValue(sizeValue, .cgSize, &size)
        // Accessibility uses a top-left origin on the primary screen; Cocoa uses bottom-left.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: pos.x, y: primaryHeight - pos.y - size.height, width: size.width, height: size.height)
    }

    private static func sendKey(_ code: CGKeyCode, flags: CGEventFlags) {
        guard let pid = finderApp?.processIdentifier else { return }
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
            event?.flags = flags
            event?.postToPid(pid)
        }
    }

    // MARK: - AppleScript

    private static let pathScript = NSAppleScript(source: """
        tell application "Finder"
            set out to {}
            repeat with w in every Finder window
                set u to ""
                try
                    set u to URL of target of w
                end try
                set end of out to (name of w) & tab & u
            end repeat
            set AppleScript's text item delimiters to linefeed
            return out as text
        end tell
        """)

    /// Name → folder URL for every Finder tab, across all windows.
    private static func tabPaths() -> [(name: String, url: URL?)] {
        var error: NSDictionary?
        guard let text = pathScript?.executeAndReturnError(&error).stringValue else { return [] }
        return text.split(separator: "\n").map { line in
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            let url = parts.count > 1 ? URL(string: String(parts[1])) : nil
            return (String(parts[0]), url)
        }
    }
}
