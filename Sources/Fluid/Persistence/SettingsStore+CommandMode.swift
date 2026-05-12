import Combine
import CryptoKit
import Foundation

extension SettingsStore {
    private var commandModeLinkedToGlobalKey: String { "CommandModeLinkedToGlobal" }

    var commandModeLinkedToGlobal: Bool {
        get {
            if let value = UserDefaults.standard.object(forKey: self.commandModeLinkedToGlobalKey) as? Bool {
                return value
            }
            return true
        }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: self.commandModeLinkedToGlobalKey)
        }
    }

    var effectiveCommandModeProviderID: String {
        if self.commandModeLinkedToGlobal,
           let providerID = self.supportedCommandModeProviderID(self.selectedProviderID)
        {
            return providerID
        }

        if let providerID = self.supportedCommandModeProviderID(self.commandModeSelectedProviderID) {
            return providerID
        }

        return "openai"
    }

    var effectiveCommandModeSelectedModel: String {
        let providerID = self.effectiveCommandModeProviderID
        let models = self.commandModeModels(for: providerID)

        if self.commandModeLinkedToGlobal,
           self.supportedCommandModeProviderID(self.selectedProviderID) == providerID
        {
            let key = ModelRepository.shared.providerKey(for: providerID)
            return self.nonEmptyModel(self.selectedModelByProvider[key])
                ?? self.providerScopedModel(self.selectedModel, in: models)
                ?? models.first
                ?? "gpt-4.1"
        }

        return self.nonEmptyModel(self.commandModeSelectedModel) ?? models.first ?? "gpt-4.1"
    }

    var commandModeReadinessIssue: String? {
        let sourceProviderID = self.commandModeLinkedToGlobal ? self.selectedProviderID : self.commandModeSelectedProviderID
        if sourceProviderID == "apple-intelligence" || sourceProviderID == "apple-intelligence-disabled" {
            return "Command Mode cannot use Apple Intelligence because terminal tools require a chat API. Choose a verified chat provider or turn Sync off."
        }

        let providerID = self.effectiveCommandModeProviderID
        let model = self.effectiveCommandModeSelectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            return "Command Mode needs a selected chat model."
        }

        if self.isUnsupportedCommandModeModel(model) {
            return "Command Mode needs a chat model. The selected model is not supported by the chat/completions endpoint."
        }

        guard self.isCommandModeProviderVerified(providerID) else {
            if self.commandModeLinkedToGlobal {
                return "Command Mode needs a verified chat provider. Verify the synced AI Enhancement provider, or turn Sync off and choose one for Command Mode."
            }
            return "Command Mode needs a verified chat provider. Verify this provider in AI Enhancement before using Command Mode."
        }

        return nil
    }

    func commandModeModels(for providerID: String) -> [String] {
        let storedList = ModelRepository.shared.providerKeys(for: providerID).lazy
            .compactMap { self.availableModelsByProvider[$0] }
            .first { !$0.isEmpty }

        return storedList ?? ModelRepository.shared.defaultModels(for: providerID)
    }

    private func supportedCommandModeProviderID(_ providerID: String) -> String? {
        let trimmed = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed != "apple-intelligence", trimmed != "apple-intelligence-disabled" else { return nil }
        return trimmed
    }

    private func isCommandModeProviderVerified(_ providerID: String) -> Bool {
        let key = ModelRepository.shared.providerKey(for: providerID)
        guard let stored = self.verifiedProviderFingerprints[key] else { return false }

        let baseURL = self.commandModeProviderBaseURL(for: providerID)
        let apiKey = self.getAPIKey(for: providerID) ?? ""
        return self.commandModeProviderFingerprint(baseURL: baseURL, apiKey: apiKey) == stored
    }

    private func commandModeProviderBaseURL(for providerID: String) -> String {
        if let saved = self.savedProviders.first(where: { $0.id == providerID }) {
            return saved.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if ModelRepository.shared.isBuiltIn(providerID) {
            return ModelRepository.shared.defaultBaseURL(for: providerID).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private func commandModeProviderFingerprint(baseURL: String, apiKey: String) -> String? {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty else { return nil }
        let input = "\(trimmedBase)|\(trimmedKey)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func isUnsupportedCommandModeModel(_ model: String) -> Bool {
        let value = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.contains("embedding") || value.contains("rerank") || value.contains("moderation") {
            return true
        }
        if value.hasPrefix("tts-") || value.hasPrefix("whisper-") || value.hasPrefix("dall-e") {
            return true
        }
        return value == "davinci" || value == "curie" || value == "babbage" || value == "ada"
    }

    private func nonEmptyModel(_ model: String?) -> String? {
        let trimmed = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func providerScopedModel(_ model: String?, in models: [String]) -> String? {
        guard let model = self.nonEmptyModel(model), models.contains(model) else { return nil }
        return model
    }
}
