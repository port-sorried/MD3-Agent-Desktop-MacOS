import Foundation

@main
struct VerifyPortable {
    static func main() async throws {
        var checks = 0
        func check(_ condition: Bool, _ message: String) throws {
            guard condition else { throw AgentError.protocolViolation("verification failed: \(message)") }
            checks += 1
        }
        var parser = StreamParser()
        var events: [String] = []
        for byte in Data(": heartbeat\r\ndata: {\"text\":\"\u{1f642}\"}\r\n\r\ndata: final".utf8) {
            events += try parser.append(Data([byte]))
        }
        events += try parser.finish()
        try check(events == ["{\"text\":\"\u{1f642}\"}", "final"], "split utf-8 and crlf")
        var lines = StreamParser(format: .jsonLines)
        let firstLines = try lines.append(Data("{}\n{\"done\":true}".utf8))
        try check(firstLines == ["{}"], "json line framing")
        try check(try lines.finish() == ["{\"done\":true}"], "final json line")
        var calls = ToolCallAccumulator()
        try calls.append(index: 0, id: "a", name: "read_file", arguments: "{\"path\":")
        try calls.append(index: 0, id: nil, name: nil, arguments: "\"a.txt\"}")
        try check(try calls.completed().first?.arguments == "{\"path\":\"a.txt\"}", "tool arguments")
        var decoder = CompletionDecoder(kind: .openAI)
        try check(try decoder.decode("{\"choices\":[{\"index\":0,\"delta\":{\"content\":\"hello\"}}]}") == [.text("hello")], "openai text")
        _ = try decoder.decode("{\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}")
        try check(try decoder.decode("{\"usage\":{\"prompt_tokens\":7,\"completion_tokens\":2},\"choices\":[]}") == [.usage(TokenUsage(input: 7, output: 2))], "trailing usage")
        _ = try decoder.decode("[DONE]")
        try check(decoder.sawFinish && decoder.terminal, "openai completion")
        var anthropic = CompletionDecoder(kind: .anthropic)
        _ = try anthropic.decode("{\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":4}}")
        _ = try anthropic.decode("{\"type\":\"message_stop\"}")
        try check(anthropic.sawFinish && anthropic.terminal, "anthropic completion")
        var ollama = CompletionDecoder(kind: .ollama)
        _ = try ollama.decode("{\"message\":{\"content\":\"hi\"},\"done\":true,\"prompt_eval_count\":3,\"eval_count\":1}")
        try check(ollama.sawFinish && ollama.terminal, "ollama completion")
        var configuration = ProviderConfiguration()
        configuration.model = "test-model"
        let request = try LLMClient.request(configuration: configuration, apiKey: "test-credential",
                                            messages: [ChatMessage(role: .user, content: "hi")], tools: [])
        try check(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-credential", "request authentication")
        let context = AgentContext(messages: [ChatMessage(role: .user, content: String(repeating: "x", count: 1000)),
                                               ChatMessage(role: .assistant, content: "old"), ChatMessage(role: .user, content: "new")])
        let window = try await context.window(systemPrompt: "system", contextTokens: 200, reservedTokens: 40)
        try check(window.count == 2 && window.last?.content == "new", "whole-turn pruning")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = try StorageService(directory: root)
        var chat = Conversation(title: "quoted ' title")
        chat.messages.append(ChatMessage(role: .user, content: "hello"))
        try await storage.save(chat)
        try check(try await storage.conversations() == [chat], "sqlite conversation round trip")
        var preferences = AppPreferences()
        preferences.provider.model = "local"
        try await storage.savePreferences(preferences)
        try check(try await storage.preferences() == preferences, "preferences round trip")
        let memory = MemoryRecord(title: "note", content: "remember")
        try await storage.saveMemory(memory)
        try check(try await storage.memories() == [memory], "memory round trip")
        try await storage.deleteMemory(memory.id)
        try check(try await storage.memories().isEmpty, "memory deletion")
        try await storage.appendLog(RunLog(conversationID: chat.id, tool: "read_file", outcome: "ok"))
        try check(try await storage.logs(conversationID: chat.id).count == 1, "run logs")
        try await storage.deleteConversation(chat.id)
        try check(try await storage.conversations().isEmpty, "conversation deletion")
        try check(try await storage.logs(conversationID: chat.id).isEmpty, "transactional log deletion")
        let registry = ToolRegistry(storage: storage)
        let fileCall = ToolCall(id: "file", name: "write_file", arguments: "{\"path\":\"note.txt\",\"content\":\"saved text\"}")
        _ = try await registry.execute(fileCall, permissions: [:], approved: true)
        let readCall = ToolCall(id: "read", name: "read_file", arguments: "{\"path\":\"note.txt\"}")
        try check(try await registry.execute(readCall, permissions: [:], approved: true) == "saved text", "workspace file round trip")
        do {
            _ = try await registry.execute(ToolCall(id: "escape", name: "read_file", arguments: "{\"path\":\"../agent.sqlite\"}"), permissions: [:], approved: true)
            throw AgentError.protocolViolation("path traversal was allowed")
        } catch AgentError.denied { checks += 1 }
        do {
            _ = try await registry.execute(readCall, permissions: [:], approved: false)
            throw AgentError.protocolViolation("unapproved call was allowed")
        } catch AgentError.denied { checks += 1 }
        let process = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/bin/sh"),
                                                  arguments: ["-c", "printf output; printf error >&2"], directory: root)
        try check(process.stdout == "output" && process.stderr == "error" && process.exitCode == 0, "process pipes")
        let timeout = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], directory: root, timeout: 0.05)
        try check(timeout.timedOut, "process timeout")
        let bounded = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/bin/sh"),
                                                  arguments: ["-c", "printf 1234567890"], directory: root, maximumOutputBytes: 4)
        try check(bounded.stdout == "1234" && bounded.truncated, "bounded output")
        print("passed \(checks) portable checks")
    }
}
