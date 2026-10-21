import Foundation
import CSQLite

public struct MemoryRecord: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var title: String
    public var content: String
    public var instant: Bool
    public var updatedAt: Date
    public init(title: String, content: String, instant: Bool = false) {
        id = UUID(); self.title = title; self.content = content; self.instant = instant; updatedAt = Date()
    }
}

public struct RunLog: Codable, Sendable, Identifiable {
    public var id = UUID()
    public var conversationID: UUID
    public var tool: String
    public var outcome: String
    public var createdAt = Date()
    public init(conversationID: UUID, tool: String, outcome: String) {
        self.conversationID = conversationID; self.tool = tool; self.outcome = outcome
    }
}

/// The connection is confined to StorageService; this owner only closes it at teardown.
private final class SQLiteConnection: @unchecked Sendable {
    let pointer: OpaquePointer
    init(url: URL) throws {
        var database: OpaquePointer?
        let status = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard status == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            throw AgentError.storage("could not open conversations database")
        }
        pointer = database
        sqlite3_busy_timeout(database, 5000)
    }
    deinit { sqlite3_close(pointer) }
}

public actor StorageService {
    private let connection: SQLiteConnection
    public nonisolated let directory: URL
    public nonisolated let workspace: URL

    public init(directory: URL? = nil) throws {
        let root = try directory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                            appropriateFor: nil, create: true).appendingPathComponent("MD3Agent", isDirectory: true)
        self.directory = root
        workspace = root.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        connection = try SQLiteConnection(url: root.appendingPathComponent("agent.sqlite"))
        let schema = """
        PRAGMA journal_mode=WAL;
        PRAGMA foreign_keys=ON;
        CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value BLOB NOT NULL);
        CREATE TABLE IF NOT EXISTS conversations (id TEXT PRIMARY KEY, title TEXT NOT NULL, updated REAL NOT NULL, payload BLOB NOT NULL);
        CREATE TABLE IF NOT EXISTS memories (id TEXT PRIMARY KEY, updated REAL NOT NULL, payload BLOB NOT NULL);
        CREATE TABLE IF NOT EXISTS run_logs (id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL, created REAL NOT NULL, payload BLOB NOT NULL);
        CREATE INDEX IF NOT EXISTS run_logs_conversation ON run_logs(conversation_id, created);
        INSERT OR IGNORE INTO metadata(key, value) VALUES ('schema_version', '1');
        """
        guard sqlite3_exec(connection.pointer, schema, nil, nil, nil) == SQLITE_OK else {
            throw AgentError.storage("could not initialize conversations database")
        }
    }

    public func conversations() throws -> [Conversation] {
        try query("SELECT payload FROM conversations ORDER BY updated DESC", values: [], as: Conversation.self)
    }
    public func save(_ conversation: Conversation) throws {
        try execute("INSERT INTO conversations(id,title,updated,payload) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET title=excluded.title,updated=excluded.updated,payload=excluded.payload",
                    values: [.text(conversation.id.uuidString), .text(conversation.title), .real(conversation.updatedAt.timeIntervalSince1970), .blob(try JSONEncoder().encode(conversation))])
    }
    public func deleteConversation(_ id: UUID) throws {
        try execute("BEGIN IMMEDIATE", values: [])
        do {
            try execute("DELETE FROM run_logs WHERE conversation_id=?", values: [.text(id.uuidString)])
            try execute("DELETE FROM conversations WHERE id=?", values: [.text(id.uuidString)])
            try execute("COMMIT", values: [])
        } catch {
            let original = error
            guard sqlite3_exec(connection.pointer, "ROLLBACK", nil, nil, nil) == SQLITE_OK else {
                throw AgentError.storage("conversation deletion failed and rollback failed")
            }
            throw original
        }
    }
    public func preferences() throws -> AppPreferences {
        try query("SELECT value FROM metadata WHERE key='preferences'", values: [], as: AppPreferences.self).first ?? AppPreferences()
    }
    public func savePreferences(_ preferences: AppPreferences) throws {
        try execute("INSERT INTO metadata(key,value) VALUES('preferences',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                    values: [.blob(try JSONEncoder().encode(preferences))])
    }
    public func memories() throws -> [MemoryRecord] {
        try query("SELECT payload FROM memories ORDER BY updated DESC", values: [], as: MemoryRecord.self)
    }
    public func saveMemory(_ memory: MemoryRecord) throws {
        guard !memory.title.isEmpty, memory.title.count <= 120, !memory.content.isEmpty,
              memory.content.count <= (memory.instant ? 600 : 4000) else { throw AgentError.limit("memory title or content exceeds limits") }
        if memory.instant {
            let existing = try memories()
            guard existing.filter({ $0.instant && $0.id != memory.id }).count < 60 else { throw AgentError.limit("instant memory is full") }
        }
        try execute("INSERT INTO memories(id,updated,payload) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET updated=excluded.updated,payload=excluded.payload",
                    values: [.text(memory.id.uuidString), .real(memory.updatedAt.timeIntervalSince1970), .blob(try JSONEncoder().encode(memory))])
    }
    public func deleteMemory(_ id: UUID) throws {
        try execute("DELETE FROM memories WHERE id=?", values: [.text(id.uuidString)])
    }
    public func appendLog(_ log: RunLog) throws {
        try execute("INSERT INTO run_logs(id,conversation_id,created,payload) VALUES(?,?,?,?)",
                    values: [.text(log.id.uuidString), .text(log.conversationID.uuidString), .real(log.createdAt.timeIntervalSince1970), .blob(try JSONEncoder().encode(log))])
    }
    public func logs(conversationID: UUID) throws -> [RunLog] {
        try query("SELECT payload FROM run_logs WHERE conversation_id=? ORDER BY created", values: [.text(conversationID.uuidString)], as: RunLog.self)
    }

    private enum Binding { case text(String), real(Double), blob(Data) }
    private func statement(_ sql: String, values: [Binding]) throws -> OpaquePointer {
        var prepared: OpaquePointer?
        guard sqlite3_prepare_v2(connection.pointer, sql, -1, &prepared, nil) == SQLITE_OK, let prepared else {
            throw databaseError()
        }
        do {
            for (offset, binding) in values.enumerated() {
                let index = Int32(offset + 1)
                let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                let status: Int32
                switch binding {
                case .text(let value): status = value.withCString { sqlite3_bind_text(prepared, index, $0, -1, transient) }
                case .real(let value): status = sqlite3_bind_double(prepared, index, value)
                case .blob(let value): status = value.withUnsafeBytes { sqlite3_bind_blob(prepared, index, $0.baseAddress, Int32($0.count), transient) }
                }
                guard status == SQLITE_OK else { throw databaseError() }
            }
            return prepared
        } catch { sqlite3_finalize(prepared); throw error }
    }
    private func execute(_ sql: String, values: [Binding]) throws {
        let prepared = try statement(sql, values: values)
        defer { sqlite3_finalize(prepared) }
        guard sqlite3_step(prepared) == SQLITE_DONE else { throw databaseError() }
    }
    private func query<T: Decodable>(_ sql: String, values: [Binding], as type: T.Type) throws -> [T] {
        let prepared = try statement(sql, values: values)
        defer { sqlite3_finalize(prepared) }
        var decoded: [T] = []
        while true {
            let status = sqlite3_step(prepared)
            if status == SQLITE_DONE { return decoded }
            guard status == SQLITE_ROW, let pointer = sqlite3_column_blob(prepared, 0) else { throw databaseError() }
            let bytes = Data(bytes: pointer, count: Int(sqlite3_column_bytes(prepared, 0)))
            decoded.append(try JSONDecoder().decode(type, from: bytes))
        }
    }
    private func databaseError() -> AgentError {
        .storage(String(cString: sqlite3_errmsg(connection.pointer)))
    }
}
