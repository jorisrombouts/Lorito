import AppKit
import ServiceManagement

enum Settings {
    static let cleanupKey = "cleanup"
    static var cleanup: CleanupLevel { CleanupLevel(rawValue: UserDefaults.standard.string(forKey: cleanupKey) ?? "") ?? .standard }
    static var cleanupEnabled: Bool { cleanup != .off }
    static var polishEnabled: Bool { cleanup == .thorough }

    /// 1.2 had two switches, "cleanupEnabled" (default on) and "polishEnabled"; they become one level.
    static func migrateCleanup(_ d: UserDefaults = .standard) {
        guard d.string(forKey: cleanupKey) == nil, d.object(forKey: "cleanupEnabled") != nil || d.object(forKey: "polishEnabled") != nil else { return }
        let level = CleanupLevel(cleanup: d.object(forKey: "cleanupEnabled") as? Bool ?? true, polish: d.bool(forKey: "polishEnabled"))
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

/// How much Apple Intelligence edits: not at all, the first pass, or the first pass plus the delete-only tidy-up.
enum CleanupLevel: String, CaseIterable, Identifiable {
    case off, standard, thorough
    var id: String { rawValue }

    init(cleanup: Bool, polish: Bool) { self = !cleanup ? .off : polish ? .thorough : .standard }

    var name: String {
        switch self {
        case .off: "Off"
        case .standard: "Standard"
        case .thorough: "Thorough"
        }
    }

    var detail: String {
        switch self {
        case .off: "Inserts exactly what was heard."
        case .standard: "Fixes punctuation and drops filler words."
        case .thorough: "Also removes repeated sentences and false starts. A moment slower."
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
