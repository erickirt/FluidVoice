import Foundation
import Combine

@MainActor
final class CommandModeService: ObservableObject {
    @Published var conversationHistory: [Message] = []
    @Published var isProcessing = false
    @Published var pendingCommand: PendingCommand? = nil
    
    private let terminalService = TerminalService()
    private var currentTurnCount = 0
    private let maxTurns = 15
    
    // MARK: - Models
    
    struct Message: Identifiable, Equatable {
        let id = UUID()
        let role: Role
        let content: String
        let toolCall: ToolCall?
        
        enum Role: Equatable {
            case user
            case assistant
            case tool
        }
        
        struct ToolCall: Equatable {
            let id: String
            let command: String
            let workingDirectory: String?
        }
        
        init(role: Role, content: String, toolCall: ToolCall? = nil) {
            self.role = role
            self.content = content
            self.toolCall = toolCall
        }
    }
    
    struct PendingCommand {
        let id: String
        let command: String
        let workingDirectory: String?
    }
    
    // MARK: - Public Methods
    
    func clearHistory() {
        conversationHistory.removeAll()
        pendingCommand = nil
        currentTurnCount = 0
    }
    
    /// Process user voice/text command
    func processUserCommand(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isProcessing = true
        currentTurnCount = 0
        conversationHistory.append(Message(role: .user, content: text))
        
        await processNextTurn()
    }
    
    /// Execute pending command (after user confirmation)
    func confirmAndExecute() async {
        guard let pending = pendingCommand else { return }
        pendingCommand = nil
        isProcessing = true
        
        await executeCommand(pending.command, workingDirectory: pending.workingDirectory, callId: pending.id)
    }
    
    /// Cancel pending command
    func cancelPendingCommand() {
        pendingCommand = nil
        conversationHistory.append(Message(
            role: .assistant,
            content: "Command cancelled."
        ))
        isProcessing = false
    }
    
    // MARK: - Agent Loop
    
    private func processNextTurn() async {
        if currentTurnCount >= maxTurns {
            conversationHistory.append(Message(role: .assistant, content: "I've reached the maximum number of steps. stopping here."))
            isProcessing = false
            return
        }
        
        currentTurnCount += 1
        
        do {
            let response = try await callLLM()
            
            if let toolCall = response.toolCall {
                // AI wants to run a command
                conversationHistory.append(Message(
                    role: .assistant,
                    content: response.content.isEmpty ? "I'll run this command:" : response.content,
                    toolCall: Message.ToolCall(
                        id: toolCall.id,
                        command: toolCall.command,
                        workingDirectory: toolCall.workingDirectory
                    )
                ))
                
                // Check if we need confirmation
                if SettingsStore.shared.commandModeConfirmBeforeExecute {
                    pendingCommand = PendingCommand(
                        id: toolCall.id,
                        command: toolCall.command,
                        workingDirectory: toolCall.workingDirectory
                    )
                    isProcessing = false
                    return
                }
                
                // Auto-execute
                await executeCommand(toolCall.command, workingDirectory: toolCall.workingDirectory, callId: toolCall.id)
                
            } else {
                // Just a text response, we are done
                conversationHistory.append(Message(role: .assistant, content: response.content))
                isProcessing = false
            }
            
        } catch {
            conversationHistory.append(Message(
                role: .assistant,
                content: "Error: \(error.localizedDescription)"
            ))
            isProcessing = false
        }
    }
    
    private func executeCommand(_ command: String, workingDirectory: String?, callId: String) async {
        let result = await terminalService.execute(
            command: command,
            workingDirectory: workingDirectory
        )
        
        let resultJSON = terminalService.resultToJSON(result)
        
        // Add tool result to conversation
        conversationHistory.append(Message(
            role: .tool,
            content: resultJSON
        ))
        
        // Continue the loop - let the AI see the result and decide what to do next
        await processNextTurn()
    }
    
    // MARK: - LLM Integration
    
    private struct LLMResponse {
        let content: String
        let toolCall: (id: String, command: String, workingDirectory: String?)?
    }
    
    private func callLLM() async throws -> LLMResponse {
        let settings = SettingsStore.shared
        let providerID = settings.commandModeLinkedToGlobal ? settings.selectedProviderID : settings.commandModeSelectedProviderID
        let model = (settings.commandModeLinkedToGlobal ? settings.selectedModel : settings.commandModeSelectedModel) ?? "gpt-4o"
        let apiKey = settings.providerAPIKeys[providerID] ?? ""
        
        let baseURL: String
        if let provider = settings.savedProviders.first(where: { $0.id == providerID }) {
            baseURL = provider.baseURL
        } else if providerID == "groq" {
            baseURL = "https://api.groq.com/openai/v1"
        } else {
            baseURL = "https://api.openai.com/v1"
        }
        
        // Build conversation
        let systemPrompt = """
        You are an autonomous macOS terminal agent. Your goal is to complete the user's request by executing commands.
        
        IMPORTANT RULES:
        1. You can execute shell commands using the 'execute_terminal_command' tool.
        2. If a command fails, ANALYZE the error output and try to FIX it by running a corrected command.
        3. You can run multiple commands in sequence to accomplish a task (e.g., make a directory, then create a file).
        4. Always use full paths when possible.
        5. For destructive operations (rm, overwrite), ask the user for confirmation first (unless they already gave implied permission).
        6. When the task is fully complete, respond with a final text summary.
        7. Keep intermediate text responses concise.
        
        The user is on macOS with zsh shell.
        """
        
        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]
        
        // Add conversation history
        var lastToolCallId: String? = nil
        
        for msg in conversationHistory {
            switch msg.role {
            case .user:
                messages.append(["role": "user", "content": msg.content])
            case .assistant:
                if let tc = msg.toolCall {
                    lastToolCallId = tc.id
                    messages.append([
                        "role": "assistant",
                        "content": msg.content,
                        "tool_calls": [[
                            "id": tc.id,
                            "type": "function",
                            "function": [
                                "name": "execute_terminal_command",
                                "arguments": try! String(data: JSONSerialization.data(withJSONObject: [
                                    "command": tc.command,
                                    "workingDirectory": tc.workingDirectory ?? ""
                                ]), encoding: .utf8)!
                            ]
                        ]]
                    ])
                } else {
                    messages.append(["role": "assistant", "content": msg.content])
                }
            case .tool:
                messages.append([
                    "role": "tool",
                    "content": msg.content,
                    "tool_call_id": lastToolCallId ?? "call_unknown"
                ])
            }
        }
        
        // We assume conversationHistory contains the user's latest message already

        
        // Build request
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "tools": [TerminalService.toolDefinition],
            "tool_choice": "auto",
            "temperature": 0.1
        ]
        
        let endpoint = baseURL.hasSuffix("/chat/completions") ? baseURL : "\(baseURL)/chat/completions"
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "CommandMode", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let err = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "CommandMode", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: err])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let choice = choices.first,
              let message = choice["message"] as? [String: Any] else {
            throw NSError(domain: "CommandMode", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        // Check for tool calls
        if let toolCalls = message["tool_calls"] as? [[String: Any]],
           let toolCall = toolCalls.first,
           let function = toolCall["function"] as? [String: Any],
           let name = function["name"] as? String,
           name == "execute_terminal_command",
           let argsString = function["arguments"] as? String,
           let argsData = argsString.data(using: .utf8),
           let args = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] {
            
            let command = args["command"] as? String ?? ""
            let workDir = args["workingDirectory"] as? String
            let callId = toolCall["id"] as? String ?? "call_\(UUID().uuidString.prefix(8))"
            
            return LLMResponse(
                content: message["content"] as? String ?? "",
                toolCall: (id: callId, command: command, workingDirectory: workDir?.isEmpty == true ? nil : workDir)
            )
        }
        
        // Text response only
        return LLMResponse(
            content: message["content"] as? String ?? "I couldn't understand that.",
            toolCall: nil
        )
    }
}
