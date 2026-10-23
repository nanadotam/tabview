import AppKit
import Carbon.HIToolbox

/// The front app's keyboard shortcut (⇧⌘\ by default, same as Safari's "Show All Tabs").
/// Registered only while a supported app (Finder, Preview) is frontmost so other apps keep their own shortcuts,
/// and re-registered on every app switch since each supported app can have its own.
final class FinderHotKey {
    private var ref: EventHotKeyRef?
    private let action: () -> Void
    private static var current: FinderHotKey?

    init(action: @escaping () -> Void) {
        self.action = action
        FinderHotKey.current = self

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { FinderHotKey.current?.action() }
            return noErr
        }, 1, &spec, nil, nil)

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.update() }
        update()
    }

    /// Call after the shortcut changes in Settings.
    func update() {
        if let ref {
            UnregisterEventHotKey(ref)
            self.ref = nil
        }
        guard let app = SupportedApp.frontmost else { return }
        let triggers = Preferences.shared.triggers(for: app)
        guard triggers.shortcutEnabled else { return }
        let id = EventHotKeyID(signature: OSType(0x5442_5657), id: 1) // "TBVW"
        RegisterEventHotKey(UInt32(triggers.shortcut.keyCode), triggers.shortcut.carbonModifiers, id,
                            GetApplicationEventTarget(), 0, &ref)
    }
}

/// One event tap for every pointer trigger:
/// - trackpad pinch (optionally while holding a modifier), never swallowed
/// - modifier + scroll wheel, for mouse users
/// - an extra mouse button (middle / back / forward)
/// Triggers only fire while the pointer is over a window of the supported app in front (or over the grid itself),
/// using that app's own trigger settings. Needs Accessibility permission.
final class InputWatcher {
    /// "In" = pinch in: show. "Out" = pinch out: hide. Scroll and mouse button toggle.
    var onIn: () -> Void = {}
    var onOut: () -> Void = {}
    var isOverlayShown: () -> Bool = { false }

    private var tap: CFMachPort?
    private var pinchTotal: CGFloat = 0
    private var pinchArmed = false
    private var scrollTotal: CGFloat = 0
    private var scrollFired = false
    private var lastScroll = Date.distantPast
    private var swallowButtonUp = false

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        // NSEventTypeGesture (29) and NSEventTypeMagnify (30) aren't in CGEventType, so build the mask by hand.
        var mask: CGEventMask = (1 << 29) | (1 << 30)
        for type in [CGEventType.scrollWheel, .otherMouseDown, .otherMouseUp] { mask |= 1 << type.rawValue }

        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, info in
                let watcher = Unmanaged<InputWatcher>.fromOpaque(info!).takeUnretainedValue()
                return watcher.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: me)
        else { return false }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// Returns true to swallow the event.
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        default:
            break
        }
        guard let app = SupportedApp.frontmost else { return false }
        let prefs = Preferences.shared.triggers(for: app)
        switch type {

        case .scrollWheel:
            return handleScroll(event, prefs)

        case .otherMouseDown:
            guard prefs.mouseButtonEnabled,
                  event.getIntegerValueField(.mouseEventButtonNumber) == prefs.mouseButton,
                  pointerIsOverSupportedApp(event.location) else { return false }
            swallowButtonUp = true
            isOverlayShown() ? onOut() : onIn()
            return true

        case .otherMouseUp:
            defer { swallowButtonUp = false }
            return swallowButtonUp

        default:
            handlePinch(event, prefs)
            return false
        }
    }

    private func handlePinch(_ event: CGEvent, _ prefs: AppTriggers) {
        guard prefs.pinchEnabled, let ns = NSEvent(cgEvent: event), ns.type == .magnify else { return }
        switch ns.phase {
        case .began:
            pinchTotal = 0
            // Decide once per gesture whether it counts; window lookups are too slow to do every frame.
            pinchArmed = prefs.pinchModifier.matches(event.flags) && pointerIsOverSupportedApp(event.location)
        case .changed:
            guard pinchArmed else { return }
            pinchTotal += ns.magnification
            let threshold = prefs.pinchThreshold
            if pinchTotal < -threshold, !isOverlayShown() {
                pinchArmed = false
                onIn()
            } else if pinchTotal > threshold, isOverlayShown() {
                pinchArmed = false
                onOut()
            }
        default:
            break
        }
    }

    private func handleScroll(_ event: CGEvent, _ prefs: AppTriggers) -> Bool {
        guard prefs.scrollEnabled, prefs.scrollModifier != .none,
              prefs.scrollModifier.matches(event.flags) else { return false }
        let now = Date()
        // A pause between scrolls starts a new "burst"; each burst fires at most once.
        if now.timeIntervalSince(lastScroll) > 0.35 {
            scrollTotal = 0
            scrollFired = false
            guard pointerIsOverSupportedApp(event.location) else { lastScroll = .distantPast; return false }
        }
        lastScroll = now
        guard !scrollFired else { return true }

        let delta = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        scrollTotal += delta
        // Either direction toggles: natural-scrolling settings make "up" and "down" ambiguous anyway.
        if abs(scrollTotal) > 12 {
            scrollFired = true
            isOverlayShown() ? onOut() : onIn()
        }
        return true
    }

    /// Is the topmost window under the pointer one of the front supported app's windows (or our own grid)?
    /// That app also has to be active, so the grid always matches the window you're looking at.
    private func pointerIsOverSupportedApp(_ point: CGPoint) -> Bool {
        guard let target = SupportedApp.frontmost?.running?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let me = ProcessInfo.processInfo.processIdentifier
        for info in windows {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.contains(point) else { continue }
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            if pid == me { return true }
            if layer != 0 { continue } // menu bar, Dock, floating chrome
            return pid == target
        }
        return false
    }
}
