import SwiftUI
import AgentCore

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var apiKey = ""
    @State private var keyStatus = ""
    @AppStorage("notch.enabled") private var notchEnabled = true
    var body: some View {
        TabView {
            Form {
                Toggle("show menu bar item", isOn: $model.preferences.showMenuBar)
                Toggle("показывать задачу у челки", isOn: $notchEnabled)
                Toggle("global shortcut: control option space", isOn: $model.preferences.enableHotkey)
                Stepper("tool round limit: \(model.preferences.maxToolRounds)", value: $model.preferences.maxToolRounds, in: 1...64)
                LabeledContent("system prompt") {
                    TextEditor(text: $model.preferences.systemPrompt).frame(height: 140).font(.body)
                }
            }.tabItem { Label("general", systemImage: "gearshape") }

            Form {
                Picker("provider", selection: $model.preferences.provider.kind) {
                    ForEach(ProviderKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.onChange(of: model.preferences.provider.kind) { _, kind in
                    switch kind {
                    case .openAI: model.preferences.provider.endpoint = "https://api.openai.com/v1/chat/completions"
                    case .anthropic: model.preferences.provider.endpoint = "https://api.anthropic.com/v1/messages"
                    case .ollama: model.preferences.provider.endpoint = "http://127.0.0.1:11434/api/chat"
                    case .custom: break
                    }
                    apiKey = ""; keyStatus = ""
                }
                TextField("full endpoint url", text: $model.preferences.provider.endpoint)
                TextField("model id", text: $model.preferences.provider.model)
                TextField("context tokens", value: $model.preferences.provider.contextTokens, format: .number)
                TextField("maximum output tokens", value: $model.preferences.provider.outputTokens, format: .number)
                SecureField("api key", text: $apiKey)
                HStack {
                    Button("save key in keychain") { saveKey() }
                    Button("delete saved key", role: .destructive) { deleteKey() }
                }
                Text(keyStatus).foregroundStyle(.secondary)
                Text("keys are scoped to the exact provider endpoint and are never stored in preferences. leave the field empty for local ollama.")
                    .font(.caption).foregroundStyle(.secondary)
            }.tabItem { Label("model provider", systemImage: "network") }

            Form {
                Text("system commands run with your user account's access. the workspace is not a sandbox. auto permits repeated execution without approval.")
                    .foregroundStyle(Theme.error)
                ForEach(ToolRegistry.definitions, id: \.name) { tool in
                    Picker(tool.name, selection: Binding(
                        get: { model.preferences.permissions[tool.name] ?? ToolRegistry.defaultPermission(for: tool.name) },
                        set: { model.preferences.permissions[tool.name] = $0 }
                    )) {
                        ForEach(ToolPermission.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.help(tool.description)
                }
            }.tabItem { Label("tools & security", systemImage: "lock.shield") }

            Form {
                Picker("appearance", selection: $model.preferences.appearance) {
                    Text("system").tag("system"); Text("light").tag("light"); Text("dark").tag("dark")
                }
                Text("material color roles follow the macos accent and semantic system colors. reduced motion follows system accessibility settings.")
                    .foregroundStyle(.secondary)
            }.tabItem { Label("appearance", systemImage: "paintpalette") }
        }
        .formStyle(.grouped).padding().frame(width: 680, height: 610)
        .disabled(model.isRunning)
        .onChange(of: model.preferences) { _, _ in Task { await model.savePreferences() } }
    }
    private func account() throws -> String {
        let endpoint = try model.preferences.provider.validatedURL()
        return "\(model.preferences.provider.kind.rawValue):\(endpoint.absoluteString)"
    }
    private func saveKey() {
        do { try KeychainService.save(apiKey, account: account()); apiKey = ""; keyStatus = "key saved" }
        catch { keyStatus = error.localizedDescription }
    }
    private func deleteKey() {
        do { try KeychainService.delete(account: account()); apiKey = ""; keyStatus = "key deleted" }
        catch { keyStatus = error.localizedDescription }
    }
}
