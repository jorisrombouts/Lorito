import FluidAudio
import Foundation

/// NVIDIA parakeet-tdt-0.6b-v3, FluidAudio's Core ML build, on the Neural Engine.
actor ParakeetEngine {
    private let asr: AsrManager

    /// First use downloads the models (461 MB) to ~/Library/Application Support/FluidAudio; later loads take 0.1 to 0.2 s.
    init() async throws {
        asr = AsrManager(models: try await AsrModels.downloadAndLoad(version: .v3))
    }

    /// 16 kHz mono samples in, text out. A fresh decoder state per dictation: nothing carries over.
    func transcribe(_ samples: [Float]) async -> String {
        var state = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
        do { return try await asr.transcribe(samples, decoderState: &state).text.trimmingCharacters(in: .whitespacesAndNewlines) }
        catch { NSLog("transcribe failed: %@", error.localizedDescription); return "" }
    }
}
