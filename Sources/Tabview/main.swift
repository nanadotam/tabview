import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let overlay = OverlayController()
    private let input = InputWatcher()
    private var hotKey: FinderHotKey?
    private var settingsWindow: NSWindow?
    private var showItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotKey = FinderHotKey { [weak self] in self?.overlay.toggle() }

        input.isOverlayShown = { [weak self] in self?.overlay.isShown ?? false }
        input.onIn = { [weak self] in self?.overlay.show() }
        input.onOut = { [weak self] in self?.overlay.hide() }

        Preferences.shared.onChange = { [weak self] in
            if SupportedApp.frontmost == nil { self?.overlay.hide(animated: false) }
            self?.hotKey?.update()
            self?.updateShowItem()
        }

        // Prompts for Accessibility the first time; needed for the tab bar and for gestures.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            input.start()
        } else {
            waitForAccessibility()
        }

        buildMenu()
    }

    /// Accessibility is granted in System Settings while we're running; start the event tap once it lands.
    private func waitForAccessibility() {
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.input.start()
        }
    }

    /// tabview://show, tabview://hide, tabview://toggle, tabview://settings — for Raycast, Shortcuts, scripts.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            switch url.host {
            case "show": showTabs()
            case "hide": overlay.hide()
            case "toggle": overlay.isShown ? overlay.hide() : showTabs()
            case "settings": openSettings()
            default: break
            }
        }
    }

    // MARK: - Menu bar

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Tabview")

        let menu = NSMenu()
        showItem = NSMenuItem(title: "Show All Tabs", action: #selector(showTabs), keyEquivalent: "")
        menu.addItem(showItem)
        menu.addItem(NSMenuItem(title: "Hide Tabs", action: #selector(hideTabs), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "About Tabview", action: #selector(openAbout), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Tabview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }
        menu.delegate = self
        statusItem.menu = menu
        updateShowItem()
    }

    func menuWillOpen(_ menu: NSMenu) { updateShowItem() }

    /// Shows the shortcut of the app in front (Finder's when neither is).
    private func updateShowItem() {
        let triggers = Preferences.shared.triggers(for: SupportedApp.frontmost ?? .finder)
        guard let showItem else { return }
        if triggers.shortcutEnabled {
            showItem.keyEquivalent = Shortcut.keyName(triggers.shortcut.keyCode).lowercased()
            showItem.keyEquivalentModifierMask = triggers.shortcut.modifiers
        } else {
            showItem.keyEquivalent = ""
        }
    }

    @objc private func showTabs() {
        // From the menu bar no supported app may be in front; fall back to bringing Finder forward.
        if SupportedApp.frontmost != nil {
            overlay.show()
        } else {
            SupportedApp.finder.running?.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.overlay.show() }
        }
    }

    @objc private func hideTabs() { overlay.hide(animated: false) }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Tabview Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openAbout() {
        NSWorkspace.shared.open(URL(string: "https://github.com/nanadotam/tabview")!)
    }
}

if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--render-readme" {
    // Offscreen README art; never touches the screen.
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    ReadmeRenderer.run(output: URL(fileURLWithPath: CommandLine.arguments[2]),
                       demo: CommandLine.arguments.count > 3 ? URL(fileURLWithPath: CommandLine.arguments[3]) : nil)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
