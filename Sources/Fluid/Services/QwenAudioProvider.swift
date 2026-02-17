import Foundation
#if arch(arm64) && ENABLE_QWEN
import FluidAudio

/// TranscriptionProvider implementation for Qwen3-ASR via FluidAudio.
final class QwenAudioProvider: TranscriptionProvider {
    private enum QwenDownloadFallback {
        static let repoPath = "FluidInference/qwen3-asr-0.6b-coreml"
        static let subPath = "f32"

        static let requiredDirectoryPrefixes: Set<String> = [
            "f32/qwen3_asr_audio_encoder.mlmodelc/",
            "f32/qwen3_asr_audio_encoder.mlpackage/",
            "f32/qwen3_asr_decoder_stateful.mlmodelc/",
            "f32/qwen3_asr_decoder_stateful.mlpackage/",
        ]

        static let requiredExactFiles: Set<String> = [
            "f32/qwen3_asr_embeddings.bin",
            "f32/vocab.json",
        ]
    }

    let name = "Qwen3 ASR (FluidAudio)"
    private let sampleRate = 16_000
    private let maxSegmentSeconds: Int = 25

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
            let manager = try await self.prepareManagerWithRecovery(progressHandler: progressHandler)
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

    @available(macOS 15.0, *)
    private func prepareManagerWithRecovery(
        progressHandler: ((Double) -> Void)?
    ) async throws -> Qwen3AsrManager {
        do {
            return try await self.downloadAndLoadManager(progressHandler: progressHandler, progressValue: 0.75)
        } catch {
            DebugLogger.shared.warning(
                "QwenAudioProvider: Initial model load failed (\(error)). Clearing Qwen cache and retrying once.",
                source: "QwenAudioProvider"
            )

            let cacheDirectory = Qwen3AsrModels.defaultCacheDirectory()
            if FileManager.default.fileExists(atPath: cacheDirectory.path) {
                try? FileManager.default.removeItem(at: cacheDirectory)
            }

            progressHandler?(0.35)
            do {
                return try await self.downloadAndLoadManager(progressHandler: progressHandler, progressValue: 0.85)
            } catch {
                DebugLogger.shared.warning(
                    "QwenAudioProvider: Standard downloader retry failed (\(error)). Falling back to direct Hugging Face f32 fetch.",
                    source: "QwenAudioProvider"
                )
                progressHandler?(0.45)

                do {
                    let modelDirectory = try await self.downloadQwenModelsViaFallback(progressHandler: progressHandler)
                    let manager = Qwen3AsrManager()
                    try await manager.loadModels(from: modelDirectory)
                    progressHandler?(0.90)
                    return manager
                } catch {
                    throw NSError(
                        domain: "QwenAudioProvider",
                        code: -5,
                        userInfo: [
                            NSLocalizedDescriptionKey: "Qwen model download is incomplete or corrupted. Cache was cleared and fallback retry also failed: \(error.localizedDescription)"
                        ]
                    )
                }
            }
        }
    }

    @available(macOS 15.0, *)
    private func downloadAndLoadManager(
        progressHandler: ((Double) -> Void)?,
        progressValue: Double
    ) async throws -> Qwen3AsrManager {
        let modelDirectory = try await Qwen3AsrModels.download()
        progressHandler?(progressValue)

        let manager = Qwen3AsrManager()
        try await manager.loadModels(from: modelDirectory)
        return manager
    }

    @available(macOS 15.0, *)
    private func downloadQwenModelsViaFallback(
        progressHandler: ((Double) -> Void)?
    ) async throws -> URL {
        let targetDirectory = Qwen3AsrModels.defaultCacheDirectory()
        if self.hasQwenModelArtifacts(at: targetDirectory) {
            return targetDirectory
        }

        try FileManager.default.createDirectory(
            at: targetDirectory,
            withIntermediateDirectories: true
        )

        let files = try await self.listFallbackFilesRecursively(
            path: QwenDownloadFallback.subPath
        )
        let filesToDownload = files.filter { self.shouldDownloadFallbackFile($0.path) }
        if filesToDownload.isEmpty {
            throw NSError(
                domain: "QwenAudioProvider",
                code: -6,
                userInfo: [NSLocalizedDescriptionKey: "No Qwen files found in fallback listing."]
            )
        }

        let totalCount = filesToDownload.count
        for (index, file) in filesToDownload.enumerated() {
            let localRelativePath = file.path.replacingOccurrences(
                of: "\(QwenDownloadFallback.subPath)/",
                with: ""
            )
            let destination = targetDirectory.appendingPathComponent(localRelativePath)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if FileManager.default.fileExists(atPath: destination.path) {
                let ratio = Double(index + 1) / Double(totalCount)
                progressHandler?(0.45 + ratio * 0.40)
                continue
            }

            if file.size == 0 {
                FileManager.default.createFile(atPath: destination.path, contents: Data())
            } else {
                let encodedPath = file.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.path
                let remoteURL = try ModelRegistry.resolveModel(QwenDownloadFallback.repoPath, encodedPath)
                let request = self.authorizedRequest(url: remoteURL)
                let (tempURL, response) = try await DownloadUtils.sharedSession.download(for: request)

                guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                    throw NSError(
                        domain: "QwenAudioProvider",
                        code: -7,
                        userInfo: [NSLocalizedDescriptionKey: "Failed downloading \(file.path)"]
                    )
                }

                if FileManager.default.fileExists(atPath: destination.path) {
                    try? FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: tempURL, to: destination)
            }

            let ratio = Double(index + 1) / Double(totalCount)
            progressHandler?(0.45 + ratio * 0.40)
        }

        guard self.hasQwenModelArtifacts(at: targetDirectory) else {
            throw NSError(
                domain: "QwenAudioProvider",
                code: -8,
                userInfo: [NSLocalizedDescriptionKey: "Fallback download finished but required Qwen artifacts are still missing."]
            )
        }

        return targetDirectory
    }

    @available(macOS 15.0, *)
    private func listFallbackFilesRecursively(path: String) async throws -> [(path: String, size: Int)] {
        let apiPath = path.isEmpty ? "tree/main" : "tree/main/\(path)"
        let url = try ModelRegistry.apiModels(QwenDownloadFallback.repoPath, apiPath)
        let request = self.authorizedRequest(url: url)
        let (data, response) = try await DownloadUtils.sharedSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw NSError(
                domain: "QwenAudioProvider",
                code: -9,
                userInfo: [NSLocalizedDescriptionKey: "Failed to list Qwen fallback files at \(path)."]
            )
        }

        guard let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        var files: [(path: String, size: Int)] = []
        for item in items {
            guard let itemPath = item["path"] as? String, let itemType = item["type"] as? String else { continue }

            if itemType == "directory" {
                if self.shouldTraverseFallbackDirectory(itemPath) {
                    let nested = try await self.listFallbackFilesRecursively(path: itemPath)
                    files.append(contentsOf: nested)
                }
            } else if itemType == "file", self.shouldDownloadFallbackFile(itemPath) {
                let size = item["size"] as? Int ?? -1
                files.append((path: itemPath, size: size))
            }
        }

        return files
    }

    private func shouldTraverseFallbackDirectory(_ path: String) -> Bool {
        if path == QwenDownloadFallback.subPath { return true }
        return QwenDownloadFallback.requiredDirectoryPrefixes.contains { prefix in
            prefix.hasPrefix(path + "/") || path.hasPrefix(prefix)
        }
    }

    private func shouldDownloadFallbackFile(_ path: String) -> Bool {
        if QwenDownloadFallback.requiredExactFiles.contains(path) { return true }
        return QwenDownloadFallback.requiredDirectoryPrefixes.contains { path.hasPrefix($0) }
    }

    @available(macOS 15.0, *)
    private func hasQwenModelArtifacts(at directory: URL) -> Bool {
        let fileManager = FileManager.default

        let encoderExists =
            fileManager.fileExists(atPath: directory.appendingPathComponent("qwen3_asr_audio_encoder.mlmodelc").path) ||
            fileManager.fileExists(atPath: directory.appendingPathComponent("qwen3_asr_audio_encoder.mlpackage").path)
        let decoderExists =
            fileManager.fileExists(atPath: directory.appendingPathComponent("qwen3_asr_decoder_stateful.mlmodelc").path) ||
            fileManager.fileExists(atPath: directory.appendingPathComponent("qwen3_asr_decoder_stateful.mlpackage").path)
        let embeddingsExists = fileManager.fileExists(atPath: directory.appendingPathComponent("qwen3_asr_embeddings.bin").path)
        let vocabExists = fileManager.fileExists(atPath: directory.appendingPathComponent("vocab.json").path)

        return encoderExists && decoderExists && embeddingsExists && vocabExists
    }

    private func authorizedRequest(url: URL, timeout: TimeInterval = 1800) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        if let token = ProcessInfo.processInfo.environment["HF_TOKEN"]
            ?? ProcessInfo.processInfo.environment["HUGGING_FACE_HUB_TOKEN"]
            ?? ProcessInfo.processInfo.environment["HUGGINGFACEHUB_API_TOKEN"]
        {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    func transcribe(_ samples: [Float]) async throws -> ASRTranscriptionResult {
        try await self.transcribeFinal(samples)
    }

    func transcribeStreaming(_ samples: [Float]) async throws -> ASRTranscriptionResult {
        try await self.transcribeInternal(samples, maxNewTokens: 192, languageHint: self.preferredLanguageHint())
    }

    func transcribeFinal(_ samples: [Float]) async throws -> ASRTranscriptionResult {
        let maxSegmentSamples = self.maxSegmentSeconds * self.sampleRate
        let languageHint = self.preferredLanguageHint()

        if samples.count <= maxSegmentSamples {
            return try await self.transcribeInternal(samples, maxNewTokens: 512, languageHint: languageHint)
        }

        var segments: [String] = []
        var start = 0
        while start < samples.count {
            let end = min(start + maxSegmentSamples, samples.count)
            let segment = Array(samples[start..<end])
            let result = try await self.transcribeInternal(segment, maxNewTokens: 512, languageHint: languageHint)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                segments.append(text)
            }
            start = end
        }

        return ASRTranscriptionResult(text: segments.joined(separator: " "), confidence: 1.0)
    }

    private func transcribeInternal(
        _ samples: [Float],
        maxNewTokens: Int,
        languageHint: String?
    ) async throws -> ASRTranscriptionResult {
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
                language: languageHint,
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

    private func preferredLanguageHint() -> String? {
        guard let preferred = Locale.preferredLanguages.first else { return nil }
        let code = preferred.split(separator: "-").first?.lowercased() ?? preferred.lowercased()
        let supported = Set([
            "zh", "en", "yue", "ar", "de", "fr", "es", "pt", "id", "it", "ko", "ru", "th",
            "vi", "ja", "tr", "hi", "ms", "nl", "sv", "da", "fi", "pl", "cs", "fil", "fa",
            "el", "hu", "mk", "ro"
        ])
        return supported.contains(code) ? code : nil
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
