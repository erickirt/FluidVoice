import Foundation
#if arch(arm64)
import FluidAudio

/// TranscriptionProvider implementation for Qwen3-ASR via FluidAudio.
final class QwenAudioProvider: TranscriptionProvider {
    let name = "Qwen3 ASR (FluidAudio)"

    var isAvailable: Bool {
        if #available(macOS 15.0, *) {
            return true
        }
        return false
    }

    private(set) var isReady: Bool = false
    private var managerStorage: Any?

    /// Optional model override retained for API symmetry with other providers.
    var modelOverride: SettingsStore.SpeechModel?

    init(modelOverride: SettingsStore.SpeechModel? = nil) {
        self.modelOverride = modelOverride
    }

    @available(macOS 15.0, *)
    private var manager: Qwen3AsrManager? {
        self.managerStorage as? Qwen3AsrManager
    }

    func prepare(progressHandler: ((Double) -> Void)? = nil) async throws {
        guard self.isAvailable else {
            throw NSError(
                domain: "QwenAudioProvider",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Qwen3 ASR requires macOS 15 or later on Apple Silicon."]
            )
        }

        guard self.isReady == false else { return }

        progressHandler?(0.05)

        if #available(macOS 15.0, *) {
            let modelDirectory = try await Qwen3AsrModels.download()
            progressHandler?(0.75)

            let manager = Qwen3AsrManager()
            try await manager.loadModels(from: modelDirectory)
            self.managerStorage = manager
            self.isReady = true
            progressHandler?(1.0)
            return
        }

        throw NSError(
            domain: "QwenAudioProvider",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "Qwen3 ASR is unavailable on this macOS version."]
        )
    }

    func transcribe(_ samples: [Float]) async throws -> ASRTranscriptionResult {
        try await self.transcribeFinal(samples)
    }

    func transcribeStreaming(_ samples: [Float]) async throws -> ASRTranscriptionResult {
        try await self.transcribeInternal(samples, maxNewTokens: 192)
    }

    func transcribeFinal(_ samples: [Float]) async throws -> ASRTranscriptionResult {
        try await self.transcribeInternal(samples, maxNewTokens: 512)
    }

    private func transcribeInternal(_ samples: [Float], maxNewTokens: Int) async throws -> ASRTranscriptionResult {
        if #available(macOS 15.0, *) {
            guard let manager = self.manager else {
                throw NSError(
                    domain: "QwenAudioProvider",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "Qwen3 ASR manager not initialized."]
                )
            }

            let text = try await manager.transcribe(
                audioSamples: samples,
                language: String?.none,
                maxNewTokens: maxNewTokens
            )
            return ASRTranscriptionResult(text: text, confidence: 1.0)
        }

        throw NSError(
            domain: "QwenAudioProvider",
            code: -4,
            userInfo: [NSLocalizedDescriptionKey: "Qwen3 ASR is unavailable on this macOS version."]
        )
    }

    func modelsExistOnDisk() -> Bool {
        if #available(macOS 15.0, *) {
            return Qwen3AsrModels.modelsExist(at: Qwen3AsrModels.defaultCacheDirectory())
        }
        return false
    }

    func clearCache() async throws {
        if #available(macOS 15.0, *) {
            let cacheDirectory = Qwen3AsrModels.defaultCacheDirectory()
            if FileManager.default.fileExists(atPath: cacheDirectory.path) {
                try FileManager.default.removeItem(at: cacheDirectory)
            }
        }

        self.isReady = false
        self.managerStorage = nil
    }
}
#else
/// Intel fallback for Qwen3-ASR.
final class QwenAudioProvider: TranscriptionProvider {
    let name = "Qwen3 ASR (Apple Silicon ONLY)"
    var isAvailable: Bool { false }
    var isReady: Bool { false }

    init(modelOverride: SettingsStore.SpeechModel? = nil) {
        // Intel stub - parameter ignored
    }

    func prepare(progressHandler: ((Double) -> Void)?) async throws {
        throw NSError(
            domain: "QwenAudioProvider",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Qwen3 ASR is not supported on Intel Macs."]
        )
    }

    func transcribe(_ samples: [Float]) async throws -> ASRTranscriptionResult {
        throw NSError(
            domain: "QwenAudioProvider",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Qwen3 ASR is not supported on Intel Macs."]
        )
    }
}
#endif
