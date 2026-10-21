import Foundation

public actor AgentContext {
    private var messages: [ChatMessage]
    public init(messages: [ChatMessage] = []) { self.messages = messages }
    public func append(_ message: ChatMessage) { messages.append(message) }
    public func history() -> [ChatMessage] { messages }

    /// A conservative byte estimate, not a provider tokenizer or billing counter.
    public static func estimatedTokens(_ message: ChatMessage) -> Int {
        12 + message.content.utf8.count + message.toolCalls.reduce(0) {
            $0 + $1.arguments.utf8.count + $1.name.utf8.count + $1.id.utf8.count + 16
        }
    }

    public func window(systemPrompt: String, contextTokens: Int, reservedTokens: Int) throws -> [ChatMessage] {
        let system = ChatMessage(role: .system, content: systemPrompt)
        let budget = contextTokens - reservedTokens - Self.estimatedTokens(system)
        guard budget > 0 else { throw AgentError.limit("system prompt fills the context window") }
        // Remove whole user turns, never orphan tool results from their assistant calls.
        let starts = messages.indices.filter { messages[$0].role == .user }
        guard let latest = starts.last else { return [system] }
        var selected = Array(messages[latest...])
        var cost = selected.reduce(0) { $0 + Self.estimatedTokens($1) }
        guard cost <= budget else { throw AgentError.limit("latest turn exceeds the context budget; start a new conversation or shorten input") }
        for startIndex in starts.dropLast().indices.reversed() {
            let start = starts[startIndex]
            let end = starts[startIndex + 1]
            let turn = Array(messages[start..<end])
            let turnCost = turn.reduce(0) { $0 + Self.estimatedTokens($1) }
            if cost + turnCost > budget { break }
            selected.insert(contentsOf: turn, at: 0); cost += turnCost
        }
        return [system] + selected
    }
}
