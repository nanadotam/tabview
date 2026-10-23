import AppKit
import SwiftUI

/// Borderless panel that sits exactly over the front window of the app whose tabs it shows.
/// Non-activating, so that app stays active while the grid is up.
final class OverlayPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
}

final class OverlayController {
    private let panel = OverlayPanel()
    private let model = TabGridModel()
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var orderOutWork: DispatchWorkItem?
    private var app: SupportedApp = .finder

    /// True from the moment the grid is asked to show until it starts hiding.
    var isShown: Bool { model.presented }

    init() {
        panel.contentView = NSHostingView(rootView: TabGridView(model: model))
        model.onOpen = { [weak self] tab in
            guard let self else { return }
            TabBridge.select(tab, in: self.app)
            self.hide()
        }
        model.onClose = { [weak self] tab in
            guard let self else { return }
            TabBridge.close(tab, in: self.app)
            // Give Finder a beat to drop the tab, then re-read the tab bar.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.reload() }
        }
        model.onNewTab = { [weak self] in
            guard let self else { return }
            self.hide()
            TabBridge.newTab(in: self.app)
        }
        model.onDismiss = { [weak self] in self?.hide() }

        let center = NSWorkspace.shared.notificationCenter
        // The grid belongs to one app's window: the moment another app comes forward, it goes away.
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) {
            [weak self] note in
            guard let self else { return }
            let active = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if active?.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }
            if active?.bundleIdentifier != self.app.bundleID { self.hide(animated: false) }
            if let supported = SupportedApp.frontmost { self.prefetch(supported) }
        }
        center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) {
            [weak self] _ in self?.hide(animated: false)
        }
        if let supported = SupportedApp.frontmost { prefetch(supported) }
    }

    func toggle() { isShown ? hide() : show() }

    func show() {
        guard !isShown, let supported = SupportedApp.frontmost,
              let (tabs, frame) = TabBridge.frontWindowTabs(of: supported) else { return }
        orderOutWork?.cancel()
        app = supported
        model.app = supported
        model.tabs = tabs
        model.query = ""
        model.highlighted = tabs.firstIndex(where: \.isActive) ?? 0
        panel.setFrame(frame, display: false)
        panel.makeKeyAndOrderFront(nil)
        model.presented = true
        installMonitors()

        // Paths came from the cache; bring them up to date without holding up the grid.
        TabBridge.refreshPaths(of: supported) { [weak self] paths in
            guard let self, self.isShown, self.app == supported else { return }
            self.model.tabs = TabBridge.assignPaths(to: self.model.tabs, from: paths)
        }
    }

    func hide(animated: Bool = true) {
        guard isShown || panel.isVisible else { return }
        model.presented = false
        removeMonitors()
        orderOutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
        orderOutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.16 : 0), execute: work)
    }

    /// Read paths and thumbnails ahead of time so opening the grid is instant.
    private func prefetch(_ supported: SupportedApp) {
        TabBridge.refreshPaths(of: supported, minInterval: 3) { paths in
            PreviewLoader.shared.prefetch(paths.compactMap(\.url), documents: !supported.showsFolders)
        }
    }

    private func reload() {
        guard isShown, let (tabs, frame) = TabBridge.frontWindowTabs(of: app) else { return }
        model.tabs = tabs
        model.highlighted = min(model.highlighted, max(model.visibleTabs.count - 1, 0))
        panel.setFrame(frame, display: true)
    }

    // MARK: - Keyboard & outside clicks

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) == true ? nil : event
        }
        // Clicking anywhere outside the grid dismisses it.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        keyMonitor = nil
        clickMonitor = nil
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let tabs = model.visibleTabs
        let columns = max(Int((panel.frame.width - 56 + 22) / (230 + 22)), 1)
        let typing = !model.query.isEmpty
        let shortcut = Preferences.shared.triggers(for: app).shortcut
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])

        if event.keyCode == shortcut.keyCode, mods == shortcut.modifiers {
            hide()
            return true
        }
        switch event.keyCode {
        case 53: // esc
            if typing { model.query = "" } else { hide() }
        case 36, 76: // return, enter
            if tabs.indices.contains(model.highlighted) { model.onOpen(tabs[model.highlighted]) }
        case 123 where !typing: // ←
            model.highlighted = max(model.highlighted - 1, 0)
        case 124 where !typing: // →
            model.highlighted = min(model.highlighted + 1, tabs.count - 1)
        case 125: // ↓
            model.highlighted = min(model.highlighted + columns, tabs.count - 1)
        case 126: // ↑
            model.highlighted = max(model.highlighted - columns, 0)
        case 13 where mods == .command: // ⌘W closes the highlighted tab
            if tabs.indices.contains(model.highlighted) { model.onClose(tabs[model.highlighted]) }
        default:
            return false
        }
        return true
    }
}
