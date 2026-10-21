import Foundation
import Testing
@testable import AgentCore

@Test func contextKeepsWholeToolTurns() async throws {
    let user1 = ChatMessage(role: .user, content: String(repeating: "x", count: 1000))
    let assistant = ChatMessage(role: .assistant, content: "", toolCalls: [ToolCall(id: "call", name: "list_files", arguments: "{}")])
    let result = ChatMessage(role: .tool, content: "files", toolCallID: "call")
    let user2 = ChatMessage(role: .user, content: "next")
    let context = AgentContext(messages: [user1, assistant, result, user2])
    let window = try await context.window(systemPrompt: "system", contextTokens: 200, reservedTokens: 50)
    #expect(window.count == 2)
    #expect(window.last == user2)
}

@Test func contextRejectsOversizedCurrentTurn() async {
    let context = AgentContext(messages: [ChatMessage(role: .user, content: String(repeating: "x", count: 500))])
    await #expect(throws: (any Error).self) { try await context.window(systemPrompt: "system", contextTokens: 100, reservedTokens: 20) }
}

@Test func endpointValidationRejectsRemotePlaintextAndCredentials() throws {
    var config = ProviderConfiguration()
    config.model = "test-model"
    config.endpoint = "http://example.com/v1/chat/completions"
    #expect(throws: (any Error).self) { try config.validatedURL() }
    config.endpoint = "https://user:password@example.com/v1/chat/completions"
    #expect(throws: (any Error).self) { try config.validatedURL() }
    config.endpoint = "http://127.0.0.1:11434/api/chat"
    #expect(try config.validatedURL().host == "127.0.0.1")
}

@Test func providerRequestHasExpectedAuthentication() throws {
    var config = ProviderConfiguration()
    config.model = "test-model"
    let request = try LLMClient.request(configuration: config, apiKey: "test-credential", messages: [ChatMessage(role: .user, content: "hi")], tools: [])
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-credential")
    let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
    #expect(body["stream"].boolean == true)
    #expect(body["messages"].array.count == 1)
}

@Test func reservedHeadersCannotOverrideTransport() {
    var config = ProviderConfiguration()
    config.model = "test-model"; config.headers = ["Host": "elsewhere.example"]
    #expect(throws: (any Error).self) { try LLMClient.request(configuration: config, apiKey: "", messages: [], tools: []) }
}

@Test func sqliteRoundTripAndDeletion() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = try StorageService(directory: root)
    var chat = Conversation(title: "quoted ' title")
    chat.messages.append(ChatMessage(role: .user, content: "hello"))
    try await storage.save(chat)
    #expect(try await storage.conversations() == [chat])
    var preferences = AppPreferences()
    preferences.provider.model = "local-model"
    try await storage.savePreferences(preferences)
    #expect(try await storage.preferences() == preferences)
    let memory = MemoryRecord(title: "test", content: "remember")
    try await storage.saveMemory(memory)
    #expect(try await storage.memories() == [memory])
    try await storage.deleteMemory(memory.id)
    #expect(try await storage.memories().isEmpty)
    try await storage.deleteConversation(chat.id)
    #expect(try await storage.conversations().isEmpty)
}

@Test func toolsDenyTraversalAndDisabledCommands() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = try StorageService(directory: root)
    let registry = ToolRegistry(storage: storage)
    await #expect(throws: (any Error).self) {
        try await registry.execute(ToolCall(id: "a", name: "read_file", arguments: "{\"path\":\"../agent.sqlite\"}"), permissions: [:], approved: true)
    }
    await #expect(throws: (any Error).self) {
        try await registry.execute(ToolCall(id: "a", name: "run_command", arguments: "{\"command\":\"true\"}"), permissions: [:], approved: true)
    }
    await #expect(throws: (any Error).self) {
        try await registry.execute(ToolCall(id: "a", name: "list_files", arguments: "{}"), permissions: [:], approved: false)
    }
}

@Test func processCapturesBothPipesAndTimeout() async throws {
    let root = FileManager.default.temporaryDirectory
    let result = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "printf output; printf error >&2"], directory: root)
    #expect(result.exitCode == 0 && result.stdout == "output" && result.stderr == "error")
    let timeout = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], directory: root, timeout: 0.05)
    #expect(timeout.timedOut)
}
