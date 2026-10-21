import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ToolDefinition: Codable, Sendable, Equatable {
    public var name: String
    public var description: String
    public var parameters: JSONValue
    public init(name: String, description: String, parameters: JSONValue) {
        self.name = name; self.description = description; self.parameters = parameters
    }
}

public struct LLMClient: Sendable {
    public init() {}

    #if os(macOS)
    public func stream(configuration: ProviderConfiguration, apiKey: String, messages: [ChatMessage], tools: [ToolDefinition]) -> AsyncThrowingStream<CompletionEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let sessionConfiguration = URLSessionConfiguration.ephemeral
                sessionConfiguration.timeoutIntervalForRequest = 60
                sessionConfiguration.timeoutIntervalForResource = 600
                sessionConfiguration.httpShouldSetCookies = false
                sessionConfiguration.urlCredentialStorage = nil
                let session = URLSession(configuration: sessionConfiguration, delegate: SameOriginRedirectPolicy(), delegateQueue: nil)
                defer { session.invalidateAndCancel() }
                do {
                    let request = try Self.request(configuration: configuration, apiKey: apiKey, messages: messages, tools: tools)
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let response = response as? HTTPURLResponse else {
                        throw AgentError.protocolViolation("non-http provider response")
                    }
                    guard (200..<300).contains(response.statusCode) else {
                        var body = Data()
                        for try await byte in bytes {
                            body.append(byte)
                            if body.count >= 8192 { break }
                        }
                        let root = try? JSONDecoder().decode(JSONValue.self, from: body)
                        let detail = root?["error"]["message"].string ?? root?["message"].string ?? "provider rejected request"
                        throw AgentError.http(response.statusCode, detail)
                    }
                    var parser = StreamParser(format: configuration.kind == .ollama ? .jsonLines : .sse)
                    var decoder = CompletionDecoder(kind: configuration.kind)
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        for payload in try parser.append(Data([byte])) {
                            for event in try decoder.decode(payload) { continuation.yield(event) }
                        }
                        if decoder.terminal { break }
                    }
                    for payload in try parser.finish() {
                        for event in try decoder.decode(payload) { continuation.yield(event) }
                    }
                    guard decoder.sawFinish else { throw AgentError.protocolViolation("provider stream ended before completion") }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
    #endif

    public static func request(configuration: ProviderConfiguration, apiKey: String, messages: [ChatMessage], tools: [ToolDefinition]) throws -> URLRequest {
        let endpoint = try configuration.validatedURL()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.kind == .ollama ? "application/x-ndjson" : "text/event-stream", forHTTPHeaderField: "Accept")
        for (name, value) in configuration.headers {
            guard !name.contains(where: { $0.isNewline }), !value.contains(where: { $0.isNewline }),
                  !["host", "content-length", "connection", "cookie", "authorization", "x-api-key"].contains(name.lowercased()) else {
                throw AgentError.invalidConfiguration("invalid or reserved custom header")
            }
            request.setValue(value, forHTTPHeaderField: name)
        }
        if !apiKey.isEmpty {
            guard !apiKey.contains(where: { $0.isNewline }) else { throw AgentError.invalidConfiguration("invalid api key") }
            request.setValue(configuration.kind == .anthropic ? apiKey : "Bearer \(apiKey)",
                             forHTTPHeaderField: configuration.kind == .anthropic ? "x-api-key" : "Authorization")
        }
        let body: JSONValue
        if configuration.kind == .anthropic {
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            var turns: [JSONValue] = []
            for message in messages where message.role != .system {
                var blocks: [JSONValue] = []
                if message.role == .tool {
                    guard let callID = message.toolCallID else { throw AgentError.protocolViolation("tool result without id") }
                    blocks = [.object(["type": .string("tool_result"), "tool_use_id": .string(callID), "content": .string(message.content)])]
                } else {
                    if !message.content.isEmpty { blocks.append(.object(["type": .string("text"), "text": .string(message.content)])) }
                    for call in message.toolCalls {
                        blocks.append(.object(["type": .string("tool_use"), "id": .string(call.id), "name": .string(call.name),
                                               "input": try JSONDecoder().decode(JSONValue.self, from: Data(call.arguments.utf8))]))
                    }
                }
                let role = message.role == .assistant ? "assistant" : "user"
                if let last = turns.last, last["role"].string == role {
                    turns[turns.count - 1] = .object(["role": .string(role), "content": .array(last["content"].array + blocks)])
                } else { turns.append(.object(["role": .string(role), "content": .array(blocks)])) }
            }
            var fields: [String: JSONValue] = [
                "model": .string(configuration.model), "stream": .bool(true),
                "max_tokens": .number(Double(configuration.outputTokens)),
                "system": .string(messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n\n")),
                "messages": .array(turns)
            ]
            if !tools.isEmpty {
                fields["tools"] = .array(tools.map { .object(["name": .string($0.name), "description": .string($0.description), "input_schema": $0.parameters]) })
            }
            body = .object(fields)
        } else {
            let turns: [JSONValue] = try messages.map { message in
                var fields: [String: JSONValue] = ["role": .string(message.role.rawValue), "content": .string(message.content)]
                if let id = message.toolCallID { fields["tool_call_id"] = .string(id) }
                if configuration.kind == .ollama, let name = message.toolName { fields["tool_name"] = .string(name) }
                if !message.toolCalls.isEmpty {
                    fields["tool_calls"] = .array(try message.toolCalls.map { call in
                        .object(["id": .string(call.id), "type": .string("function"), "function": .object([
                            "name": .string(call.name),
                            "arguments": configuration.kind == .ollama
                                ? try JSONDecoder().decode(JSONValue.self, from: Data(call.arguments.utf8)) : .string(call.arguments)
                        ])])
                    })
                }
                return .object(fields)
            }
            var fields: [String: JSONValue] = ["model": .string(configuration.model), "messages": .array(turns), "stream": .bool(true)]
            if configuration.kind == .ollama {
                fields["options"] = .object(["num_predict": .number(Double(configuration.outputTokens)), "num_ctx": .number(Double(configuration.contextTokens))])
            } else {
                fields["max_tokens"] = .number(Double(configuration.outputTokens))
                fields["stream_options"] = .object(["include_usage": .bool(true)])
            }
            if !tools.isEmpty {
                fields["tools"] = .array(tools.map { .object(["type": .string("function"), "function": .object([
                    "name": .string($0.name), "description": .string($0.description), "parameters": $0.parameters
                ])]) })
            }
            body = .object(fields)
        }
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }
}

private final class SameOriginRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // Refuse redirects rather than forward secrets or silently change POST semantics.
        completionHandler(nil)
    }
}

public struct CompletionDecoder: Sendable {
    private let kind: ProviderKind
    public private(set) var terminal = false
    public private(set) var sawFinish = false
    private var anthropicToolBlocks = Set<Int>()
    private var ollamaCallIndex = 0
    public init(kind: ProviderKind) { self.kind = kind }

    public mutating func decode(_ payload: String) throws -> [CompletionEvent] {
        if terminal { return [] }
        if payload == "[DONE]" {
            guard sawFinish else { throw AgentError.protocolViolation("done marker without finish reason") }
            terminal = true; return []
        }
        guard let bytes = payload.data(using: .utf8) else { throw AgentError.protocolViolation("invalid stream payload") }
        let root = try JSONDecoder().decode(JSONValue.self, from: bytes)
        if root["error"] != .null {
            throw AgentError.protocolViolation(root["error"]["message"].string ?? root["error"].string ?? "provider stream error")
        }
        var events: [CompletionEvent] = []
        if kind == .anthropic {
            let index = root["index"].integer ?? 0
            switch root["type"].string {
            case "content_block_start":
                let block = root["content_block"]
                if block["type"].string == "tool_use" {
                    anthropicToolBlocks.insert(index)
                    let initialInput = block["input"].object.isEmpty ? "" : try block["input"].encoded()
                    events.append(.toolDelta(index: index, id: block["id"].string, name: block["name"].string, arguments: initialInput))
                } else if let text = block["text"].string, !text.isEmpty { events.append(.text(text)) }
            case "content_block_delta":
                if let text = root["delta"]["text"].string { events.append(.text(text)) }
                if let fragment = root["delta"]["partial_json"].string, anthropicToolBlocks.contains(index) {
                    events.append(.toolDelta(index: index, id: nil, name: nil, arguments: fragment))
                }
            case "message_start":
                events.append(.usage(TokenUsage(input: root["message"]["usage"]["input_tokens"].integer ?? 0)))
            case "message_delta":
                events.append(.usage(TokenUsage(output: root["usage"]["output_tokens"].integer ?? 0)))
                if let reason = root["delta"]["stop_reason"].string { sawFinish = true; events.append(.finished(reason)) }
            case "message_stop":
                terminal = true
            default: break
            }
        } else if kind == .ollama {
            if let text = root["message"]["content"].string, !text.isEmpty { events.append(.text(text)) }
            for call in root["message"]["tool_calls"].array {
                events.append(.toolDelta(index: ollamaCallIndex, id: "ollama-\(ollamaCallIndex)", name: call["function"]["name"].string,
                                         arguments: try call["function"]["arguments"].encoded()))
                ollamaCallIndex += 1
            }
            if root["done"].boolean == true {
                events.append(.usage(TokenUsage(input: root["prompt_eval_count"].integer ?? 0, output: root["eval_count"].integer ?? 0)))
                sawFinish = true; terminal = true; events.append(.finished(root["done_reason"].string))
            }
        } else {
            if root["usage"] != .null {
                events.append(.usage(TokenUsage(input: root["usage"]["prompt_tokens"].integer ?? 0, output: root["usage"]["completion_tokens"].integer ?? 0)))
            }
            for choice in root["choices"].array where choice["index"].integer == 0 || choice["index"] == .null {
                if let text = choice["delta"]["content"].string { events.append(.text(text)) }
                for call in choice["delta"]["tool_calls"].array {
                    guard let index = call["index"].integer else { throw AgentError.protocolViolation("tool delta without index") }
                    events.append(.toolDelta(index: index, id: call["id"].string, name: call["function"]["name"].string,
                                             arguments: call["function"]["arguments"].string ?? ""))
                }
                if let reason = choice["finish_reason"].string { sawFinish = true; events.append(.finished(reason)) }
            }
        }
        return events
    }
}
