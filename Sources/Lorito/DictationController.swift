import AppKit
import AVFoundation
import Carbon.HIToolbox
import Observation
import SwiftUI

/// idle → listening → transcribing → cleaning → done. Owns every component; the UI is a function of `state`.
@MainActor
@Observable
final class DictationController {
    static let shared = DictationController()
    enum State: Equatable {
        case idle, listening, transcribing, cleaning, done
        case fallback(String)
    }

    private(set) var state: State = .idle
    private(set) var level: Float = 0      // 0...1 for the meter, see onLevel below
    private(set) var handsFree = false     // tapped instead of held: keeps listening until the next tap, Esc or ✕
    private var swallowNextTap = false     // the release after the tap that finished a hands-free dictation
    private var generation = 0             // bumped per pill; a delayed finish() of an older one must not end a newer dictation
    private var lastVoice = Date()
    private var smooth: Float = 0
    private var noiseFloor: Float = 0.01
    private var peakHold: Float = 0
    private var levelMax: Float = 0        // logged per dictation
    private(set) var transcripts: [String] = []
    private(set) var problem: String?          // shown in the menu
    private(set) var cleanupUnavailable: String? = Cleaner.unavailableReason

    private let recorder = AudioRecorder()
    private let hotkey = HotkeyMonitor()
    private let cleaner = Cleaner()
    private var engine: ParakeetEngine?
    private var started = false
    @ObservationIgnored private lazy var overlay = RecordingOverlay(controller: self)

    func start() {
        guard !started else { return }
        started = true
        if let dir = arg(after: "--overlay-demo") { demoOverlay(to: dir) }
        recorder.onLevel = { [self] l in Task { @MainActor in
            // Meter like the system ones: nothing below the noise floor, full at the recent peak, fast rise and slow fall.
            // Buffers arrive every 10 ms; room noise per buffer spans 0.0003 to 0.0015, so smooth first.
            // ponytail: constants tuned on the built-in mic at 27% input volume; these are the knobs if another mic misbehaves
            smooth += (l - smooth) * 0.2                                       // ~50 ms window
            if smooth < peakHold * 0.3 { noiseFloor += (smooth - noiseFloor) * 0.02 }
            peakHold = max(smooth, peakHold * 0.995, noiseFloor * 6)
            let rel = max(0, smooth - noiseFloor * 2.5) / max(peakHold - noiseFloor * 2.5, 1e-4)
            level = max(rel, level * 0.93); levelMax = max(levelMax, level)    // ~0.3 s release
            if rel > 0.3 { lastVoice = Date() } else if handsFree, Date().timeIntervalSince(lastVoice) > 120 { release() }
        } }
        recorder.onInterrupted = { [self] _ in if state == .listening { release() } }   // keep what was said before the mic went away
        hotkey.onPress = { [self] in press() }
        hotkey.onRelease = { [self] in release() }
        hotkey.onCancel = { [self] in cancel() }
        hotkey.onTap = { [self] in tap() }
        hotkey.onEscape = { [self] in if handsFree { cancel() } }
        hotkey.start()
        refreshPermissions()
        loadEngine()
        if cleanupUnavailable == nil { cleaner.warmUp() }
        if !UserDefaults.standard.bool(forKey: Settings.onboardedKey) || problem != nil { onboarding.show() }
    }

    enum ModelStatus: Equatable { case loading(Double, String), ready, failed(String) }
    private(set) var model: ModelStatus = .loading(0, "Loading")
    private(set) var micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    private(set) var axTrusted = AXIsProcessTrusted()
    var modelFailed: Bool { if case .failed = model { true } else { false } }
    var ready: Bool { model == .ready && micStatus == .authorized && axTrusted }
    @ObservationIgnored private lazy var onboarding = OnboardingWindow(controller: self)

    /// Loads the engine, downloading the models the first time; called again by Retry after a failure.
    func loadEngine() {
        if case .loading(let f, _) = model, f > 0 { return }   // already on its way
        model = .loading(0, "Loading")
        refreshPermissions()
        Task.detached { [self] in
            let t0 = Date()
            do {
                let e = try await ParakeetEngine { f, what in Task { @MainActor in
                    if case .loading = self.model { self.model = .loading(max(f, 0.01), what) }
                } }
                await MainActor.run { engine = e; model = .ready; refreshPermissions() }
                NSLog("engine ready in %d ms", Int(Date().timeIntervalSince(t0) * 1000))
            } catch {
                NSLog("engine failed: %@", error.localizedDescription)
                await MainActor.run { model = .failed(error.localizedDescription); refreshPermissions() }
            }
        }
    }

    func showOnboarding() { onboarding.show() }

    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in Task { @MainActor in self.refreshPermissions() } }
    }

    /// Shows the system prompt that adds Lorito to the Accessibility list, and opens that list.
    func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func refreshPermissions() {
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        axTrusted = AXIsProcessTrusted()
        problem = !axTrusted ? "Accessibility permission missing (needed to paste)"
            : micStatus == .denied || micStatus == .restricted ? "Microphone access denied"
            : micStatus == .notDetermined ? "Microphone access not granted yet"
            : modelFailed ? "Speech model failed to load" : nil
    }

    private func press() {
        swallowNextTap = false   // left over when the key-up that ended hands-free was cancelled by another key
        if handsFree { release(); swallowNextTap = true; return }
        guard state == .idle || state == .done else { return }
        guard engine != nil else { show(.fallback(modelFailed ? "Speech model failed to load" : "Model still loading")); return }
        if let reason = Self.cannotRecord() { show(.fallback(reason)); return }
        do {
            (smooth, peakHold, levelMax) = (0, 0, 0)   // the first syllable sets the peak; one carried over or started above a soft voice leaves the bars flat until it decays
            try recorder.start()
            generation += 1
            if Settings.cleanupEnabled, cleanupUnavailable == nil { cleaner.warmUp(polish: Settings.polishEnabled) }
            state = .listening
            if Settings.sounds { NSSound(named: "Tink")?.play() }
            overlay.show()
        } catch {
            show(.fallback(error.localizedDescription))
        }
    }

    /// Why a dictation must not start: no microphone access, or a password field (Secure Event Input) has focus.
    static func cannotRecord() -> String? {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted: return "Microphone access denied"
        case .notDetermined: AVCaptureDevice.requestAccess(for: .audio) { _ in }; return "Allow microphone access first"
        default: break
        }
        return IsSecureEventInputEnabled() ? "Secure input is on, not dictating" : nil
    }

    private func tap() {
        if swallowNextTap { swallowNextTap = false; return }
        guard state == .listening else { return }
        handsFree = true
        lastVoice = Date()
    }

    func cancel() {
        guard state == .listening else { return }
        _ = recorder.stop()
        finish()
    }

    private func release() {
        if swallowNextTap { swallowNextTap = false; return }
        guard state == .listening, let engine else { return }
        let mode = handsFree ? "handsfree" : "hold"
        let g = generation
        guard let samples = recorder.stop() else { finish(); return }
        state = .transcribing
        if Settings.sounds { NSSound(named: "Pop")?.play() }
        handsFree = false   // the ✕ belongs to listening only
        Task {
            let t0 = Date()
            let audioSeconds = Double(samples.count) / AudioRecorder.format.sampleRate
            var text = await engine.transcribe(samples)
            let sttMs = ms(since: t0)
            guard !text.isEmpty else { finish(); return }

            var cleanMs = 0, polishMs = 0
            var fellBack = false
            var polish = "off"
            if Settings.cleanupEnabled, cleanupUnavailable == nil, text.split(separator: " ").count >= 4 {
                state = .cleaning
                let t1 = Date()
                if let cleaned = await cleaner.clean(text, audioSeconds: audioSeconds) { text = cleaned } else { fellBack = true }
                cleanMs = ms(since: t1)
                if !fellBack, Settings.polishEnabled {
                    let t3 = Date()
                    (text, polish) = await cleaner.polish(text, audioSeconds: audioSeconds)
                    polishMs = ms(since: t3)
                }
            }

            let t2 = Date()
            let notInserted = TextInserter.insert(text)
            transcripts = Array(([text] + transcripts).prefix(5))
            NSLog("dictation mode=%@ audio_s=%.1f stt_ms=%d clean_ms=%d polish=%@ polish_ms=%d insert_ms=%d fallback=%d meter floor=%.4f peak=%.4f level_max=%.2f",
                  mode, audioSeconds, sttMs, cleanMs, polish, polishMs, ms(since: t2), fellBack ? 1 : 0, noiseFloor, peakHold, levelMax)
            // A failed paste is the one the user must act on, so it outranks a cleanup fallback and holds longer.
            let (next, hold): (State, Int) =
                if let notInserted { (.fallback(notInserted), 2500) }
                else if fellBack { (.fallback("Raw text inserted"), 1500) }
                else { (.done, 700) }
            state = next
            try? await Task.sleep(for: .milliseconds(hold))
            if generation == g { finish() }   // a dictation started on the "done" pill is not ours to end
        }
    }

    private func show(_ s: State) {
        state = s
        generation += 1
        let g = generation
        overlay.show()
        Task { try? await Task.sleep(for: .seconds(1.2)); if generation == g { finish() } }
    }

    private func finish() {
        state = .idle
        handsFree = false
        level = 0
        overlay.hide()
    }

    /// `--overlay-demo <dir>`: render every overlay state to <dir>/overlay-<state>.png and exit.
    func demoOverlay(to dir: String) {
        let states: [(String, State)] = [("listening", .listening), ("transcribing", .transcribing), ("cleaning", .cleaning),
                                         ("done", .done), ("fallback", .fallback("Raw text inserted")),
                                         ("paste-failed", .fallback("Accessibility permission missing"))]
        level = 0.7
        for (name, s) in states + [("listening-handsfree", .listening)] {
            state = s
            handsFree = name.hasSuffix("handsfree")
            let view = NSHostingView(rootView: OverlayView(controller: self).background(.blue.opacity(0.3)))
            view.frame = NSRect(origin: .zero, size: OverlayView.canvas)
            view.layoutSubtreeIfNeeded()
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("overlay-\(name).png"))
            }
        }
        exit(0)
    }

    private func ms(since d: Date) -> Int { Int(Date().timeIntervalSince(d) * 1000) }
}
