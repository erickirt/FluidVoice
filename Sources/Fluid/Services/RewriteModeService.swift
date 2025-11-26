import Foundation
import Combine
import AppKit

@MainActor
final class RewriteModeService: ObservableObject {
    @Published var originalText: String = ""
    @Published var rewrittenText: String = ""
    @Published var isProcessing = false
    @Published var conversationHistory: [Message] = []
    
    private let textSelectionService = TextSelectionService.shared
    private let typingService = TypingService()
    
    struct Message: Identifiable, Equatable {
        let id = UUID()
        let role: Role
        let content: String
        
        enum Role: Equatable {
            case user
            case assistant
        }
    }
    
    func captureSelectedText() -> Bool {
        if let text = textSelectionService.getSelectedText(), !text.isEmpty {
            self.originalText = text
            self.rewrittenText = ""
            self.conversationHistory = []
            return true
        }
        return false
    }
    
    func processRewriteRequest(_ prompt: String) async {
        guard !originalText.isEmpty else { return }
        
        isProcessing = true
        
        // If this is the first request, include the original text
        if conversationHistory.isEmpty {
            conversationHistory.append(Message(role: .user, content: "Original text:\n\(originalText)\n\nRequest: \(prompt)"))
        } else {
            conversationHistory.append(Message(role: .user, content: prompt))
        }
        
        do {
            let response = try await callLLM(messages: conversationHistory)
            conversationHistory.append(Message(role: .assistant, content: response))
            rewrittenText = response
            isProcessing = false
        } catch {
            conversationHistory.append(Message(role: .assistant, content: "Error: \(error.localizedDescription)"))
            isProcessing = false
        }
    }
    
    func acceptRewrite() {
        guard !rewrittenText.isEmpty else { return }
        NSApp.hide(nil) // Restore focus to the previous app
        typingService.typeTextInstantly(rewrittenText)
    }
    
    func clearState() {
        originalText = ""
        rewrittenText = ""
        conversationHistory = []
    }
    
    // MARK: - LLM Integration (Duplicated from CommandModeService for now)
    
    private func callLLM(messages: [Message]) async throws -> String {
        let settings = SettingsStore.shared
        // Use global settings for now, or add specific rewrite settings
        let providerID = settings.selectedProviderID
        let model = settings.selectedModel ?? "gpt-4o"
        let apiKey = settings.providerAPIKeys[providerID] ?? ""
        
        let baseURL: String
        if let provider = settings.savedProviders.first(where: { $0.id == providerID }) {
            baseURL = provider.baseURL
        } else if providerID == "groq" {
            baseURL = "https://api.groq.com/openai/v1"
        } else {
            baseURL = "https://api.openai.com/v1"
        }
        
        let systemPrompt = """
        You are a helpful writing assistant. Your task is to rewrite or modify the text provided by the user according to their instructions.
        Output ONLY the rewritten text. Do not include explanations or conversational filler unless specifically asked.
        """
        
        var apiMessages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]
        
        for msg in messages {
            apiMessages.append(["role": msg.role == .user ? "user" : "assistant", "content": msg.content])
        }
        
        let body: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "temperature": 0.7
        ]
        
        let endpoint = baseURL.hasSuffix("/chat/completions") ? baseURL : "\(baseURL)/chat/completions"
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "RewriteMode", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let err = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "RewriteMode", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: err])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let choice = choices.first,
              let message = choice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "RewriteMode", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        return content
    }
}
