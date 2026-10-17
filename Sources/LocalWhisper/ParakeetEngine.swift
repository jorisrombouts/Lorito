import FluidAudio
import Foundation

/// NVIDIA parakeet-tdt-0.6b-v3 (Core ML build by FluidInference) on the Neural Engine. Replaces whisper on this branch.
actor ParakeetEngine {
    private let asr = AsrManager(config: .default)

    /// Downloads the models to ~/Library/Application Support/FluidAudio on first use (~480 MB), loads them after that.
    init() async throws {
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        try await asr.loadModels(models)
    }

    /// 16 kHz mono float samples in, text out. A fresh decoder state per dictation: nothing carries over.
    func transcribe(_ samples: [Float]) async -> String {
        var state = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
        let text = (try? await asr.transcribe(samples, decoderState: &state).text) ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
