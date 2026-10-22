import AppKit
import ApplicationServices

/// One tab in the front window of a supported app.
struct FinderTab: Identifiable {
    let id: Int              // position in the tab bar
    let title: String
    var url: URL?            // folder or document the tab is showing (nil for Recents, AirDrop, …)
    let isActive: Bool
    let button: AXUIElement? // the tab's button in the tab bar (nil for a window with one tab)
}

/// An app whose native tab bar Tabview can show as a grid.
struct SupportedApp: Equatable {
    let bundleID: String
    let name: String
    /// AppleScript returning `{names, locations}` for every tab, in one Apple Event.
    let pathsScript: String
    /// Locations come back as `file://` URLs (Finder) rather than POSIX paths (Preview).
    let returnsURLs: Bool
    /// Cards show the folder's contents (Finder) or the document itself (Preview).
    let showsFolders: Bool
    let canOpenNewTab: Bool

    static let finder = SupportedApp(
        bundleID: "com.apple.finder", name: "Finder",
        pathsScript: "tell application \"Finder\" to get {name, URL of target} of every Finder window",
        returnsURLs: true, showsFolders: true, canOpenNewTab: true)

    static let preview = SupportedApp(
        bundleID: "com.apple.Preview", name: "Preview",
        pathsScript: "tell application \"Preview\" to get {name, path} of every document",
        returnsURLs: false, showsFolders: false, canOpenNewTab: false)

    static let all = [finder, preview]

    var isEnabled: Bool { Preferences.shared.isEnabled(self) }

    var running: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    /// The enabled supported app that's in front, if any.
    static var frontmost: SupportedApp? {
        let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return all.first { $0.bundleID == id && $0.isEnabled }
    }
}

/// Reads and drives an app's native tab bar.
/// Accessibility gives the exact tabs of the front window, in order, in a few milliseconds.
/// Paths come from AppleScript (Finder scripts each tab as a "window", Preview as a "document").
/// That's slower, so it runs in the background and the last answer is cached for an instant first paint.
enum TabBridge {
    /// Tabs of the app's front window plus that window's frame in Cocoa screen coordinates.
    /// Paths are filled from the cache; call `refreshPaths` to bring them up to date.
    static func frontWindowTabs(of supported: SupportedApp) -> (tabs: [FinderTab], frame: CGRect)? {
        guard let running = supported.running else { return nil }
        let app = AXUIElementCreateApplication(running.processIdentifier)
        // Never let a busy app stall the grid.
        AXUIElementSetMessagingTimeout(app, 0.3)
        guard let window: AXUIElement = attribute(app, kAXFocusedWindowAttribute)
                ?? attribute(app, kAXMainWindowAttribute),
              let frame = frame(of: window) else { return nil }

        var tabs = tabButtons(in: window).enumerated().map { i, button in
            FinderTab(id: i,
                      title: attribute(button, kAXTitleAttribute) ?? "Untitled",
                      url: nil,
                      isActive: (attribute(button, kAXValueAttribute) as NSNumber?)?.boolValue ?? false,
                      button: button)
        }
        // A window with a single tab has no tab bar.
        if tabs.isEmpty {
            tabs = [FinderTab(id: 0, title: attribute(window, kAXTitleAttribute) ?? supported.name,
                              url: nil, isActive: true, button: nil)]
        }
        return (assignPaths(to: tabs, from: cachedPaths[supported.bundleID] ?? []), frame)
    }

    static func select(_ tab: FinderTab, in app: SupportedApp) {
        app.running?.activate()
        if let button = tab.button { AXUIElementPerformAction(button, kAXPressAction as CFString) }
    }

    /// Closes a tab by bringing it forward and sending ⌘W.
    static func close(_ tab: FinderTab, in app: SupportedApp) {
        if let button = tab.button { AXUIElementPerformAction(button, kAXPressAction as CFString) }
        sendKey(13 /* W */, flags: .maskCommand, to: app)
    }

    static func newTab(in app: SupportedApp) {
        app.running?.activate()
        sendKey(17 /* T */, flags: .maskCommand, to: app)
    }

    // MARK: - Folder paths

    typealias TabPath = (name: String, url: URL?)

    private static let queue = DispatchQueue(label: "tabview.tab-paths", qos: .userInitiated)
    private static var cachedPaths: [String: [TabPath]] = [:]
    private static var lastRefresh: [String: Date] = [:]

    /// Re-reads every tab's location in the background, then calls back on the main queue.
    /// Calls within `minInterval` of the last refresh for that app are skipped.
    static func refreshPaths(of app: SupportedApp, minInterval: TimeInterval = 0,
                             completion: (([TabPath]) -> Void)? = nil) {
        let id = app.bundleID
        guard Date().timeIntervalSince(lastRefresh[id] ?? .distantPast) >= minInterval else { return }
        lastRefresh[id] = Date()
        queue.async {
            let paths = fetchPaths(of: app)
            DispatchQueue.main.async {
                if !paths.isEmpty { cachedPaths[id] = paths }
                completion?(cachedPaths[id] ?? [])
            }
        }
    }

    /// Matches tabs to folders by name; duplicates (two tabs on the same folder name) are consumed in order.
    static func assignPaths(to tabs: [FinderTab], from paths: [TabPath]) -> [FinderTab] {
        var used = Set<Int>()
        return tabs.map { tab in
            var tab = tab
            if let hit = paths.enumerated().first(where: { !used.contains($0.offset) && $0.element.name == tab.title }) {
                used.insert(hit.offset)
                tab.url = hit.element.url
            }
            return tab
        }
    }

    /// One Apple Event for all tabs (~0.2 s). Asking tab by tab is ~100× slower.
    private static func fetchPaths(of app: SupportedApp) -> [TabPath] {
        func location(_ string: String?) -> URL? {
            guard let string, !string.isEmpty else { return nil }
            return app.returnsURLs ? URL(string: string) : URL(fileURLWithPath: string)
        }
        let bulk = run(app.pathsScript)
        if let names = bulk?.atIndex(1), let paths = bulk?.atIndex(2), names.numberOfItems == paths.numberOfItems {
            return (1...max(names.numberOfItems, 1)).compactMap { i in
                guard let name = names.atIndex(i)?.stringValue else { return nil }
                return (name, location(paths.atIndex(i)?.stringValue))
            }
        }
        guard app == .finder else { return [] }
        // Some tab (Recents, AirDrop, a network browser…) has no URL and failed the bulk query.
        // Fall back to names plus per-tab URLs, skipping the ones that error.
        guard let names = run("tell application \"Finder\" to get name of every Finder window") else { return [] }
        return (1...max(names.numberOfItems, 1)).compactMap { i in
            guard let name = names.atIndex(i)?.stringValue else { return nil }
            let url = run("tell application \"Finder\" to get URL of target of Finder window \(i)")?.stringValue
            return (name, url.flatMap(URL.init(string:)))
        }
    }

    private static func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? result : nil
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

    private static func sendKey(_ code: CGKeyCode, flags: CGEventFlags, to app: SupportedApp) {
        guard let pid = app.running?.processIdentifier else { return }
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
            event?.flags = flags
            event?.postToPid(pid)
        }
    }
}
