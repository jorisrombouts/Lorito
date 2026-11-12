import AppKit

/// `Lorito --self-test`: the logic that needs no model, microphone or permission. Runs in CI and in check.sh.
/// A flag in the binary, not a test target: the Command Line Tools cannot load the Swift Testing macros.
@MainActor
enum SelfTest {
    static func run() -> Bool {
        var failures: [String] = []
        func expect(_ ok: Bool, _ what: String) { if !ok { failures.append(what) } }

        // Cleanup guard: an edit passes, an answer, a translation or a summary falls back to the raw text.
        expect(Cleaner.plausible("So I think we should go to the store tomorrow.", for: "So I think we should, uh, go to the store tomorrow."), "guard: filler edit")
        expect(Cleaner.plausible("Send the report to Sarah by Friday.", for: "Send the report to John, no wait, to Sarah by Friday."), "guard: self-correction")
        expect(Cleaner.plausible("Ik wil overmorgen naar de winkel gaan.", for: "Ik wil, eh, morgen naar de winkel gaan. Nee wacht, overmorgen."), "guard: Dutch correction")
        expect(!Cleaner.plausible("The capital of France is Paris, a city known for the Eiffel Tower and its museums.", for: "What is the capital of France?"), "guard: answer")
        expect(!Cleaner.plausible("I want to go to the store tomorrow.", for: "Ik wil morgen naar de winkel gaan."), "guard: translation")
        expect(!Cleaner.plausible("Meeting moved.", for: "So the meeting that we had planned for Monday morning is now moved to Tuesday afternoon instead."), "guard: summary")

        // Cleanup: 1.2's two switches and 1.2.1's Thorough carry over as on or off; a fresh install is untouched.
        let suite = "lorito.selftest.\(UUID())"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        Settings.migrateCleanup(d)
        expect(d.string(forKey: Settings.cleanupKey) == nil, "cleanup: fresh install untouched")
        for (on, polish, level) in [(true, true, CleanupLevel.standard), (true, false, .standard), (false, true, .off), (false, false, .off)] {
            d.removeObject(forKey: Settings.cleanupKey)
            d.set(on, forKey: "cleanupEnabled"); d.set(polish, forKey: "polishEnabled")
            Settings.migrateCleanup(d)
            expect(d.string(forKey: Settings.cleanupKey) == level.rawValue && d.object(forKey: "polishEnabled") == nil,
                   "cleanup: \(on)/\(polish) becomes \(level)")
        }
        d.set("thorough", forKey: Settings.cleanupKey)
        Settings.migrateCleanup(d)
        expect(d.string(forKey: Settings.cleanupKey) == "standard", "cleanup: thorough becomes standard")

        // Hotkeys: one key code and one flag bit each; 1.0's Left Option stays the default.
        expect(Set(Hotkey.allCases.map(\.keyCode)).count == Hotkey.allCases.count, "hotkey: key codes unique")
        expect(Set(Hotkey.allCases.map(\.mask)).count == Hotkey.allCases.count, "hotkey: masks unique")
        expect(Hotkey(rawValue: "nonsense") == nil && Hotkey.leftOption.keyCode == 58, "hotkey: default")

        // Gestures, by event time: a natural tap of 0.35 s starts hands-free (it was a too-short hold under 1.1's 0.3 s limit).
        func gesture(_ steps: [(Character, TimeInterval)]) -> [HotkeyGesture.Result?] {
            var g = HotkeyGesture()
            return steps.map { k, t in k == "d" ? g.down(at: t) : k == "u" ? g.up(at: t) : g.otherKey() }
        }
        expect(gesture([("d", 10), ("u", 10.35)]) == [.press, .tap], "gesture: tap")
        expect(gesture([("d", 10), ("u", 11.2)]) == [.press, .release], "gesture: hold")
        expect(gesture([("d", 10), ("d", 10.1), ("u", 10.2)]) == [.press, nil, .tap], "gesture: repeated down")
        expect(gesture([("d", 10), ("k", 10.1), ("k", 10.2), ("u", 10.3)]) == [.press, .cancel, nil, nil], "gesture: Option-combo")
        expect(gesture([("u", 10), ("k", 10.1), ("d", 11), ("u", 11.1)]) == [nil, nil, .press, .tap], "gesture: stray up")

        // Clipboard: every item and type comes back; an empty clipboard stays empty.
        let pb = NSPasteboard(name: NSPasteboard.Name("lorito.selftest.\(UUID())"))
        defer { pb.releaseGlobally() }
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString("hello", forType: .string)
        item.setData(Data([1, 2, 3]), forType: .png)
        pb.writeObjects([item])
        var saved = TextInserter.snapshot(pb)
        pb.clearContents(); pb.setString("dictated", forType: .string)
        TextInserter.restore(saved, to: pb)
        expect(pb.string(forType: .string) == "hello" && pb.data(forType: .png) == Data([1, 2, 3]), "clipboard: restore all types")
        pb.clearContents()
        saved = TextInserter.snapshot(pb)
        pb.setString("dictated", forType: .string)
        TextInserter.restore(saved, to: pb)
        expect(pb.string(forType: .string) == nil, "clipboard: empty stays empty")

        expect(Chime.start != nil && Chime.stop != nil, "sounds: start and stop load")
        expect(Chime.sound("missing.caf", or: "Tink") != nil, "sounds: a missing file falls back")

        failures.forEach { print("FAIL:", $0) }
        print(failures.isEmpty ? "self-test passed" : "self-test: \(failures.count) failed")
        return failures.isEmpty
    }
}
