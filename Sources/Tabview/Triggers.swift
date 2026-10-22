import AppKit
import Carbon.HIToolbox

/// ⇧⌘\ — the same shortcut as Safari's "Show All Tabs".
/// Registered only while Finder is frontmost so Safari keeps its own shortcut.
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

    private func update() {
        if FinderBridge.finderIsFrontmost {
            guard ref == nil else { return }
            let id = EventHotKeyID(signature: OSType(0x5442_5657), id: 1) // "TBVW"
            RegisterEventHotKey(UInt32(kVK_ANSI_Backslash), UInt32(cmdKey | shiftKey), id,
                                GetApplicationEventTarget(), 0, &ref)
        } else if let ref {
            UnregisterEventHotKey(ref)
            self.ref = nil
        }
    }
}

/// Watches trackpad pinches system-wide (listen-only, nothing is swallowed).
/// Pinch in over Finder → show the grid; pinch out while it's up → hide it.
/// Needs Accessibility permission.
final class PinchWatcher {
    var onPinchIn: () -> Void = {}
    var onPinchOut: () -> Void = {}
    var isEnabled = true

    private var tap: CFMachPort?
    private var total: CGFloat = 0
    private var firedThisGesture = false
    private let threshold: CGFloat = 0.22

    /// Returns false if the tap couldn't be created (usually: no Accessibility permission yet).
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        // NSEventTypeGesture (29) and NSEventTypeMagnify (30) aren't in CGEventType, so build the mask by hand.
        let mask: CGEventMask = (1 << 29) | (1 << 30)
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, info in
                let watcher = Unmanaged<PinchWatcher>.fromOpaque(info!).takeUnretainedValue()
                watcher.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: me)
        else { return false }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard isEnabled, let ns = NSEvent(cgEvent: event), ns.type == .magnify else { return }

        switch ns.phase {
        case .began:
            total = 0
            firedThisGesture = false
        case .changed:
            total += ns.magnification
            guard !firedThisGesture else { return }
            if total < -threshold {
                firedThisGesture = true
                onPinchIn()
            } else if total > threshold {
                firedThisGesture = true
                onPinchOut()
            }
        default:
            break
        }
    }
}
