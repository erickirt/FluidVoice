import Foundation
#if arch(arm64)
import AVFoundation
import FluidAudio

private actor DownloadProgressSink {
    private let handler: ((Double) -> Void)?

    init(handler: ((Double) -> Void)?) {
        self.handler = handler
    }

    func emit(_ progress: Double) {
        self.handler?(progress)
    }
}

/// TranscriptionProvider implementation using FluidAudio (optimized for Apple Silicon)
/// This wraps the existing FluidAudio-based ASR for use on Apple Silicon Macs.
final class FluidAudioProvider: TranscriptionProvider {
    let name = "FluidAudio (Apple Silicon Optimized)"

    /// Whether this provider is supported on the current system.
    /// FluidAudio is optimized for Apple Silicon, but may still function on Intel.
    var isAvailable: Bool {
        true
    }

    private var streamingAsrManager: AsrManager?
    private var finalAsrManager: AsrManager?
    private var slidingWindowManager: SlidingWindowAsrManager?
    private var loadedModels: AsrModels?
    private var streamedSampleCount: Int = 0
    private var latestStreamingPreviewText: String = ""
    private var vocabularyBundle: (vocabulary: CustomVocabularyContext, ctcModels: CtcModels)?
    private(set) var isReady: Bool = false
    private(set) var isWordBoostingActive: Bool = false
    private(set) var boostedVocabularyTermsCount: Int = 0
    private var boostedTermLookup: [String] = []

    /// Optional model override - if set, uses this model instead of the global setting.
    /// Used for downloading specific models without changing the active selection.
    var modelOverride: SettingsStore.SpeechModel?
    private let configureWordBoosting: Bool

    init(modelOverride: SettingsStore.SpeechModel? = nil, configureWordBoosting: Bool = true) {
        self.modelOverride = modelOverride
        self.configureWordBoosting = configureWordBoosting
    }

    func prepare(progressHandler: ((Double) -> Void)? = nil) async throws {
        guard self.isReady == false else { return }

        let selectedModel = self.modelOverride ?? SettingsStore.shared.selectedSpeechModel
        let modelVersion: String = selectedModel == .parakeetTDTv2 ? "v2" : "v3"
        let cacheDirectory = AsrModels.defaultCacheDirectory().deletingLastPathComponent()
        DebugLogger.shared.info(
            "FluidAudioProvider: Starting model preparation for \(selectedModel.displayName) [version=\(modelVersion)]",
            source: "FluidAudioProvider"
        )
        DebugLogger.shared.debug("FluidAudioProvider: target cache directory=\(cacheDirectory.path)", source: "FluidAudioProvider")
        let progressSink = DownloadProgressSink(handler: progressHandler)
        await progressSink.emit(0.05)

        // AsrModels.downloadAndLoad() is a single await without granular callbacks.
        // Emit synthetic incremental progress so the UI updates smoothly during long downloads.
        let progressTicker = Task(priority: .utility) {
            var stagedProgress = 0.05
            let stageCap = 0.82
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if Task.isCancelled { break }
                if stagedProgress >= stageCap { continue }

                let remaining = stageCap - stagedProgress
                let step = max(0.008, remaining * 0.12)
                stagedProgress = min(stageCap, stagedProgress + step)
                await progressSink.emit(stagedProgress)
            }
        }
        defer { progressTicker.cancel() }

        let loadStart = Date()
        // Download and load models
        let models: AsrModels
        if selectedModel == .parakeetTDTv2 {
            // Explicitly load v2 (English Only)
            models = try await AsrModels.downloadAndLoad(version: .v2)
        } else {
            // Default to v3 (Multilingual)
            models = try await AsrModels.downloadAndLoad(version: .v3)
        }
        self.loadedModels = models
        progressTicker.cancel()
        DebugLogger.shared.debug(
            "FluidAudioProvider: Models downloadAndLoad returned in \(String(format: "%.2f", Date().timeIntervalSince(loadStart)))s",
            source: "FluidAudioProvider"
        )
        await progressSink.emit(0.88)

        // Streaming manager: lightweight, no vocab boosting → avoids CTC/ANE contention
        // that causes intermittent SIGTRAP crashes during streaming inference.
        let streamingManager = AsrManager(config: ASRConfig.default)
        try await streamingManager.initialize(models: models)
        DebugLogger.shared.debug("FluidAudioProvider: Streaming AsrManager initialized", source: "FluidAudioProvider")
        await progressSink.emit(0.94)

        self.isWordBoostingActive = false
        self.boostedVocabularyTermsCount = 0
        self.boostedTermLookup = []

        // Final manager: separate instance with vocab boosting for end-of-recording rescoring.
        // Shares the same underlying MLModel objects (reference types) so memory overhead
        // is only the decoder state (~100KB).
        let finalManager: AsrManager
        if self.configureWordBoosting {
            do {
                if let vocabBundle = try await ParakeetVocabularyStore.shared.loadTokenizedVocabularyBundle() {
                    self.vocabularyBundle = vocabBundle
                    DebugLogger.shared.debug(
                        "FluidAudioProvider: Vocabulary bundle loaded with \(vocabBundle.vocabulary.terms.count) terms",
                        source: "FluidAudioProvider"
                    )
                    let boostedManager = AsrManager(config: ASRConfig.default)
                    try await boostedManager.initialize(models: models)
                    try await boostedManager.configureVocabularyBoosting(
                        vocabulary: vocabBundle.vocabulary,
                        ctcModels: vocabBundle.ctcModels
                    )
                    self.isWordBoostingActive = true
                    self.boostedVocabularyTermsCount = vocabBundle.vocabulary.terms.count
                    self.boostedTermLookup = Self.makeBoostedTermLookup(from: vocabBundle.vocabulary.terms)
                    DebugLogger.shared.info(
                        "FluidAudioProvider: Enabled vocabulary boosting with \(self.boostedVocabularyTermsCount) terms (final only)",
                        source: "FluidAudioProvider"
                    )
                    finalManager = boostedManager
                } else {
                    DebugLogger.shared.debug("FluidAudioProvider: No vocabulary boost terms found; using base ASR manager", source: "FluidAudioProvider")
                    finalManager = streamingManager
                }
            } catch {
                DebugLogger.shared.warning("FluidAudioProvider: Failed to configure vocabulary boosting: \(error)", source: "FluidAudioProvider")
                finalManager = streamingManager
            }
        } else {
            DebugLogger.shared.debug("FluidAudioProvider: Word boosting disabled by configuration", source: "FluidAudioProvider")
            finalManager = streamingManager
        }

        self.streamingAsrManager = streamingManager
        self.finalAsrManager = finalManager
        self.slidingWindowManager = nil
        self.streamedSampleCount = 0
        self.latestStreamingPreviewText = ""
        await progressSink.emit(0.98)

        self.isReady = true
        await progressSink.emit(1.0)
        DebugLogger.shared.info(
            "FluidAudioProvider: Models ready [isWordBoostingActive=\(self.isWordBoostingActive), terms=\(self.boostedVocabularyTermsCount)]",
            source: "FluidAudioProvider"
        )
    }

    func transcribe(_ samples: [Float]) async throws -> ASRTranscriptionResult {
        try await self.transcribeFinal(samples)
    }

    func transcribeStreaming(_ samples: [Float]) async throws -> ASRTranscriptionResult {
        guard let fullPreviewManager = self.streamingAsrManager else {
            throw NSError(
                domain: "FluidAudioProvider",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "ASR manager not initialized"]
            )
        }

        let startedAt = Date().timeIntervalSince1970
        let slidingManager = try await self.ensureSlidingWindowManager()
        let delta = try await self.consumeStreamingDelta(from: samples)
        if !delta.isEmpty {
            try await slidingManager.streamAudio(self.createPCMBuffer(from: delta))
        }
        let result = try await fullPreviewManager.transcribe(samples, source: AudioSource.microphone)
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.latestStreamingPreviewText = text
        let elapsedMs = Int(((Date().timeIntervalSince1970 - startedAt) * 1000).rounded())
        let audioMs = Int((Double(samples.count) / 16_000.0 * 1000).rounded())
        let rtf = audioMs > 0 ? Double(elapsedMs) / Double(audioMs) : 0
        DebugLogger.shared.info(
            """
            ASR_BENCH provider_streaming_done samples=\(samples.count) audioMs=\(audioMs) \
            elapsedMs=\(elapsedMs) textChars=\(text.trimmingCharacters(in: .whitespacesAndNewlines).count) \
            rtf=\(String(format: "%.3f", rtf))
            """,
            source: "ASRBenchmark"
        )
        return ASRTranscriptionResult(text: result.text, confidence: result.confidence)
    }

    func transcribeFinal(_ samples: [Float]) async throws -> ASRTranscriptionResult {
        guard let manager = self.finalAsrManager ?? self.streamingAsrManager else {
            throw NSError(
                domain: "FluidAudioProvider",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "ASR manager not initialized"]
            )
        }

        let startedAt = Date().timeIntervalSince1970
        do {
            if let slidingResult = try await self.finishSlidingWindowTranscription(samples),
               self.shouldUseSlidingWindowFinal(slidingResult.text)
            {
                self.logFinalBenchmark(samples: samples, text: slidingResult.text, startedAt: startedAt, usedFallback: false)
                return slidingResult
            }
        } catch {
            DebugLogger.shared.warning(
                "ASR_BENCH provider_sliding_rejected reason=error error=\(error.localizedDescription)",
                source: "ASRBenchmark"
            )
        }

        // If the boosted final manager fails, fall back to the unboosted streaming
        // manager so the user still gets a transcription (just without CTC rescoring).
        do {
            let startedAt = Date().timeIntervalSince1970
            let result = try await manager.transcribe(samples, source: AudioSource.microphone)
            self.logFinalBenchmark(samples: samples, text: result.text, startedAt: startedAt, usedFallback: false)
            return ASRTranscriptionResult(text: result.text, confidence: result.confidence)
        } catch {
            guard let fallback = self.streamingAsrManager, fallback !== manager else {
                throw error
            }
            DebugLogger.shared.warning(
                "FluidAudioProvider: Boosted final transcription failed (\(error.localizedDescription)), retrying without vocab boost",
                source: "FluidAudioProvider"
            )
            let startedAt = Date().timeIntervalSince1970
            let result = try await fallback.transcribe(samples, source: AudioSource.microphone)
            self.logFinalBenchmark(samples: samples, text: result.text, startedAt: startedAt, usedFallback: true)
            return ASRTranscriptionResult(text: result.text, confidence: result.confidence)
        }
    }

    private func ensureSlidingWindowManager() async throws -> SlidingWindowAsrManager {
        if let slidingWindowManager {
            return slidingWindowManager
        }
        guard let loadedModels else {
            throw NSError(
                domain: "FluidAudioProvider",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "ASR models not initialized"]
            )
        }

        let manager = SlidingWindowAsrManager(config: .streaming)
        if let vocabularyBundle {
            try await manager.configureVocabularyBoosting(
                vocabulary: vocabularyBundle.vocabulary,
                ctcModels: vocabularyBundle.ctcModels
            )
        }
        try await manager.start(models: loadedModels, source: .microphone)
        self.slidingWindowManager = manager
        self.streamedSampleCount = 0
        self.latestStreamingPreviewText = ""
        return manager
    }

    private func consumeStreamingDelta(from samples: [Float]) async throws -> [Float] {
        if samples.count < self.streamedSampleCount {
            await self.slidingWindowManager?.cancel()
            self.slidingWindowManager = nil
            self.streamedSampleCount = 0
            self.latestStreamingPreviewText = ""
        }

        let delta = Array(samples.dropFirst(self.streamedSampleCount))
        self.streamedSampleCount = samples.count
        return delta
    }

    private func finishSlidingWindowTranscription(_ samples: [Float]) async throws -> ASRTranscriptionResult? {
        guard let manager = self.slidingWindowManager else {
            return nil
        }

        let delta = try await self.consumeStreamingDelta(from: samples)
        if !delta.isEmpty {
            try await manager.streamAudio(self.createPCMBuffer(from: delta))
        }

        let text = try await manager.finish()
        self.slidingWindowManager = nil
        self.streamedSampleCount = 0
        return ASRTranscriptionResult(text: text, confidence: text.isEmpty ? 0 : 1)
    }

    private func shouldUseSlidingWindowFinal(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }
        guard !self.hasSuspiciousMidWordPeriod(cleaned) else {
            DebugLogger.shared.info("ASR_BENCH provider_sliding_rejected reason=mid_word_period", source: "ASRBenchmark")
            return false
        }
        guard !self.latestStreamingPreviewText.isEmpty else { return true }

        let minimumLength = Int(Double(self.latestStreamingPreviewText.count) * 0.92)
        if cleaned.count < minimumLength {
            DebugLogger.shared.info(
                "ASR_BENCH provider_sliding_rejected reason=short slidingChars=\(cleaned.count) previewChars=\(self.latestStreamingPreviewText.count)",
                source: "ASRBenchmark"
            )
            return false
        }
        return true
    }

    private func hasSuspiciousMidWordPeriod(_ text: String) -> Bool {
        let chars = Array(text)
        guard chars.count >= 3 else { return false }
        for index in 1..<(chars.count - 1) where chars[index] == "." {
            if chars[index - 1].isLetter, chars[index + 1].isLetter {
                return true
            }
        }
        return false
    }

    private func createPCMBuffer(from samples: [Float]) throws -> AVAudioPCMBuffer {
        guard
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
            let channelData = buffer.floatChannelData
        else {
            throw NSError(
                domain: "FluidAudioProvider",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create audio buffer for sliding-window ASR"]
            )
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { samplePtr in
            guard let baseAddress = samplePtr.baseAddress else { return }
            channelData[0].update(from: baseAddress, count: samples.count)
        }
        return buffer
    }

    private func logFinalBenchmark(samples: [Float], text: String, startedAt: TimeInterval, usedFallback: Bool) {
        let elapsedMs = Int(((Date().timeIntervalSince1970 - startedAt) * 1000).rounded())
        let audioMs = Int((Double(samples.count) / 16_000.0 * 1000).rounded())
        let rtf = audioMs > 0 ? Double(elapsedMs) / Double(audioMs) : 0
        DebugLogger.shared.info(
            """
            ASR_BENCH provider_final_done samples=\(samples.count) audioMs=\(audioMs) \
            elapsedMs=\(elapsedMs) textChars=\(text.trimmingCharacters(in: .whitespacesAndNewlines).count) \
            rtf=\(String(format: "%.3f", rtf)) fallback=\(usedFallback)
            """,
            source: "ASRBenchmark"
        )
    }

    func modelsExistOnDisk() -> Bool {
        let baseCacheDir = AsrModels.defaultCacheDirectory().deletingLastPathComponent()
        let selectedModel = self.modelOverride ?? SettingsStore.shared.selectedSpeechModel

        if selectedModel == .parakeetTDTv2 {
            let v2CacheDir = baseCacheDir.appendingPathComponent("parakeet-tdt-0.6b-v2-coreml")
            return FileManager.default.fileExists(atPath: v2CacheDir.path)
        } else {
            let v3CacheDir = baseCacheDir.appendingPathComponent("parakeet-tdt-0.6b-v3-coreml")
            return FileManager.default.fileExists(atPath: v3CacheDir.path)
        }
    }

    func clearCache() async throws {
        let baseCacheDir = AsrModels.defaultCacheDirectory().deletingLastPathComponent()
        let selectedModel = self.modelOverride ?? SettingsStore.shared.selectedSpeechModel
        DebugLogger.shared.info(
            "FluidAudioProvider: clearCache called for \(selectedModel.displayName)",
            source: "FluidAudioProvider"
        )

        let start = Date()
        if selectedModel == .parakeetTDTv2 {
            // Clear v2 cache only
            let v2CacheDir = baseCacheDir.appendingPathComponent("parakeet-tdt-0.6b-v2-coreml")
            if FileManager.default.fileExists(atPath: v2CacheDir.path) {
                try FileManager.default.removeItem(at: v2CacheDir)
                DebugLogger.shared.info("FluidAudioProvider: Deleted Parakeet v2 cache", source: "FluidAudioProvider")
            }
        } else {
            // Clear v3 cache only (default)
            let v3CacheDir = baseCacheDir.appendingPathComponent("parakeet-tdt-0.6b-v3-coreml")
            if FileManager.default.fileExists(atPath: v3CacheDir.path) {
                try FileManager.default.removeItem(at: v3CacheDir)
                DebugLogger.shared.info("FluidAudioProvider: Deleted Parakeet v3 cache", source: "FluidAudioProvider")
            }
        }

        DebugLogger.shared.debug(
            "FluidAudioProvider: clearCache completed in \(String(format: "%.3f", Date().timeIntervalSince(start)))s",
            source: "FluidAudioProvider"
        )

        self.isReady = false
        self.streamingAsrManager = nil
        self.finalAsrManager = nil
        self.isWordBoostingActive = false
        self.boostedVocabularyTermsCount = 0
        self.boostedTermLookup = []
    }

    /// Provides direct access to the underlying AsrManager for advanced use cases
    /// (e.g., MeetingTranscriptionService sharing)
    var underlyingManager: AsrManager? {
        return self.streamingAsrManager
    }

    func detectBoostedTerms(in text: String, limit: Int = 2) -> [String] {
        guard self.isWordBoostingActive, !self.boostedTermLookup.isEmpty else { return [] }
        let normalizedText = " \(Self.normalizeForLookup(text)) "
        guard normalizedText.count > 2 else { return [] }

        var hits: [String] = []
        hits.reserveCapacity(min(limit, 2))
        for candidate in self.boostedTermLookup where normalizedText.contains(" \(candidate) ") {
            hits.append(candidate)
            if hits.count >= limit {
                break
            }
        }
        return hits
    }

    private static func makeBoostedTermLookup(from terms: [CustomVocabularyTerm]) -> [String] {
        var unique: Set<String> = []
        unique.reserveCapacity(terms.count * 2)
        for term in terms {
            let normalized = self.normalizeForLookup(term.text)
            if !normalized.isEmpty {
                unique.insert(normalized)
            }
            for alias in term.aliases ?? [] {
                let normalizedAlias = self.normalizeForLookup(alias)
                if !normalizedAlias.isEmpty {
                    unique.insert(normalizedAlias)
                }
            }
        }
        return unique.sorted { lhs, rhs in
            if lhs.count == rhs.count {
                return lhs < rhs
            }
            return lhs.count > rhs.count
        }
    }

    private static func normalizeForLookup(_ text: String) -> String {
        let lowercase = text.lowercased()
        let words = lowercase
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return words.joined(separator: " ")
    }
}
#else
/// Check-shim for Intel Macs where FluidAudio is not available
final class FluidAudioProvider: TranscriptionProvider {
    let name = "FluidAudio (Apple Silicon ONLY)"
    var isAvailable: Bool { false }
    var isReady: Bool { false }
    private(set) var isWordBoostingActive: Bool = false
    private(set) var boostedVocabularyTermsCount: Int = 0

    init(modelOverride: SettingsStore.SpeechModel? = nil, configureWordBoosting: Bool = true) {
        // Intel stub - parameter ignored
    }

    func prepare(progressHandler: ((Double) -> Void)?) async throws {
        throw NSError(
            domain: "FluidAudioProvider",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "FluidAudio is not supported on Intel Macs"]
        )
    }

    func transcribe(_ samples: [Float]) async throws -> ASRTranscriptionResult {
        throw NSError(
            domain: "FluidAudioProvider",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "FluidAudio is not supported on Intel Macs"]
        )
    }

    func detectBoostedTerms(in text: String, limit: Int = 2) -> [String] {
        []
    }
}
#endif
