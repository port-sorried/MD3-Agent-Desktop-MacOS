import AgentCore
import AppKit
import Observation

@MainActor @Observable
final class AppModel {
    enum RunOutcome { case idle, completed, failed, stopped }
    var runOutcome: RunOutcome = .idle
    var runTitle: String?
    var runStartedAt: Date?
    var runFinishedAt: Date?
    var conversations: [Conversation] = []
    var selectedID: UUID?
    var preferences = AppPreferences()
    var draft = ""
    var streamedText = ""
    var errorMessage: String?
    var isRunning = false
    var usage = TokenUsage()
    var pendingApproval: ToolCall?
    var activeTool: String?
    var storage: StorageService?
    private var execution: Task<Void, Never>?
    private var approvalContinuation: CheckedContinuation<Bool, Never>?
    private var initialized = false
    let systemAutomation = SystemAutomation()
    let voice = VoiceActivation()

    var selectedConversation: Conversation? { conversations.first { $0.id == selectedID } }

    func initialize() async {
        guard !initialized else { return }
        initialized = true
        do {
            let database = try StorageService()
            storage = database
            conversations = try await database.conversations()
            preferences = try await database.preferences()
            systemAutomation.enabled = preferences.systemControlEnabled == true
            selectedID = conversations.first?.id
        } catch { errorMessage = error.localizedDescription }
    }

    func newConversation() {
        guard !isRunning else { return }
        let conversation = Conversation()
        conversations.insert(conversation, at: 0); selectedID = conversation.id
        draft = ""; streamedText = ""; errorMessage = nil
    }

    func deleteSelected() async {
        guard !isRunning, let id = selectedID, let storage else { return }
        do {
            try await storage.deleteConversation(id)
            conversations.removeAll { $0.id == id }; selectedID = conversations.first?.id
        } catch { errorMessage = error.localizedDescription }
    }

    func savePreferences() async {
        guard let storage else { return }
        do { try await storage.savePreferences(preferences) }
        catch { errorMessage = error.localizedDescription }
    }

    func send() {
        guard !isRunning, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let storage else { return }
        let submittedText = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if selectedID == nil { newConversation() }
        guard let index = conversations.firstIndex(where: { $0.id == selectedID }) else { return }
        let user = ChatMessage(role: .user, content: submittedText)
        conversations[index].messages.append(user)
        if conversations[index].messages.count == 1 { conversations[index].title = String(user.content.prefix(60)) }
        conversations[index].updatedAt = Date()
        let conversation = conversations[index]
        let configuration = preferences
        draft = ""; streamedText = ""; errorMessage = nil; isRunning = true
        runTitle = String(submittedText.prefix(160)); runStartedAt = Date(); runFinishedAt = nil
        runOutcome = .idle; usage = TokenUsage(); activeTool = nil
        execution = Task {
            defer { isRunning = false; runFinishedAt = Date(); execution = nil; streamedText = ""; activeTool = nil; resolveApproval(false) }
            do {
                try await storage.save(conversation)
                let endpoint = try configuration.provider.validatedURL()
                let account = "\(configuration.provider.kind.rawValue):\(endpoint.absoluteString)"
                let apiKey = try KeychainService.read(account: account)
                try await AgentEngine(storage: storage).run(conversation: conversation, preferences: configuration, apiKey: apiKey,
                    systemHandler: { [weak self] call in
                        guard let self else { throw AgentError.denied("application closed") }
                        return try await self.systemAutomation.execute(call)
                    },
                    approve: { [weak self] call in await self?.requestApproval(call) ?? false },
                    emit: { [weak self] event in await self?.receive(event, conversationID: conversation.id) })
                runOutcome = .completed
            } catch is CancellationError {
                runOutcome = .stopped
                errorMessage = "response stopped"
            } catch { runOutcome = .failed; errorMessage = error.localizedDescription }
            do {
                conversations = try await storage.conversations()
            } catch { errorMessage = "could not reload conversations: \(error.localizedDescription)" }
        }
    }

    func stop() { execution?.cancel(); resolveApproval(false) }

    func configureVoice(enabled: Bool, name: String, locale: String) async {
        await voice.configure(enabled: enabled, name: name, locale: locale) { [weak self] command in
            guard let self else { return }
            guard !isRunning, draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorMessage = "голосовая команда не отправлена: дождитесь ответа или очистите черновик"
                return
            }
            draft = command
            send()
        }
    }

    private func receive(_ event: AgentEvent, conversationID: UUID) {
        switch event {
        case .draft(let text): streamedText = text; activeTool = nil
        case .message(let message):
            if let index = conversations.firstIndex(where: { $0.id == conversationID }) {
                conversations[index].messages.append(message)
            }
            streamedText = ""
            if message.role == .tool { activeTool = nil }
        case .usage(let received):
            if received.input > 0 { usage.input = received.input }
            if received.output > 0 { usage.output = received.output }
        case .toolStarted(let call): activeTool = call.name
        }
    }

    private func requestApproval(_ call: ToolCall) async -> Bool {
        if Task.isCancelled { return false }
        return await withCheckedContinuation { continuation in
            approvalContinuation = continuation; pendingApproval = call
        }
    }

    func resolveApproval(_ approved: Bool) {
        let continuation = approvalContinuation
        approvalContinuation = nil; pendingApproval = nil
        continuation?.resume(returning: approved)
    }

    func importFiles(_ urls: [URL]) async {
        guard !isRunning, let storage else { return }
        for url in urls {
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            do {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= 1_048_576 else {
                    throw AgentError.limit("attachments must be regular files up to 1 mib")
                }
                let bytes = try Data(contentsOf: url)
                guard let text = String(data: bytes, encoding: .utf8) else {
                    throw AgentError.invalidConfiguration("only utf-8 text attachments are supported by this native target")
                }
                let name = UUID().uuidString + "-" + url.lastPathComponent
                try bytes.write(to: storage.workspace.appendingPathComponent(name), options: .atomic)
                draft += "\n\n<attachment name=\(name)>\n\(text)\n</attachment>"
            } catch { errorMessage = "\(url.lastPathComponent): \(error.localizedDescription)" }
        }
    }
}
