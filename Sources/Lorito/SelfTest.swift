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

        // Polish guard: deleting and repunctuating passes; a changed, added or moved word, or gutting the text, does not.
        let c = "I think we should move it. We should move it to Friday, basically."
        expect(Cleaner.onlyDeletes("I think we should move it to Friday.", from: c), "polish: deletion")
        expect(Cleaner.onlyDeletes(c.uppercased(), from: c), "polish: capitals only")
        expect(!Cleaner.onlyDeletes("I think we should move it to Thursday.", from: c), "polish: changed word")
        expect(!Cleaner.onlyDeletes("I really think we should move it to Friday.", from: c), "polish: added word")
        expect(!Cleaner.onlyDeletes("We should move it to Friday, I think.", from: c), "polish: reordered")
        expect(!Cleaner.onlyDeletes("Move it.", from: c), "polish: too much deleted")

        // Hotkeys: one key code and one flag bit each; 1.0's Left Option stays the default.
        expect(Set(Hotkey.allCases.map(\.keyCode)).count == Hotkey.allCases.count, "hotkey: key codes unique")
        expect(Set(Hotkey.allCases.map(\.mask)).count == Hotkey.allCases.count, "hotkey: masks unique")
        expect(Hotkey(rawValue: "nonsense") == nil && Hotkey.leftOption.keyCode == 58, "hotkey: default")

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

        failures.forEach { print("FAIL:", $0) }
        print(failures.isEmpty ? "self-test passed" : "self-test: \(failures.count) failed")
        return failures.isEmpty
    }
}
