import AppKit
import SwiftUI

/// Borderless panel that sits exactly over the front Finder window.
/// Non-activating, so Finder stays the active app while the grid is up.
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
    }

    override var canBecomeKey: Bool { true }
}

final class OverlayController {
    private let panel = OverlayPanel()
    private let model = TabGridModel()
    private var keyMonitor: Any?
    private var clickMonitor: Any?

    var isShown: Bool { panel.isVisible }

    init() {
        panel.contentView = NSHostingView(rootView: TabGridView(model: model))
        model.onOpen = { [weak self] tab in
            FinderBridge.select(tab)
            self?.hide()
        }
        model.onClose = { [weak self] tab in
            FinderBridge.close(tab)
            // Give Finder a beat to drop the tab, then re-read the tab bar.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self?.reload() }
        }
        model.onNewTab = { [weak self] in
            self?.hide()
            FinderBridge.newTab()
        }
        model.onDismiss = { [weak self] in self?.hide() }
    }

    func toggle() { isShown ? hide() : show() }

    func show() {
        guard !isShown, let (tabs, frame) = FinderBridge.frontWindowTabs() else { NSSound.beep(); return }
        model.tabs = tabs
        model.query = ""
        model.highlighted = tabs.firstIndex(where: \.isActive) ?? 0
        model.presented = false
        panel.setFrame(frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { self.model.presented = true }
        installMonitors()
    }

    func hide() {
        guard isShown else { return }
        model.presented = false
        removeMonitors()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, !self.model.presented else { return }
            self.panel.orderOut(nil)
        }
    }

    private func reload() {
        guard isShown, let (tabs, frame) = FinderBridge.frontWindowTabs() else { return }
        model.tabs = tabs
        model.highlighted = min(model.highlighted, max(tabs.count - 1, 0))
        panel.setFrame(frame, display: true)
    }

    // MARK: - Keyboard & outside clicks

    private func installMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) == true ? nil : event
        }
        // Clicking anywhere outside the grid (e.g. back in Finder) dismisses it.
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
        case 42 where event.modifierFlags.contains([.command, .shift]): // ⇧⌘\ again
            hide()
        case 13 where event.modifierFlags.contains(.command): // ⌘W closes the highlighted tab
            if tabs.indices.contains(model.highlighted) { model.onClose(tabs[model.highlighted]) }
        default:
            return false
        }
        return true
    }
}
