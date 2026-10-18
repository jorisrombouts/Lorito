import AppKit
import AVFoundation

let args = CommandLine.arguments
func arg(after flag: String) -> String? { args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }

// Cleanup check: `Lorito --clean "raw text"`
if let raw = arg(after: "--clean") {
    if let r = Cleaner.unavailableReason { print(r); exit(1) }
    let cleaner = Cleaner()
    Task { @MainActor in
        cleaner.warmUp()
        try? await Task.sleep(for: .seconds(2))   // let the model load, or the timeout fires and the check is flaky
        let t0 = Date()
        let out = await cleaner.clean(raw, audioSeconds: Double(raw.count) / 15)   // ~15 chars per second of speech
        print("clean_ms", Int(Date().timeIntervalSince(t0) * 1000), "cleaned", out != nil)
        print("text:", out ?? "(fallback)")
        exit(0)
    }
    RunLoop.main.run()
}

// Engine check: `Lorito --transcribe file.wav`
if let path = arg(after: "--transcribe") {
    let samples = try loadSamples16k(URL(fileURLWithPath: path))
    print("audio_s", Double(samples.count) / 16_000)
    Task {
        let t0 = Date()
        guard let engine = try? await ParakeetEngine() else { print("engine failed"); exit(1) }
        print("load_ms", Int(Date().timeIntervalSince(t0) * 1000))
        let t1 = Date()
        let text = await engine.transcribe(samples)
        print("stt_ms", Int(Date().timeIntervalSince(t1) * 1000))
        print("text:", text)
        exit(0)
    }
    RunLoop.main.run()
}

func loadSamples16k(_ url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: buf)
    return AudioRecorder.resample(buf, with: AVAudioConverter(from: file.processingFormat, to: AudioRecorder.format)!)
}

// Insert self-test: `Lorito --insert-test` pastes a fixed string into the frontmost app after 3 s.
if args.contains("--insert-test") {
    Task { @MainActor in
        try? await Task.sleep(for: .seconds(3))
        print("insert:", TextInserter.insert("hello from Lorito") ?? "posted")
        try? await Task.sleep(for: .seconds(1))
        exit(0)
    }
    RunLoop.main.run()
}

// Normal launch: the menu bar app. stderr (NSLog) goes to ~/Library/Logs/Lorito.log.
let logPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Lorito.log").path
freopen(logPath, "a", stderr)
NSApplication.shared.setActivationPolicy(.accessory)
LoritoApp.main()
