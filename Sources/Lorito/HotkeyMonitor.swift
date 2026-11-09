import AppKit

/// Hold the hotkey (Settings, Left Option by default) to dictate; a tap (under 0.3 s) is reported separately for hands-free mode.
/// Any other key pressed during a hold cancels it, so Option-combos (€, @, accents) never trigger a dictation.
@MainActor
final class HotkeyMonitor {
    static let escapeKeyCode: UInt16 = 53
    static let tapSeconds = 0.3

    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}
    var onCancel: () -> Void = {}
    var onTap: () -> Void = {}
    var onEscape: () -> Void = {}

    private var isHeld = false
    private var cancelled = false
    private var pressedAt = Date()
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
        switch e.type {
        case .flagsChanged where e.keyCode == key.keyCode:
            let down = e.modifierFlags.rawValue & key.mask != 0
            if down, !isHeld {
                isHeld = true; cancelled = false; pressedAt = Date()
                onPress()
            } else if !down, isHeld {
                isHeld = false
                if !cancelled { Date().timeIntervalSince(pressedAt) < Self.tapSeconds ? onTap() : onRelease() }
            }
        case .keyDown where isHeld && !cancelled:
            cancelled = true
            NSLog("hotkey: cancelled by key %d after %d ms", e.keyCode, Int(Date().timeIntervalSince(pressedAt) * 1000))
            onCancel()
        case .keyDown where e.keyCode == Self.escapeKeyCode:
            onEscape()
        default:
            break
        }
    }
}
