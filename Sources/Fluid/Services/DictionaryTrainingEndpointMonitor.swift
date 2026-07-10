import Foundation

@MainActor
final class DictionaryTrainingEndpointMonitor {
    static let shared = DictionaryTrainingEndpointMonitor()

    private let detector = DictionaryTrainingEndpointDetector()
    private var task: Task<Void, Never>?

    private init() {}

    func prepare() async {
        do {
            try await self.detector.prepare()
            DebugLogger.shared.debug(
                "Dictionary training endpoint detector ready",
                source: "DictionaryTrainingEndpointMonitor"
            )
        } catch {
            DebugLogger.shared.warning(
                "Dictionary training endpoint detector unavailable: \(error.localizedDescription)",
                source: "DictionaryTrainingEndpointMonitor"
            )
        }
    }

    func start(
        asr: ASRService,
        onSpeechEnded: @escaping @MainActor () -> Void
    ) {
        self.stop()
        let detector = self.detector

        self.task = Task { @MainActor [weak asr] in
            do {
                guard let asr,
                      let detectorSession = try await detector.beginSession()
                else {
                    return
                }
                defer {
                    Task { await detector.endSession(detectorSession) }
                }

                var sampleOffset = 0
                while !Task.isCancelled {
                    guard asr.isRunning, asr.isDictionaryTrainingCaptureActive else { return }

                    let chunk = asr.dictionaryTrainingAudioChunk(
                        at: sampleOffset,
                        count: DictionaryTrainingEndpointDetector.chunkSize
                    )
                    guard !chunk.isEmpty else {
                        try await Task.sleep(nanoseconds: 40_000_000)
                        continue
                    }
                    sampleOffset += chunk.count

                    guard let event = try await detector.process(
                        chunk,
                        session: detectorSession
                    ) else {
                        continue
                    }
                    guard !Task.isCancelled,
                          asr.isRunning,
                          asr.isDictionaryTrainingCaptureActive
                    else {
                        return
                    }

                    switch event {
                    case .speechStarted:
                        DebugLogger.shared.debug(
                            "Dictionary training speech started",
                            source: "DictionaryTrainingEndpointMonitor"
                        )
                    case .speechEnded:
                        DebugLogger.shared.debug(
                            "Dictionary training speech ended; stopping sample",
                            source: "DictionaryTrainingEndpointMonitor"
                        )
                        onSpeechEnded()
                        return
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                DebugLogger.shared.warning(
                    "Dictionary training endpoint detection failed: \(error.localizedDescription)",
                    source: "DictionaryTrainingEndpointMonitor"
                )
            }
        }
    }

    func stop() {
        self.task?.cancel()
        self.task = nil
    }
}
