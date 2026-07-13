import Foundation

struct PronunciationEnrollmentCapture: Codable, Sendable {
    let values: [Float]
    let sourceFrameCount: Int
    let modelKey: String
}

struct PronunciationDictionaryProfile: Codable, Identifiable, Sendable {
    let dictionaryEntryID: UUID
    var label: String
    let modelKey: String
    let hiddenSize: Int
    var enrollments: [PronunciationEnrollmentCapture]

    var id: String { "\(self.dictionaryEntryID.uuidString):\(self.modelKey)" }
}

enum PronunciationDictionaryStoreError: LocalizedError, Equatable {
    case inconsistentEnrollment

    var errorDescription: String? {
        switch self {
        case .inconsistentEnrollment:
            "Pronunciation samples must use the same model and embedding size."
        }
    }
}

actor PronunciationDictionaryStore {
    static let shared = PronunciationDictionaryStore()

    private struct Document: Codable {
        let version: Int
        var profiles: [PronunciationDictionaryProfile]
    }

    private let fileURL: URL
    private var document: Document?

    init(fileManager: FileManager = .default) {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let appURL = baseURL.appendingPathComponent("FluidVoice", isDirectory: true)
        self.fileURL = appURL.appendingPathComponent("pronunciation-dictionary-v1.json")
    }

    func profiles(modelKey: String) -> [PronunciationDictionaryProfile] {
        self.loadIfNeeded()
        return self.document?.profiles.filter { $0.modelKey == modelKey } ?? []
    }

    func enrollmentCount(dictionaryEntryID: UUID, modelKey: String) -> Int {
        self.loadIfNeeded()
        return self.document?.profiles.first {
            $0.dictionaryEntryID == dictionaryEntryID && $0.modelKey == modelKey
        }?.enrollments.count ?? 0
    }

    func upsert(
        dictionaryEntryID: UUID,
        label: String,
        modelKey: String,
        enrollments: [PronunciationEnrollmentCapture]
    ) throws {
        guard let first = enrollments.first, !first.values.isEmpty else { return }
        guard enrollments.allSatisfy({ $0.modelKey == modelKey && $0.values.count == first.values.count }) else {
            throw PronunciationDictionaryStoreError.inconsistentEnrollment
        }
        self.loadIfNeeded()
        var profiles = self.document?.profiles ?? []
        let profile = PronunciationDictionaryProfile(
            dictionaryEntryID: dictionaryEntryID,
            label: label,
            modelKey: modelKey,
            hiddenSize: first.values.count,
            enrollments: Array(enrollments.suffix(10))
        )
        if let index = profiles.firstIndex(where: {
            $0.dictionaryEntryID == dictionaryEntryID && $0.modelKey == modelKey
        }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        try self.persist(Document(version: 1, profiles: profiles))
    }

    func updateLabel(dictionaryEntryID: UUID, label: String) throws {
        self.loadIfNeeded()
        var profiles = self.document?.profiles ?? []
        var changed = false
        for index in profiles.indices where profiles[index].dictionaryEntryID == dictionaryEntryID {
            profiles[index].label = label
            changed = true
        }
        if changed {
            try self.persist(Document(version: 1, profiles: profiles))
        }
    }

    func delete(dictionaryEntryID: UUID) throws {
        self.loadIfNeeded()
        var profiles = self.document?.profiles ?? []
        profiles.removeAll { $0.dictionaryEntryID == dictionaryEntryID }
        try self.persist(Document(version: 1, profiles: profiles))
    }

    private func loadIfNeeded() {
        guard self.document == nil else { return }
        guard let data = try? Data(contentsOf: self.fileURL),
              let decoded = try? JSONDecoder().decode(Document.self, from: data),
              decoded.version == 1
        else {
            self.document = Document(version: 1, profiles: [])
            return
        }
        self.document = decoded
    }

    private func persist(_ updated: Document) throws {
        try FileManager.default.createDirectory(
            at: self.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(updated).write(to: self.fileURL, options: .atomic)
        self.document = updated
    }
}
