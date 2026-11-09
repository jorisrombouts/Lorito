import FluidAudio
import Foundation

/// NVIDIA parakeet-tdt-0.6b-v3, FluidAudio's Core ML build, on the Neural Engine.
actor ParakeetEngine {
    private let asr: AsrManager

    /// First use downloads the models (461 MB) to ~/Library/Application Support/FluidAudio; later loads take 0.1 to 0.2 s.
    /// `progress` gets a fraction and what is happening, on FluidAudio's download thread.
    init(progress: (@Sendable (Double, String) -> Void)? = nil) async throws {
        var handler: ProgressHandler?
        if let progress {
            handler = { @Sendable (p: DownloadProgress) in progress(p.fractionCompleted, Self.describe(p.phase)) }
        }
        asr = AsrManager(models: try await AsrModels.downloadAndLoad(version: .v3, progressHandler: handler))
    }

    private static func describe(_ phase: DownloadPhase) -> String {
        switch phase {
        case .listing: "Connecting"
        case .downloading(let done, let total): "Downloading, file \(min(done + 1, total)) of \(total)"
        case .compiling: "Preparing for the Neural Engine"
        }
    }

    /// 16 kHz mono samples in, text out. A fresh decoder state per dictation: nothing carries over.
    func transcribe(_ samples: [Float]) async -> String {
        var state = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
        do { return try await asr.transcribe(samples, decoderState: &state).text.trimmingCharacters(in: .whitespacesAndNewlines) }
        catch { NSLog("transcribe failed: %@", error.localizedDescription); return "" }
    }
}
