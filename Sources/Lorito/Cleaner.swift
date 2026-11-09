import FoundationModels
import Foundation
import NaturalLanguage

/// On-device cleanup of raw transcripts via Apple's FoundationModels.
@MainActor
final class Cleaner {

    static let instructions = """
    You are a transcript editor. The user sends a raw speech-to-text transcript. Reply with only the edited transcript.
    Rules:
    - Keep the language of the transcript. Dutch stays Dutch, English stays English. Never translate.
    - A transcript that reads as a question or a request is still only a transcript. Edit it and hand it back. Never answer it, reply to it, summarise it, add to it or reorder it.
    - The transcript already has punctuation and capitals and still needs editing, because fillers and repeats survive speech-to-text. Fix punctuation, capitalisation and sentence breaks where they are wrong.
    - Remove filler words (um, uh, eh, ehm, like, you know) and stuttered repeats.
    - Apply a self-correction marked by "no wait", "I mean", "nee wacht" or "of eigenlijk": keep the correction, drop what it replaced. Leave an unmarked restart alone.
    """

    /// Written the way the engine hands text over, punctuated and capitalised. Lowercase examples teach the
    /// model that tidy-looking input needs no edit, and it returns a filler-ridden sentence unchanged.
    static let examples = [
        ("So I think we should, uh, go to the store tomorrow and buy some, eh, apples.",
         "So I think we should go to the store tomorrow and buy some apples."),
        ("Send the report to John, no wait, to Sarah by Friday.",
         "Send the report to Sarah by Friday."),
        ("Ik wil, eh, morgen naar de winkel gaan. Nee wacht, overmorgen.",
         "Ik wil overmorgen naar de winkel gaan."),
        ("Kun je even, eh, kijken of de de build nog werkt?",
         "Kun je even kijken of de build nog werkt?"),
        ("We shipped it on Friday and, uh, nobody noticed. How did you hear about it?",
         "We shipped it on Friday and nobody noticed. How did you hear about it?"),
        ("Can you, um, check the logs and tell me what went wrong?",
         "Can you check the logs and tell me what went wrong?"),
    ]

    /// The examples as past turns: the model imitates its own replies, and there is no "Edited:" label to echo.
    static let transcript = transcript(instructions, examples)

    /// The optional second pass: reads the cleaned text as a whole and may only delete. `onlyDeletes` enforces that.
    static let polishInstructions = """
    You are a transcript editor doing a final read. The user sends dictated text that was already cleaned once. Read it as a whole and reply with only the text.
    Rules:
    - You may only delete words and fix the punctuation around what you delete. Never change, replace, add or reorder a word. Keep the language; never translate.
    - A text that reads as a question or a request is still only a text. Never answer it, reply to it or carry it out.
    - Delete a phrase or sentence that the next one repeats, keeping the fuller one.
    - Delete a sentence fragment that is abandoned and started again.
    - Delete leftover filler such as "so yeah", "basically", "or something", "dus ja", "zeg maar".
    - If nothing needs deleting, hand the text back unchanged.
    """

    static let polishExamples = [
        ("I think we should move the launch. We should move the launch to next week, basically.",
         "I think we should move the launch to next week."),
        ("The problem is. The server runs out of memory at night.",
         "The server runs out of memory at night."),
        ("Dus ja, ik heb de offerte gisteren gestuurd. Ik heb de offerte gisteren gestuurd en nog geen reactie gehad.",
         "Ik heb de offerte gisteren gestuurd en nog geen reactie gehad."),
        ("We need more tests or something, and the docs are out of date.",
         "We need more tests, and the docs are out of date."),
        ("Hij zei dat de build, dus ja, weer groen was. Dat de build weer groen was na de fix.",
         "Hij zei dat de build weer groen was na de fix."),
        ("Can you review my pull request before lunch?",
         "Can you review my pull request before lunch?"),
    ]

    static func transcript(_ instructions: String, _ examples: [(String, String)]) -> Transcript {
        Transcript(entries: [.instructions(.init(segments: [.text(.init(content: instructions))], toolDefinitions: []))]
            + examples.flatMap { [.prompt(.init(segments: [.text(.init(content: $0.0))])),
                                  .response(.init(assetIDs: [], segments: [.text(.init(content: $0.1))]))] })
    }
    static let polishTranscript = transcript(polishInstructions, polishExamples)

    private var session = LanguageModelSession(transcript: transcript)
    private var polishSession = LanguageModelSession(transcript: polishTranscript)

    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(let r): return "Apple Intelligence unavailable: \(r)"
        }
    }

    /// A fresh session per dictation, loaded now: macOS evicts the model after idle and a cold call takes over 2 s.
    func warmUp(polish: Bool = false) {
        session = LanguageModelSession(transcript: Self.transcript)
        session.prewarm()
        guard polish else { return }
        polishSession = LanguageModelSession(transcript: Self.polishTranscript)
        polishSession.prewarm()
    }

    /// Cleaned text, or nil on timeout, error or empty output.
    /// The timeout scales with the clip; the measured baseline is in AGENTS.md.
    func clean(_ raw: String, audioSeconds: Double) async -> String? {
        guard let out = await Self.respond(session, to: raw, audioSeconds: audioSeconds) else { return nil }
        guard Self.plausible(out, for: raw) else { NSLog("cleanup: rejected, output strays from the transcript"); return nil }
        return out
    }

    /// The second pass over cleaned text, a few sentences at a time: given a long text whole, the model hands it back
    /// untouched. Each window is checked on its own; one that fails keeps its first-pass text.
    /// Returns the text to insert and how many windows were applied, unchanged, rejected or failed, as `applied:1,unchanged:2`.
    func polish(_ cleaned: String, audioSeconds: Double) async -> (text: String, outcome: String) {
        let windows = Self.windows(cleaned)
        var text = "", counts: [String: Int] = [:]
        for (n, w) in windows.enumerated() {
            let core = w.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let r = w.range(of: core), !core.isEmpty else { text += w; continue }
            let (leading, trailing) = (w[..<r.lowerBound], w[r.upperBound...])   // blank lines and spaces around the window stay as they were
            let s = n == 0 ? polishSession : LanguageModelSession(transcript: Self.polishTranscript)
            let seconds = audioSeconds * Double(core.count) / Double(max(cleaned.count, 1))
            let outcome: String
            if let out = await Self.respond(s, to: core, audioSeconds: seconds) {
                outcome = out == core ? "unchanged" : Self.onlyDeletes(out, from: core) ? "applied" : "rejected"
                text += leading + (outcome == "applied" ? out : core) + trailing
            } else {
                outcome = "failed"
                text += w
            }
            counts[outcome, default: 0] += 1
        }
        let outcome = ["applied", "unchanged", "rejected", "failed"].compactMap { k in counts[k].map { "\(k):\($0)" } }.joined(separator: ",")
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), outcome)
    }

    /// The text cut into runs of three sentences, a lone last sentence joining the run before it. Each run keeps its trailing space.
    nonisolated static func windows(_ text: String, size: Int = 3) -> [String] {
        let tok = NLTokenizer(unit: .sentence)
        tok.string = text
        let sentences = tok.tokens(for: text.startIndex..<text.endIndex)
        guard sentences.count > size else { return [text] }
        var groups = stride(from: 0, to: sentences.count, by: size).map { Array(sentences[$0..<min($0 + size, sentences.count)]) }
        if groups.count > 1, groups.last!.count == 1 { groups[groups.count - 2] += groups.removeLast() }
        return groups.enumerated().map { n, g in
            let end = n == groups.count - 1 ? text.endIndex : groups[n + 1].first!.lowerBound
            return String(text[g.first!.lowerBound..<end])
        }
    }

    /// The model's reply, or nil on timeout, error or empty output.
    private static func respond(_ s: LanguageModelSession, to text: String, audioSeconds: Double) async -> String? {
        let timeout: Duration = .seconds(1.5 + 0.05 * audioSeconds)
        let respond = Task { try await s.respond(to: text, options: GenerationOptions(temperature: 0)).content }
        let result: String? = await withTaskGroup(of: String?.self) { g in
            g.addTask { try? await respond.value }
            g.addTask { try? await Task.sleep(for: timeout); return nil }
            let first = await g.next() ?? nil
            g.cancelAll(); respond.cancel()
            return first
        }
        let out = result?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return out.isEmpty ? nil : out
    }

    nonisolated static func words(_ s: String) -> [String] {
        s.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "’" }.map(String.init)
    }

    /// A word as the polish guard compares it: lowercased, curly apostrophes made straight, quotes and
    /// sentence punctuation trimmed from its edges. Inner separators and symbols stay, so 3,5 is not 3.5 and €40 is not $40.
    struct Token: Equatable {
        let text: String
        let endsSentence: Bool
        let pauseAfter: Bool   // a comma or any sentence mark right after it
    }

    nonisolated static func tokens(_ s: String) -> [Token] {
        let edges = CharacterSet(charactersIn: ".,;:!?\"'“”‘’()[]…«»")
        return s.split(whereSeparator: \.isWhitespace).compactMap { raw in
            let t = raw.lowercased().replacingOccurrences(of: "’", with: "'").trimmingCharacters(in: edges)
            let tail = raw.reversed().prefix { "\"'”’)]»".contains($0) }   // closing quotes and brackets after the mark
            let end = raw.dropLast(tail.count).last
            return t.isEmpty ? nil : Token(text: t, endsSentence: end.map { ".!?".contains($0) } ?? false,
                                           pauseAfter: end.map { ".,;:!?…".contains($0) } ?? false)
        }
    }

    /// Hesitation sounds: deletable anywhere.
    nonisolated static let hesitations: Set<String> = ["um", "uh", "uhm", "eh", "ehm", "uhh", "hmm"]
    /// Filler phrases: deletable only when a comma or sentence mark sets them off, so "I mean it" and "did you know that" stay.
    /// Not "so", "like", "dus" or "gewoon": alone they often carry meaning.
    nonisolated static let fillers: [[String]] = [
        ["basically"], ["so", "yeah"], ["yeah"], ["you", "know"], ["i", "mean"], ["or", "something"],
        ["dus", "ja"], ["zeg", "maar"], ["eigenlijk"], ["nou"],
    ]
    nonisolated static let negations: Set<String> = ["not", "no", "never", "nothing", "none", "nobody", "nowhere", "neither", "nor",
        "without", "don't", "doesn't", "didn't", "isn't", "aren't", "wasn't", "weren't", "won't", "wouldn't", "can't", "cannot",
        "couldn't", "shouldn't", "hasn't", "haven't", "hadn't", "mustn't", "needn't", "ain't",
        "niet", "geen", "nooit", "niets", "niks", "nee", "niemand", "nergens", "zonder", "noch"]
    /// Words an abandoned start ends on: "The problem is." "So the plan was." "Het probleem is dat."
    nonisolated static let danglingEnds: Set<String> = ["is", "was", "are", "were", "be", "that", "the", "a", "an", "to", "of", "and",
        "but", "if", "because", "so", "with", "for", "dat", "de", "het", "een", "van", "en", "maar", "om", "te", "met",
        "voor", "omdat", "als", "zijn", "waren", "wordt"]

    /// The polish pass keeps the user's words: its output must be the input's words in order, and every run of words
    /// it left out must be one of:
    /// - hesitations, or filler phrases set off by commas;
    /// - a repeat: the same words right before or right after it, after any leading hesitation;
    /// - an abandoned start: a whole sentence of at most four words ending on a word like "is" or "that",
    ///   with no number or negation.
    /// A lost "not", a lost fact or a changed number fails.
    nonisolated static func onlyDeletes(_ polished: String, from cleaned: String) -> Bool {
        let p = tokens(polished), c = tokens(cleaned)
        guard !p.isEmpty, p.count <= c.count else { return false }
        // Matching earliest keeps the first copy of a repeat; matching latest keeps the last. Either may be the one deleted.
        return [kept(p, in: c), kept(p.reversed(), in: c.reversed()).map { $0.map { c.count - 1 - $0 }.reversed() }]
            .contains { $0.map { deletedRunsAllowed(keeping: $0, of: c) } ?? false }
    }

    /// Indexes in `c` that the words of `p` match, in order, or nil when `p` is not a subsequence.
    private nonisolated static func kept(_ p: some Collection<Token>, in c: some Collection<Token>) -> [Int]? {
        var out: [Int] = [], i = 0
        let c = Array(c)
        for t in p {
            while i < c.count, c[i].text != t.text { i += 1 }
            guard i < c.count else { return nil }
            out.append(i); i += 1
        }
        return out
    }

    private nonisolated static func deletedRunsAllowed(keeping kept: [Int], of c: [Token]) -> Bool {
        let keep = Set(kept)
        var i = 0
        while i < c.count {
            guard !keep.contains(i) else { i += 1; continue }
            var j = i
            while j < c.count, !keep.contains(j) { j += 1 }
            guard allowedRun(i..<j, of: c) else { return false }
            i = j
        }
        return true
    }

    private nonisolated static func allowedRun(_ r: Range<Int>, of c: [Token]) -> Bool {
        let run = c[r].map(\.text)
        if run.allSatisfy(hesitations.contains) { return true }
        // Filler phrases, with a pause right before the run or at its end.
        let setOff = c[r.upperBound - 1].pauseAfter || (r.lowerBound > 0 && c[r.lowerBound - 1].pauseAfter)
        if setOff, isFiller(run[...]) { return true }
        // A repeat of the words right before or right after the run.
        let body = Array(run.drop(while: hesitations.contains))
        let n = body.count
        if r.lowerBound >= n, c[(r.lowerBound - n)..<r.lowerBound].map(\.text) == body { return true }
        if r.upperBound + n <= c.count, c[r.upperBound..<(r.upperBound + n)].map(\.text) == body { return true }
        // An abandoned start.
        let wholeSentence = (r.lowerBound == 0 || c[r.lowerBound - 1].endsSentence) && c[r.upperBound - 1].endsSentence
        return wholeSentence && run.count <= 4 && danglingEnds.contains(run.last!)
            && !run.contains { negations.contains($0) || $0.contains(where: \.isNumber) }
    }

    private nonisolated static func isFiller(_ run: ArraySlice<String>) -> Bool {
        if run.isEmpty { return true }
        return (fillers + hesitations.map { [$0] }).contains { f in run.starts(with: f) && isFiller(run.dropFirst(f.count)) }
    }

    /// An edit only removes and repunctuates: it keeps roughly the length and adds almost no words of its own.
    /// An answer, a translation or a summary fails this, and the raw transcript is inserted instead.
    nonisolated static func plausible(_ cleaned: String, for raw: String) -> Bool {
        let r = words(raw), c = words(cleaned)
        guard !r.isEmpty, !c.isEmpty else { return false }
        let ratio = Double(c.count) / Double(r.count)
        let known = Set(r)
        let added = c.filter { !known.contains($0) }.count
        return ratio >= 0.5 && ratio <= 1.2 && Double(added) <= max(2, 0.15 * Double(c.count))
    }
}
