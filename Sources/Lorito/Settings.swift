import AppKit
import ServiceManagement

enum Settings {
    static let cleanupKey = "cleanup"
    static var cleanup: CleanupLevel { CleanupLevel(rawValue: UserDefaults.standard.string(forKey: cleanupKey) ?? "") ?? .off }   // off unless chosen
    static var cleanupEnabled: Bool { cleanup != .off }

    /// 1.2 had two switches, "cleanupEnabled" (default on) and "polishEnabled"; 1.2.1 made them one level with
    /// a third, "thorough", since removed. Both become on or off.
    static func migrateCleanup(_ d: UserDefaults = .standard) {
        if d.string(forKey: cleanupKey) == "thorough" { d.set(CleanupLevel.standard.rawValue, forKey: cleanupKey) }
        guard d.string(forKey: cleanupKey) == nil, d.object(forKey: "cleanupEnabled") != nil || d.object(forKey: "polishEnabled") != nil else { return }
        let level: CleanupLevel = d.object(forKey: "cleanupEnabled") as? Bool ?? true ? .standard : .off
        d.set(level.rawValue, forKey: cleanupKey)
        d.removeObject(forKey: "cleanupEnabled"); d.removeObject(forKey: "polishEnabled")
        NSLog("settings: cleanup switches moved to cleanup=%@", level.rawValue)
    }
    static let inputDeviceKey = "inputDeviceUID"   // empty = automatic
    static let hotkeyKey = "hotkey"
    static var hotkey: Hotkey { Hotkey(rawValue: UserDefaults.standard.string(forKey: hotkeyKey) ?? "") ?? .leftOption }
    static let soundsKey = "sounds"
    static var sounds: Bool { UserDefaults.standard.bool(forKey: soundsKey) }
    static let onboardedKey = "onboarded"
    static var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set { try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
    }
}

/// Whether Apple Intelligence edits the transcript. Stored as a string, as 1.2.1's three-level picker was.
enum CleanupLevel: String {
    case off, standard

    var detail: String {
        switch self {
        case .off: "Inserts exactly what was heard."
        case .standard: "Fixes punctuation and drops filler words."
        }
    }
}

/// The key to hold or tap. Modifier keys only: they never type a character, so a hold can wait to see what follows.
/// Left and right are told apart by the device-dependent bits of the modifier flags (IOLLEvent.h `NX_DEVICE*KEYMASK`).
enum Hotkey: String, CaseIterable, Identifiable {
    case leftOption, rightOption, rightCommand, rightControl, fn
    var id: String { rawValue }

    var name: String {
        switch self {
        case .leftOption: "Left Option"
        case .rightOption: "Right Option"
        case .rightCommand: "Right Command"
        case .rightControl: "Right Control"
        case .fn: "Fn (Globe)"
        }
    }

    var keyCode: UInt16 {
        switch self {
        case .leftOption: 58
        case .rightOption: 61
        case .rightCommand: 54
        case .rightControl: 62
        case .fn: 63
        }
    }

    /// The flag bit that is set while this key, and only this key, is down.
    var mask: UInt {
        switch self {
        case .leftOption: 0x20
        case .rightOption: 0x40
        case .rightCommand: 0x10
        case .rightControl: 0x2000
        case .fn: NSEvent.ModifierFlags.function.rawValue
        }
    }
}
