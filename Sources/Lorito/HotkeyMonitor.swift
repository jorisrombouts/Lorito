import AppKit

/// Hold the hotkey (Settings, Left Option by default) to dictate; a tap (under 0.5 s) is reported separately for hands-free mode.
/// Any other key pressed during a hold cancels it, so Option-combos (€, @, accents) never trigger a dictation.
@MainActor
final class HotkeyMonitor {
    static let escapeKeyCode: UInt16 = 53

    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}
    var onCancel: () -> Void = {}
    var onTap: () -> Void = {}
    var onEscape: () -> Void = {}

    private var gesture = HotkeyGesture()
    private var monitors: [Any] = []

    func start() {
        let handle: (NSEvent) -> Void = { [weak self] e in self?.handle(e) }
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: handle) as Any,
            NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { e in handle(e); return e } as Any,
        ]
    }

    private func handle(_ e: NSEvent) {
        let key = Settings.hotkey
        let result: HotkeyGesture.Result?
        switch e.type {
        case .flagsChanged where e.keyCode == key.keyCode:
            result = e.modifierFlags.rawValue & key.mask != 0 ? gesture.down(at: e.timestamp) : gesture.up(at: e.timestamp)
        case .keyDown where gesture.isHeld:
            result = gesture.otherKey()
            if result != nil { NSLog("hotkey: cancelled by key %d", e.keyCode) }
        case .keyDown where e.keyCode == Self.escapeKeyCode:
            result = nil
            onEscape()
        default:
            result = nil
        }
        switch result {
        case .press: onPress()
        case .tap: onTap()
        case .release: onRelease()
        case .cancel: onCancel()
        case nil: break
        }
    }
}

/// Press, tap, release or cancel from the hotkey's down and up times. Times are the events' own timestamps,
/// not the time the handler runs: starting the microphone can hold the main thread past the tap limit.
struct HotkeyGesture {
    /// A release this soon is a tap. A hold this short records under `AudioRecorder.minSeconds` once the
    /// microphone has started, which is discarded anyway, so nothing that would have worked as a hold is lost.
    static let tapSeconds = 0.5
    enum Result { case press, tap, release, cancel }

    private(set) var isHeld = false
    private var cancelled = false
    private var downAt: TimeInterval = 0

    mutating func down(at t: TimeInterval) -> Result? {
        guard !isHeld else { return nil }
        isHeld = true; cancelled = false; downAt = t
        return .press
    }

    mutating func up(at t: TimeInterval) -> Result? {
        guard isHeld else { return nil }
        isHeld = false
        return cancelled ? nil : t - downAt < Self.tapSeconds ? .tap : .release
    }

    mutating func otherKey() -> Result? {
        guard isHeld, !cancelled else { return nil }
        cancelled = true
        return .cancel
    }
}
