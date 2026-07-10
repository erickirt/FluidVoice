import AppKit
import Combine
import Foundation

@MainActor
final class AutomaticDictionaryTrainingSession: ObservableObject {
    enum Screen: Equatable {
        case choice
        case training
        case success
    }

    enum CapturePhase: Equatable {
        case idle
        case starting
        case recording
        case processing
    }

    let candidate: AutomaticDictionaryCorrectionCandidate

    @Published private(set) var screen: Screen = .choice
    @Published private(set) var capturePhase: CapturePhase = .idle
    @Published private(set) var variants: [String]
    @Published private(set) var sampleCount = 0
    @Published private(set) var lastOutput = ""
    @Published private(set) var lastOutputIsCovered = false
    @Published private(set) var consecutiveCoveredCaptures = 0
    @Published private(set) var statusMessage = ""
    @Published private(set) var hasError = false
    @Published private(set) var successTitle = "Added to Dictionary"

    var onInteraction: (() -> Void)?
    var onSuccess: (() -> Void)?

    private let asr: ASRService
    private var stopRequestedDuringStart = false
    private var didStartAudioCapture = false
    private var discardCurrentCapture = false
    private var isCancelled = false
    private var stopTask: Task<Void, Never>?

    init(candidate: AutomaticDictionaryCorrectionCandidate, asr: ASRService) {
        self.candidate = candidate
        self.asr = asr

        let replacement = CustomDictionaryTrainingMerge.normalizedReplacement(candidate.correctedText)
        let savedVariants = SettingsStore.shared.customDictionaryEntries
            .filter { $0.replacement.caseInsensitiveCompare(replacement) == .orderedSame }
            .flatMap(\.triggers)
        self.variants = CustomDictionaryTrainingMerge.normalizedTriggers(
            from: savedVariants + [candidate.heardText],
            intendedReplacement: replacement
        )
    }

    var intendedText: String {
        CustomDictionaryTrainingMerge.normalizedReplacement(self.candidate.correctedText)
    }

    var readinessProgress: Int {
        guard self.lastOutputIsCovered else { return 0 }
        return min(self.consecutiveCoveredCaptures, CustomDictionaryTrainingMerge.readyCoveredCount)
    }

    var readinessFraction: Double {
        Double(self.readinessProgress) / Double(CustomDictionaryTrainingMerge.readyCoveredCount)
    }

    var isReady: Bool {
        self.readinessProgress >= CustomDictionaryTrainingMerge.readyCoveredCount
    }

    var finalOutputText: String {
        guard !self.lastOutput.isEmpty else { return "Record to check" }
        return self.lastOutputIsCovered ? self.intendedText : self.lastOutput
    }

    var canSave: Bool {
        !self.variants.isEmpty && self.capturePhase == .idle
    }

    var canUseRecordButton: Bool {
        switch self.capturePhase {
        case .starting:
            return !self.stopRequestedDuringStart
        case .recording:
            return true
        case .processing:
            return false
        case .idle:
            return !self.asr.isRunning && self.sampleCount < CustomDictionaryTrainingMerge.maxSamples
        }
    }

    var recordButtonIsStop: Bool {
        self.capturePhase == .starting || self.capturePhase == .recording
    }

    var recordButtonTitle: String {
        switch self.capturePhase {
        case .starting:
            return self.stopRequestedDuringStart ? "Stopping..." : "Stop"
        case .recording:
            return "Stop"
        case .processing:
            return "Checking..."
        case .idle:
            return "Record"
        }
    }

    var trainingHeadline: String {
        if self.isReady {
            return "FluidVoice understands you"
        }
        return self.sampleCount == 0 ? "Say it naturally" : "Say it again"
    }

    var trainingDetail: String {
        if self.isReady {
            return "You can add it now, or keep trying."
        }
        if self.sampleCount >= CustomDictionaryTrainingMerge.maxSamples {
            return "Maximum samples reached. Add the replacement when ready."
        }
        return "Keep going until FluidVoice understands you 3 times in a row."
    }

    func beginTraining() {
        guard self.screen == .choice else { return }
        self.onInteraction?()
        self.screen = .training
        self.statusMessage = ""
        self.hasError = false
        Task { await DictionaryTrainingEndpointMonitor.shared.prepare() }
    }

    func returnToChoice() {
        guard self.screen == .training, self.capturePhase == .idle else { return }
        self.onInteraction?()
        self.screen = .choice
    }

    func toggleCapture() {
        self.onInteraction?()
        switch self.capturePhase {
        case .idle:
            Task { await self.startCapture() }
        case .starting, .recording:
            Task { await self.stopCapture() }
        case .processing:
            break
        }
    }

    func addOnlyCorrection() {
        self.persist(triggers: [self.candidate.heardText])
    }

    func addTrainedReplacement() {
        guard self.canSave else { return }
        self.persist(triggers: self.variants)
    }

    func removeVariant(_ variant: String) {
        guard self.capturePhase == .idle else { return }
        self.onInteraction?()
        self.variants.removeAll { $0.caseInsensitiveCompare(variant) == .orderedSame }
        self.refreshCoverageAfterVariantRemoval()
    }

    func cancel() {
        self.isCancelled = true
        self.discardCurrentCapture = true
        DictionaryTrainingEndpointMonitor.shared.stop()
        switch self.capturePhase {
        case .starting:
            self.stopRequestedDuringStart = true
        case .recording:
            self.stopTask?.cancel()
            self.stopTask = Task { await self.finishCapture() }
        case .idle, .processing:
            break
        }
    }

    private func startCapture() async {
        guard self.capturePhase == .idle,
              !self.asr.isRunning,
              self.sampleCount < CustomDictionaryTrainingMerge.maxSamples
        else {
            return
        }

        self.stopRequestedDuringStart = false
        self.didStartAudioCapture = false
        self.discardCurrentCapture = false
        self.capturePhase = .starting
        self.hasError = false
        self.statusMessage = "Starting..."

        await self.asr.start(forDictionaryTraining: true) { [weak self] in
            guard let self else { return }
            self.didStartAudioCapture = true
            self.capturePhase = .recording
            if self.stopRequestedDuringStart || self.isCancelled {
                self.statusMessage = "Stopping..."
                self.stopTask?.cancel()
                self.stopTask = Task { await self.finishCapture() }
            } else {
                self.statusMessage = "Listening..."
            }
        }
        guard self.asr.isRunning else {
            self.capturePhase = .idle
            self.stopRequestedDuringStart = false
            guard !self.didStartAudioCapture else { return }
            guard !self.isCancelled else { return }
            self.hasError = true
            self.statusMessage = "Couldn't start recording. Check microphone access and try again."
            return
        }

        if self.stopRequestedDuringStart || self.isCancelled {
            await self.finishCapture()
            return
        }

        if self.capturePhase == .starting {
            self.capturePhase = .recording
            self.statusMessage = "Listening..."
        }
        DictionaryTrainingEndpointMonitor.shared.start(asr: self.asr) { [weak self] in
            self?.handleAutomaticSpeechEnd()
        }
    }

    private func stopCapture() async {
        DictionaryTrainingEndpointMonitor.shared.stop()
        switch self.capturePhase {
        case .starting:
            self.stopRequestedDuringStart = true
            self.statusMessage = "Stopping..."
        case .recording:
            await self.finishCapture()
        case .idle, .processing:
            break
        }
    }

    private func handleAutomaticSpeechEnd() {
        guard self.capturePhase == .starting || self.capturePhase == .recording else { return }
        self.statusMessage = "Stopping..."
        self.stopTask?.cancel()
        self.stopTask = Task { await self.stopCapture() }
    }

    private func finishCapture() async {
        guard self.capturePhase == .recording || self.capturePhase == .starting else { return }
        DictionaryTrainingEndpointMonitor.shared.stop()
        self.capturePhase = .processing
        self.stopRequestedDuringStart = false
        self.hasError = false
        self.statusMessage = "Checking..."

        let transcript = await self.asr.stop(forDictionaryTraining: true)
        let shouldDiscard = self.discardCurrentCapture || self.isCancelled
        self.capturePhase = .idle
        self.discardCurrentCapture = false
        guard !shouldDiscard else { return }
        self.addTrainingVariant(from: transcript)
    }

    private func addTrainingVariant(from transcript: String) {
        guard let detected = CustomDictionaryTrainingMerge.normalizedTrigger(transcript) else {
            self.lastOutput = ""
            self.lastOutputIsCovered = false
            self.consecutiveCoveredCaptures = 0
            self.hasError = true
            self.statusMessage = "Nothing heard. Try again."
            return
        }

        self.lastOutput = detected
        self.sampleCount = min(self.sampleCount + 1, CustomDictionaryTrainingMerge.maxSamples)

        let matchesReplacement = detected.caseInsensitiveCompare(self.intendedText) == .orderedSame
        let isCaptured = self.variants.contains { $0.caseInsensitiveCompare(detected) == .orderedSame }
        if matchesReplacement || isCaptured {
            self.lastOutputIsCovered = true
            self.consecutiveCoveredCaptures += 1
            self.hasError = false
            self.statusMessage = self.isReady ? "Ready to add." : "Understood. Try again."
            return
        }

        guard self.variants.count < CustomDictionaryTrainingMerge.maxSamples else {
            self.lastOutputIsCovered = false
            self.consecutiveCoveredCaptures = 0
            self.hasError = false
            self.statusMessage = "Maximum samples reached."
            return
        }

        self.variants.append(detected)
        self.lastOutputIsCovered = false
        self.consecutiveCoveredCaptures = 0
        self.hasError = false
        self.statusMessage = "New pronunciation captured."
    }

    private func refreshCoverageAfterVariantRemoval() {
        guard !self.lastOutput.isEmpty else { return }
        let matchesReplacement = self.lastOutput.caseInsensitiveCompare(self.intendedText) == .orderedSame
        let isCaptured = self.variants.contains { $0.caseInsensitiveCompare(self.lastOutput) == .orderedSame }
        self.lastOutputIsCovered = matchesReplacement || isCaptured
        if !self.lastOutputIsCovered {
            self.consecutiveCoveredCaptures = 0
        }
    }

    private func persist(triggers: [String]) {
        guard !self.isCancelled else { return }
        self.onInteraction?()
        let currentEntries = SettingsStore.shared.customDictionaryEntries
        let updatedExisting = currentEntries.contains {
            $0.replacement.caseInsensitiveCompare(self.intendedText) == .orderedSame
        }
        let mergedEntries = CustomDictionaryTrainingMerge.mergedEntries(
            current: currentEntries,
            replacement: self.intendedText,
            triggers: triggers
        )
        guard mergedEntries != currentEntries else {
            self.completeSave(title: "Already in Dictionary")
            return
        }

        SettingsStore.shared.customDictionaryEntries = mergedEntries
        ASRService.invalidateDictionaryCache()
        NotificationCenter.default.post(name: .parakeetVocabularyDidChange, object: nil)
        self.completeSave(title: updatedExisting ? "Dictionary Updated" : "Added to Dictionary")
    }

    private func completeSave(title: String) {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        self.successTitle = title
        self.screen = .success
        self.hasError = false
        self.statusMessage = ""
        self.onSuccess?()
    }
}
