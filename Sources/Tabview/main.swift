import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let overlay = OverlayController()
    private let pinch = PinchWatcher()
    private var hotKey: FinderHotKey?
    private var pinchItem: NSMenuItem!

    private var pinchEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "pinchEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "pinchEnabled") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotKey = FinderHotKey { [weak self] in self?.overlay.toggle() }

        pinch.isEnabled = pinchEnabled
        pinch.onPinchIn = { [weak self] in
            guard let self, FinderBridge.finderIsFrontmost, !self.overlay.isShown else { return }
            self.overlay.show()
        }
        pinch.onPinchOut = { [weak self] in self?.overlay.hide() }

        // Prompts for Accessibility the first time; needed for the tab bar and for pinch.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            pinch.start()
        } else {
            waitForAccessibility()
        }

        buildMenu()
    }

    /// Accessibility is granted in System Settings while we're running; start the pinch tap once it lands.
    private func waitForAccessibility() {
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.pinch.start()
        }
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Tabview")

        let menu = NSMenu()
        let show = NSMenuItem(title: "Show Finder Tabs", action: #selector(showTabs), keyEquivalent: "\\")
        show.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(show)
        menu.addItem(.separator())

        pinchItem = NSMenuItem(title: "Pinch to Show Tabs", action: #selector(togglePinch), keyEquivalent: "")
        pinchItem.state = pinchEnabled ? .on : .off
        menu.addItem(pinchItem)

        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(NSMenuItem(title: "Accessibility Settings…", action: #selector(openAccessibility), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Tabview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }
        statusItem.menu = menu
    }

    @objc private func showTabs() {
        // Picking from the menu bar leaves Finder frontmost underneath, so just open the grid.
        FinderBridge.finderApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.overlay.show() }
    }

    @objc private func togglePinch() {
        pinchEnabled.toggle()
        pinch.isEnabled = pinchEnabled
        pinchItem.state = pinchEnabled ? .on : .off
    }

    @objc private func toggleLogin(_ item: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSSound.beep()
        }
        item.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
