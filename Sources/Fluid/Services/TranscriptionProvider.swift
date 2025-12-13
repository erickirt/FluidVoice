import Foundation

// MARK: - Transcription Result

/// Unified result type for ASR transcription across all providers
/// Named ASRTranscriptionResult to avoid conflict with MeetingTranscriptionService.TranscriptionResult
struct ASRTranscriptionResult {
    let text: String
    let confidence: Float
    
    init(text: String, confidence: Float = 1.0) {
        self.text = text
        self.confidence = confidence
    }
}

// MARK: - Transcription Provider Protocol

/// Protocol that abstracts speech-to-text transcription.
/// Implementations can use different backends (FluidAudio, SwiftWhisper, etc.)
protocol TranscriptionProvider {
    /// Display name of the provider
    var name: String { get }
    
    /// Whether this provider is available on the current system
    var isAvailable: Bool { get }
    
    /// Whether models are downloaded and ready
    var isReady: Bool { get }
    
    /// Download/prepare models for transcription
    /// - Parameter progressHandler: Optional callback for download progress (0.0 to 1.0)
    func prepare(progressHandler: ((Double) -> Void)?) async throws
    
    /// Transcribe audio samples
    /// - Parameter samples: 16kHz mono PCM float samples
    /// - Returns: Transcription result with text and confidence
    func transcribe(_ samples: [Float]) async throws -> ASRTranscriptionResult
    
    /// Check if models exist on disk (without loading them)
    func modelsExistOnDisk() -> Bool
    
    /// Clear cached models
    func clearCache() async throws
}

// Default implementation for optional methods
extension TranscriptionProvider {
    func modelsExistOnDisk() -> Bool { return false }
    func clearCache() async throws { }
}

// MARK: - Architecture Detection

/// Utility to detect the current CPU architecture
enum CPUArchitecture {
    case applesilicon
    case intel
    
    static var current: CPUArchitecture {
        #if arch(arm64)
        return .applesilicon
        #else
        return .intel
        #endif
    }
    
    static var isAppleSilicon: Bool {
        current == .applesilicon
    }
    
    static var isIntel: Bool {
        current == .intel
    }
}
