import Foundation

/// Shared gating logic for whether dictation AI post-processing is usable/configured.
enum DictationAIPostProcessingGate {
    /// Returns true if dictation AI post-processing should be allowed, given current settings.
    /// - Requires dictation prompt selection to not be `Off`
    /// - For Apple Intelligence: requires `AppleIntelligenceService.isAvailable`
    /// - For other providers: requires a local endpoint OR a non-empty API key
    static func isConfigured() -> Bool {
        self.isConfigured(for: .primary)
    }

    static func isConfigured(for slot: SettingsStore.DictationShortcutSlot) -> Bool {
        let settings = SettingsStore.shared
        guard settings.dictationPromptSelection(for: slot) != .off else { return false }

        return self.isProviderConfigured()
    }

    /// Returns true if the selected AI provider is reachable/configured (API key or local endpoint),
    /// regardless of the AI toggle or prompt selection. Used to gate prompt-mode hotkey AI processing.
    static func isProviderConfigured() -> Bool {
        let settings = SettingsStore.shared
        let providerID = settings.selectedProviderID
        if providerID == "apple-intelligence" {
            return AppleIntelligenceService.isAvailable
        }
        let baseURL = self.baseURL(for: providerID, settings: settings)
        if self.isLocalEndpoint(baseURL) { return true }
        let apiKey = (settings.getAPIKey(for: providerID) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !apiKey.isEmpty
    }

    static func baseURL(for providerID: String, settings: SettingsStore) -> String {
        if let saved = settings.savedProviders.first(where: { $0.id == providerID }) {
            return saved.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Use ModelRepository for all built-in providers (openai, groq, cerebras, google, openrouter, ollama, lmstudio)
        if ModelRepository.shared.isBuiltIn(providerID) {
            return ModelRepository.shared.defaultBaseURL(for: providerID)
        }
        // Unknown provider - fallback to OpenAI
        return ModelRepository.shared.defaultBaseURL(for: "openai")
    }

    static func isLocalEndpoint(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString), let host = url.host else { return false }
        let hostLower = host.lowercased()

        if hostLower == "localhost" || hostLower == "127.0.0.1" { return true }
        if hostLower.hasPrefix("127.") || hostLower.hasPrefix("10.") || hostLower.hasPrefix("192.168.") { return true }

        if hostLower.hasPrefix("172.") {
            let components = hostLower.split(separator: ".")
            if components.count >= 2, let secondOctet = Int(components[1]), secondOctet >= 16 && secondOctet <= 31 {
                return true
            }
        }

        return false
    }
}
