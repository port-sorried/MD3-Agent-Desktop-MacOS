import Foundation
import Testing
@testable import AgentCore

@Test func wakeNameMatchesWholeWordsAndIgnoresCase() {
    #expect(WakePhrase.command(in: "Привет, АГЕНТ, открой заметки", name: "агент") == "открой заметки")
    #expect(WakePhrase.command(in: "контрагент открой заметки", name: "агент") == nil)
    #expect(WakePhrase.command(in: "агент", name: "агент") == "")
    #expect(WakePhrase.command(in: "эй мой помощник открой сафари", name: "мой помощник") == "открой сафари")
    #expect(WakePhrase.command(in: "что угодно", name: "  ") == nil)
}

@Test func oldPreferencesKeepSystemControlDisabled() throws {
    var root = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(AppPreferences())).object
    root.removeValue(forKey: "systemControlEnabled")
    let old = try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(JSONValue.object(root)))
    #expect(old.systemControlEnabled != true)
}

@Test func systemToolsAreHiddenUntilEnabledAndAlwaysAsk() {
    #expect(ToolRegistry.available([:]).allSatisfy { !ToolRegistry.systemToolNames.contains($0.name) })
    #expect(ToolRegistry.available([:], systemControlEnabled: true).contains { $0.name == "open_application" })
    #expect(ToolRegistry.needsApproval("press_element", permissions: ["press_element": .auto]))
    #expect(!ToolRegistry.available(["open_application": .off], systemControlEnabled: true).contains { $0.name == "open_application" })
}

@Test func systemToolsCannotBypassApprovalUsingAuto() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = try StorageService(directory: root)
    let registry = ToolRegistry(storage: storage)
    let call = ToolCall(id: "system", name: "open_application", arguments: "{\"bundle_id\":\"com.apple.Notes\"}")
    await #expect(throws: (any Error).self) {
        try await registry.execute(call, permissions: ["open_application": .auto], approved: false)
    }
    await #expect(throws: (any Error).self) {
        try await registry.execute(call, permissions: ["open_application": .auto], approved: true)
    }
}
