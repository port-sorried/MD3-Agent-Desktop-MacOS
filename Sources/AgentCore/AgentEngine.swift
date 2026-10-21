import Foundation

public enum AgentEvent: Sendable {
    case message(ChatMessage)
    case draft(String)
    case usage(TokenUsage)
    case toolStarted(ToolCall)
}

public struct AgentEngine: Sendable {
    private let storage: StorageService
    public init(storage: StorageService) { self.storage = storage }

    public func run(conversation: Conversation, preferences: AppPreferences, apiKey: String,
                    approve: @escaping @Sendable (ToolCall) async -> Bool,
                    emit: @escaping @Sendable (AgentEvent) async -> Void) async throws {
        let context = AgentContext(messages: conversation.messages)
        let registry = ToolRegistry(storage: storage)
        var saved = conversation
        let rounds = min(max(preferences.maxToolRounds, 1), 64)
        let definitions = ToolRegistry.available(preferences.permissions)
        let schemaBytes = try JSONEncoder().encode(definitions).count
        for _ in 0..<rounds {
            try Task.checkCancellation()
            let messages = try await context.window(systemPrompt: preferences.systemPrompt, contextTokens: preferences.provider.contextTokens,
                                                    reservedTokens: preferences.provider.outputTokens + schemaBytes + 1024)
            var text = ""
            var calls = ToolCallAccumulator()
            var finishReason: String?
            do {
                for try await event in LLMClient().stream(configuration: preferences.provider, apiKey: apiKey, messages: messages,
                                                        tools: definitions) {
                    try Task.checkCancellation()
                    switch event {
                    case .text(let fragment):
                        text += fragment
                        guard text.utf8.count <= 4_194_304 else { throw AgentError.limit("response exceeds size limit") }
                        await emit(.draft(text))
                    case .toolDelta(let index, let id, let name, let arguments):
                        try calls.append(index: index, id: id, name: name, arguments: arguments)
                    case .usage(let usage): await emit(.usage(usage))
                    case .finished(let reason): finishReason = reason
                    }
                }
            } catch {
                if !text.isEmpty {
                    let partial = ChatMessage(role: .assistant, content: text + "\n\n[response interrupted]")
                    saved.messages.append(partial); saved.updatedAt = Date()
                    try await storage.save(saved); await emit(.message(partial))
                }
                throw error
            }
            if ["length", "max_tokens"].contains(finishReason ?? "") {
                if !text.isEmpty {
                    let partial = ChatMessage(role: .assistant, content: text + "\n\n[output token limit reached]")
                    saved.messages.append(partial); saved.updatedAt = Date()
                    try await storage.save(saved); await emit(.message(partial))
                }
                throw AgentError.limit("model reached its output limit; increase output tokens or request a shorter response")
            }
            let toolCalls = try calls.completed()
            let assistant = ChatMessage(role: .assistant, content: text, toolCalls: toolCalls)
            await context.append(assistant)
            saved.messages.append(assistant); saved.updatedAt = Date()
            // Commit tool requests and results together so interrupted runs cannot leave orphan calls on disk.
            if toolCalls.isEmpty {
                try await storage.save(saved); await emit(.message(assistant)); return
            }
            await emit(.message(assistant))
            for call in toolCalls {
                var result: String
                do {
                    try Task.checkCancellation()
                    await emit(.toolStarted(call))
                    let permission = preferences.permissions[call.name] ?? ToolRegistry.defaultPermission(for: call.name)
                    let approved = permission == .ask ? await approve(call) : false
                    try Task.checkCancellation()
                    result = try await registry.execute(call, permissions: preferences.permissions, approved: approved)
                    if result.utf8.count > 65_536 { result = String(result.prefix(16_384)) + "\n[tool output truncated]" }
                } catch { result = "tool failed: \(error.localizedDescription)" }
                let message = ChatMessage(role: .tool, content: result, toolCallID: call.id, toolName: call.name)
                await context.append(message); saved.messages.append(message)
                try await storage.appendLog(RunLog(conversationID: saved.id, tool: call.name, outcome: String(result.prefix(4096))))
                await emit(.message(message))
            }
            saved.updatedAt = Date(); try await storage.save(saved)
            try Task.checkCancellation()
        }
        throw AgentError.limit("tool round budget exhausted")
    }
}
