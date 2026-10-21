import Foundation

public struct ToolRegistry: Sendable {
    public let storage: StorageService
    public init(storage: StorageService) { self.storage = storage }

    public static let definitions: [ToolDefinition] = [
        definition("list_files", "List files inside the workspace.", ["path": "string"], required: []),
        definition("read_file", "Read a UTF-8 file inside the workspace, at most 1 MiB.", ["path": "string"]),
        definition("write_file", "Write a UTF-8 workspace file. Requires approval by default.", ["path": "string", "content": "string"]),
        definition("run_command", "Run a shell command as the current user. Not sandboxed. Requires explicit enabling and approval.", ["command": "string"]),
        definition("run_python", "Run Python 3 code as the current user. Not sandboxed. Requires explicit enabling and approval.", ["code": "string"]),
        definition("memory_add", "Save a long-term memory.", ["title": "string", "content": "string"]),
        definition("memory_list", "List saved memories.", [:]),
        definition("memory_search", "Search memory by case-insensitive words.", ["query": "string"]),
        definition("memory_delete", "Delete a memory by UUID.", ["id": "string"]),
        definition("list_chats", "List conversation ids and titles.", [:]),
        definition("read_chat", "Read a saved conversation by UUID.", ["id": "string"]),
        definition("search_messages", "Search saved chat messages.", ["query": "string"])
    ]

    public static func defaultPermission(for name: String) -> ToolPermission {
        switch name {
        case "run_command", "run_python": .off
        default: .ask
        }
    }

    public static func available(_ permissions: [String: ToolPermission]) -> [ToolDefinition] {
        definitions.filter { (permissions[$0.name] ?? defaultPermission(for: $0.name)) != .off }
    }

    public func execute(_ call: ToolCall, permissions: [String: ToolPermission], approved: Bool) async throws -> String {
        guard let definition = Self.definitions.first(where: { $0.name == call.name }) else {
            throw AgentError.denied("unknown tool")
        }
        let permission = permissions[call.name] ?? Self.defaultPermission(for: call.name)
        guard permission != .off, permission != .ask || approved else { throw AgentError.denied("tool execution denied") }
        let root = try JSONDecoder().decode(JSONValue.self, from: Data(call.arguments.utf8))
        guard case .object(let arguments) = root else { throw AgentError.protocolViolation("tool arguments must be an object") }
        let properties = definition.parameters["properties"].object
        guard Set(arguments.keys).isSubset(of: Set(properties.keys)) else { throw AgentError.protocolViolation("unexpected tool argument") }
        for required in definition.parameters["required"].array.compactMap(\.string) {
            guard arguments[required]?.string != nil else { throw AgentError.protocolViolation("missing string argument: \(required)") }
        }
        for (name, value) in arguments where value.string == nil {
            throw AgentError.protocolViolation("argument must be a string: \(name)")
        }
        func string(_ key: String) -> String { arguments[key]?.string ?? "" }
        switch call.name {
        case "list_files":
            let directory = try workspaceURL(string("path"))
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])
            guard files.count <= 10_000 else { throw AgentError.limit("directory has too many entries") }
            return files.map(\.lastPathComponent).sorted().joined(separator: "\n")
        case "read_file":
            let url = try workspaceURL(string("path"))
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let bytes = try handle.read(upToCount: 1_048_577) ?? Data()
            guard bytes.count <= 1_048_576, let text = String(data: bytes, encoding: .utf8) else {
                throw AgentError.limit("file is too large or not utf-8")
            }
            return text
        case "write_file":
            let url = try workspaceURL(string("path"))
            guard string("content").utf8.count <= 1_048_576 else { throw AgentError.limit("file content too large") }
            try Data(string("content").utf8).write(to: url, options: .atomic)
            return "wrote \(string("content").utf8.count) bytes"
        case "run_command", "run_python":
            let isPython = call.name == "run_python"
            let result = try await ProcessRunner.run(executable: URL(fileURLWithPath: isPython ? "/usr/bin/env" : "/bin/zsh"),
                                                     arguments: isPython ? ["python3", "-c", string("code")] : ["-c", string("command")], directory: storage.workspace)
            return String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        case "memory_add":
            let memory = MemoryRecord(title: string("title"), content: string("content"))
            try await storage.saveMemory(memory)
            return memory.id.uuidString
        case "memory_list", "memory_search":
            let words = string("query").lowercased().split(whereSeparator: \.isWhitespace)
            let memories = try await storage.memories().filter { memory in
                let text = (memory.title + " " + memory.content).lowercased()
                return words.allSatisfy { text.contains($0) }
            }
            return String(decoding: try JSONEncoder().encode(memories), as: UTF8.self)
        case "memory_delete":
            guard let id = UUID(uuidString: string("id")) else { throw AgentError.protocolViolation("invalid memory id") }
            try await storage.deleteMemory(id); return "memory deleted"
        case "list_chats":
            return try await storage.conversations().map { "\($0.id.uuidString) \($0.title)" }.joined(separator: "\n")
        case "read_chat":
            guard let id = UUID(uuidString: string("id")), let chat = try await storage.conversations().first(where: { $0.id == id }) else {
                throw AgentError.protocolViolation("conversation not found")
            }
            return String(decoding: try JSONEncoder().encode(chat), as: UTF8.self)
        case "search_messages":
            let query = string("query")
            guard !query.isEmpty else { throw AgentError.protocolViolation("empty search query") }
            return try await storage.conversations().flatMap { chat in
                chat.messages.filter { $0.content.localizedCaseInsensitiveContains(query) }.map { "\(chat.id): \($0.role.rawValue): \($0.content.prefix(2000))" }
            }.prefix(100).joined(separator: "\n")
        default: throw AgentError.denied("tool is not executable")
        }
    }

    private func workspaceURL(_ path: String) throws -> URL {
        guard !path.hasPrefix("/"), !path.contains("\0") else { throw AgentError.denied("workspace paths must be relative") }
        let root = storage.workspace.resolvingSymlinksInPath().standardizedFileURL
        let target = root.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
        guard target.path == root.path || target.path.hasPrefix(root.path + "/") else {
            throw AgentError.denied("path escapes workspace")
        }
        return target
    }

    private static func definition(_ name: String, _ description: String, _ fields: [String: String], required: [String]? = nil) -> ToolDefinition {
        ToolDefinition(name: name, description: description, parameters: .object([
            "type": .string("object"), "properties": .object(fields.mapValues { .object(["type": .string($0)]) }),
            "required": .array((required ?? fields.keys.sorted()).map(JSONValue.string)), "additionalProperties": .bool(false)
        ]))
    }
}
