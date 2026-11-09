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

        // Polish guard: a deleted run must be filler, a repeat of kept words, or a short abandoned sentence.
        let c = "I think we should move it. We should move it to Friday, basically."
        expect(Cleaner.onlyDeletes("I think we should move it to Friday.", from: c), "polish: repeat and filler")
        expect(Cleaner.onlyDeletes(c.uppercased(), from: c), "polish: capitals only")
        expect(Cleaner.onlyDeletes("Ik wil het abonnement niet opzeggen, alleen pauzeren.",
                                   from: "Ik wil het abonnement niet opzeggen. Ik wil het abonnement niet opzeggen, alleen pauzeren, zeg maar."), "polish: repeat over half the text")
        expect(Cleaner.onlyDeletes("The server runs out of memory.", from: "The problem is. The server runs out of memory."), "polish: abandoned start")
        expect(Cleaner.onlyDeletes("He said fine and don't worry.", from: "He said 'fine' and don’t worry."), "polish: quotes and apostrophes")
        expect(!Cleaner.onlyDeletes("I think we should move it to Thursday.", from: c), "polish: changed word")
        expect(!Cleaner.onlyDeletes("I really think we should move it to Friday.", from: c), "polish: added word")
        expect(!Cleaner.onlyDeletes("We should move it to Friday, I think.", from: c), "polish: reordered")
        expect(!Cleaner.onlyDeletes("Move it.", from: c), "polish: lost content")
        expect(!Cleaner.onlyDeletes("I do want the refund.", from: "I do not want the refund."), "polish: lost negation")
        expect(!Cleaner.onlyDeletes("It costs 3.5 euro.", from: "It costs 3,5 euro."), "polish: number format")
        expect(!Cleaner.onlyDeletes("It costs $40.", from: "It costs €40."), "polish: currency")
        expect(!Cleaner.onlyDeletes("One two three four five.", from: "One two three four five. Six seven eight nine ten."), "polish: lost sentence")
        expect(!Cleaner.onlyDeletes("We moeten de login afmaken.", from: "We moeten dus de login afmaken."), "polish: dus is not filler")
        expect(!Cleaner.onlyDeletes("The test passed.", from: "The test failed. The test passed."), "polish: short sentence is not a fragment")
        expect(!Cleaner.onlyDeletes("We accept the offer.", from: "Yes. We accept the offer."), "polish: yes is kept")
        expect(!Cleaner.onlyDeletes("The client knows.", from: "The client knows. The client knows already."), "polish: kept the shorter copy")
        expect(!Cleaner.onlyDeletes("I do think it's not ready.", from: "I do not think it's not ready."), "polish: repeat must be adjacent")
        expect(!Cleaner.onlyDeletes("Order pizzas and 2 drinks.", from: "Order 2 pizzas and 2 drinks."), "polish: number elsewhere")
        expect(!Cleaner.onlyDeletes("It.", from: "I mean it."), "polish: filler needs a pause")
        expect(!Cleaner.onlyDeletes("Did that work?", from: "Did you know that work?"), "polish: you know in a question")
        expect(!Cleaner.onlyDeletes("We shipped it.", from: "It wouldn't work. We shipped it."), "polish: wouldn't is a negation")
        expect(Cleaner.onlyDeletes("We meet at five.", from: "We meet at five, uh, at five."), "polish: hesitation then repeat")
        expect(Cleaner.onlyDeletes("I reviewed it, we can sign.", from: "I reviewed it, so yeah, we can sign."), "polish: filler set off by commas")
        expect(!Cleaner.onlyDeletes("The tickets are booked.", from: "Not today. The tickets are booked."), "polish: negation fragment")
        let six = "We left early. The train was late. It rained all day. We ate in town. The museum was closed. We went home."
        let emoji = "Thanks 🙏, really. See you 👋 Monday. Bring the slides 📊. Ping me if late. Or text me. Either is fine."
        expect(Cleaner.windows(emoji).joined() == emoji, "polish: windows keep emoji text")
        expect(Cleaner.windows("We left early. The train was late. It rained. We ate.").count == 1, "polish: four sentences, one window")
        expect(Cleaner.windows(six).count == 2 && Cleaner.windows(six).joined() == six, "polish: windows cover the text")

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

        failures.forEach { print("FAIL:", $0) }
        print(failures.isEmpty ? "self-test passed" : "self-test: \(failures.count) failed")
        return failures.isEmpty
    }
}
