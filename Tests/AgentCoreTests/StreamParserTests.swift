import Foundation
import Testing
@testable import AgentCore

@Test func splitUTF8AndCRLFArePreserved() throws {
    let wire = Data("event: message\r\ndata: {\"text\":\"\u{1f642}\"}\r\n\r\n".utf8)
    var parser = StreamParser()
    var payloads: [String] = []
    for byte in wire { payloads += try parser.append(Data([byte])) }
    payloads += try parser.finish()
    #expect(payloads == ["{\"text\":\"\u{1f642}\"}"])
}

@Test func multilineSSECommentsAndTrailingEvent() throws {
    var parser = StreamParser()
    let payloads = try parser.append(Data(": heartbeat\ndata: first\ndata: second\n\ndata: trailing".utf8))
    #expect(payloads == ["first\nsecond"])
    #expect(try parser.finish() == ["trailing"])
}

@Test func initialByteOrderMarkIsIgnored() throws {
    var parser = StreamParser()
    #expect(try parser.append(Data("\u{feff}data: first\n\n".utf8)) == ["first"])
}

@Test func emptyToolInputNeedsNoArgumentDelta() throws {
    var accumulator = ToolCallAccumulator()
    try accumulator.append(index: 0, id: "empty", name: "list_files", arguments: "")
    #expect(try accumulator.completed().first?.arguments == "{}")
}

@Test func jsonLinesSupportsFinalUnterminatedLine() throws {
    var parser = StreamParser(format: .jsonLines)
    #expect(try parser.append(Data("{\"a\":1}\n\n{\"b\":2}".utf8)) == ["{\"a\":1}"])
    #expect(try parser.finish() == ["{\"b\":2}"])
}

@Test func oversizedEventsAreRejected() {
    var parser = StreamParser(maximumBytes: 8)
    #expect(throws: (any Error).self) { try parser.append(Data("data: excessive payload".utf8)) }
}

@Test func invalidUTF8IsRejected() {
    var parser = StreamParser()
    #expect(throws: (any Error).self) { try parser.append(Data([0xff, 10])) }
}

@Test func toolArgumentsAccumulateByIndex() throws {
    var accumulator = ToolCallAccumulator()
    try accumulator.append(index: 1, id: "b", name: "read_file", arguments: "{\"path\":")
    try accumulator.append(index: 0, id: "a", name: "list_files", arguments: "{}")
    try accumulator.append(index: 1, id: nil, name: nil, arguments: "\"file.txt\"}")
    let calls = try accumulator.completed()
    #expect(calls.map(\.id) == ["a", "b"])
    #expect(calls[1].arguments == "{\"path\":\"file.txt\"}")
}

@Test func incompleteToolCallsAreRejected() throws {
    var accumulator = ToolCallAccumulator()
    try accumulator.append(index: 0, id: "a", name: "read_file", arguments: "{")
    #expect(throws: (any Error).self) { try accumulator.completed() }
}

@Test func openAIUsageCanFollowFinishReason() throws {
    var decoder = CompletionDecoder(kind: .openAI)
    let text = try decoder.decode("{\"choices\":[{\"index\":0,\"delta\":{\"content\":\"hello\"},\"finish_reason\":null}]}")
    #expect(text == [.text("hello")])
    #expect(try decoder.decode("{\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}") == [.finished("stop")])
    #expect(try decoder.decode("{\"choices\":[],\"usage\":{\"prompt_tokens\":12,\"completion_tokens\":3}}") == [.usage(TokenUsage(input: 12, output: 3))])
    #expect(try decoder.decode("[DONE]").isEmpty)
    #expect(decoder.terminal)
}

@Test func doneMarkerDoesNotHideTruncatedResponse() {
    var decoder = CompletionDecoder(kind: .openAI)
    #expect(throws: (any Error).self) { try decoder.decode("[DONE]") }
}

@Test func anthropicToolDeltasAndCompletion() throws {
    var decoder = CompletionDecoder(kind: .anthropic)
    #expect(try decoder.decode("{\"type\":\"content_block_start\",\"index\":2,\"content_block\":{\"type\":\"tool_use\",\"id\":\"abc\",\"name\":\"list_files\",\"input\":{}}}") == [.toolDelta(index: 2, id: "abc", name: "list_files", arguments: "")])
    #expect(try decoder.decode("{\"type\":\"content_block_delta\",\"index\":2,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{}\"}}") == [.toolDelta(index: 2, id: nil, name: nil, arguments: "{}")])
    _ = try decoder.decode("{\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"tool_use\"},\"usage\":{\"output_tokens\":7}}")
    _ = try decoder.decode("{\"type\":\"message_stop\"}")
    #expect(decoder.terminal && decoder.sawFinish)
}

@Test func ollamaStructuredToolArguments() throws {
    var decoder = CompletionDecoder(kind: .ollama)
    let events = try decoder.decode("{\"message\":{\"content\":\"\",\"tool_calls\":[{\"function\":{\"name\":\"list_files\",\"arguments\":{}}}]},\"done\":true,\"prompt_eval_count\":4,\"eval_count\":2}")
    #expect(events.first == .toolDelta(index: 0, id: "ollama-0", name: "list_files", arguments: "{}"))
    #expect(decoder.terminal && decoder.sawFinish)
}
