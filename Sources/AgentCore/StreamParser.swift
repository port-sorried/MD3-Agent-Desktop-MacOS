import Foundation

/// Keeps bytes intact until a complete line arrives, including split UTF-8 scalars.
public struct StreamParser: Sendable {
    public enum Format: Sendable { case sse, jsonLines }
    private let format: Format
    private let maximumBytes: Int
    private var lineBytes = Data()
    private var eventLines: [String] = []
    private var eventBytes = 0
    private var previousWasCR = false

    public init(format: Format = .sse, maximumBytes: Int = 1_048_576) {
        self.format = format; self.maximumBytes = maximumBytes
    }

    public mutating func append(_ bytes: Data) throws -> [String] {
        var payloads: [String] = []
        for byte in bytes {
            if byte == 10 && previousWasCR { previousWasCR = false; continue }
            previousWasCR = byte == 13
            if byte == 10 || byte == 13 {
                try consumeLine(into: &payloads)
            } else {
                lineBytes.append(byte)
                guard lineBytes.count + eventBytes <= maximumBytes else {
                    throw AgentError.limit("stream event exceeds byte limit")
                }
            }
        }
        return payloads
    }

    public mutating func finish() throws -> [String] {
        var payloads: [String] = []
        if !lineBytes.isEmpty { try consumeLine(into: &payloads) }
        dispatch(into: &payloads)
        return payloads
    }

    private mutating func consumeLine(into payloads: inout [String]) throws {
        guard let line = String(data: lineBytes, encoding: .utf8) else {
            throw AgentError.protocolViolation("invalid utf-8 in stream")
        }
        lineBytes.removeAll(keepingCapacity: true)
        switch format {
        case .jsonLines:
            if !line.trimmingCharacters(in: .whitespaces).isEmpty { payloads.append(line) }
        case .sse:
            if line.isEmpty { dispatch(into: &payloads) }
            else if line.hasPrefix("data:") {
                var value = String(line.dropFirst(5))
                if value.hasPrefix(" ") { value.removeFirst() }
                eventBytes += value.utf8.count + 1
                guard eventBytes <= maximumBytes else { throw AgentError.limit("stream event exceeds byte limit") }
                eventLines.append(value)
            }
        }
    }

    private mutating func dispatch(into payloads: inout [String]) {
        if !eventLines.isEmpty { payloads.append(eventLines.joined(separator: "\n")) }
        eventLines.removeAll(keepingCapacity: true); eventBytes = 0
    }
}

public struct ToolCallAccumulator: Sendable {
    private var calls: [Int: ToolCall] = [:]
    public init() {}
    public mutating func append(index: Int, id: String?, name: String?, arguments: String) throws {
        guard index >= 0, index < 128 else { throw AgentError.limit("too many tool calls") }
        var call = calls[index] ?? ToolCall(id: "", name: "", arguments: "")
        if let id, !id.isEmpty { call.id = id }
        if let name, !name.isEmpty { call.name += name }
        call.arguments += arguments
        guard call.arguments.utf8.count <= 1_048_576 else { throw AgentError.limit("tool arguments exceed byte limit") }
        calls[index] = call
    }
    public func completed() throws -> [ToolCall] {
        let ordered = calls.keys.sorted().compactMap { calls[$0] }
        guard Set(ordered.map(\.id)).count == ordered.count else {
            throw AgentError.protocolViolation("duplicate tool call ids")
        }
        for call in ordered {
            guard !call.id.isEmpty, !call.name.isEmpty,
                  case .object = try JSONDecoder().decode(JSONValue.self, from: Data(call.arguments.utf8)) else {
                throw AgentError.protocolViolation("incomplete tool call")
            }
        }
        return ordered
    }
}
