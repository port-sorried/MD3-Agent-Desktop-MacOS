import SwiftUI
import AgentCore

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var apiKey = ""
    @State private var keyStatus = ""
    @AppStorage("notch.enabled") private var notchEnabled = true
    @AppStorage("voice.enabled") private var voiceEnabled = false
    @AppStorage("voice.wakeName") private var wakeName = "агент"
    @AppStorage("voice.locale") private var voiceLocale = "ru-RU"
    @State private var accessibilityGranted = false
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
                Toggle("управление приложениями", isOn: Binding(
                    get: { model.preferences.systemControlEnabled == true },
                    set: { model.preferences.systemControlEnabled = $0; model.systemAutomation.enabled = $0 }
                ))
                Text("каждое чтение интерфейса, открытие приложения, нажатие и ввод требуют подтверждения. парольные поля исключены.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text(accessibilityGranted ? "универсальный доступ разрешен" : "универсальный доступ не разрешен")
                    Button("запросить доступ") { model.systemAutomation.requestAccessibility() }
                    Button("проверить") { accessibilityGranted = model.systemAutomation.accessibilityGranted }
                }.font(.caption)
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
                Toggle("откликаться на имя через микрофон", isOn: $voiceEnabled)
                TextField("имя для вызова", text: $wakeName)
                Picker("язык распознавания", selection: $voiceLocale) {
                    Text("русский").tag("ru-RU")
                    Text("english").tag("en-US")
                }
                Text(model.voice.status).foregroundStyle(model.voice.isListening ? Color.orange : Color.secondary)
                if !model.voice.lastCommand.isEmpty { LabeledContent("последняя команда", value: model.voice.lastCommand) }
                Button("повторить подключение") {
                    Task { await model.configureVoice(enabled: voiceEnabled, name: wakeName, locale: voiceLocale) }
                }
                Text("пока режим включен, микрофон слушает локально. скажите имя и команду одной фразой. после паузы команда отправится выбранной модели. имя не является проверкой личности: голос из динамиков тоже может активировать агента. разрешения инструментов голосом не подтверждаются.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("аудио не отправляется в сеть. если локальное распознавание языка недоступно, режим не запустится. текст команды отправляется вашему провайдеру. после сна включите режим повторно.")
                    .font(.caption).foregroundStyle(.secondary)
            }.tabItem { Label("голос", systemImage: "mic") }

            Form {
                Picker("appearance", selection: $model.preferences.appearance) {
                    Text("system").tag("system"); Text("light").tag("light"); Text("dark").tag("dark")
                }
                Text("material color roles follow the macos accent and semantic system colors. reduced motion follows system accessibility settings.")
                    .foregroundStyle(.secondary)
            }.tabItem { Label("appearance", systemImage: "paintpalette") }
        }
        .formStyle(.grouped).padding().frame(width: 680, height: 610)
        .onAppear { accessibilityGranted = model.systemAutomation.accessibilityGranted }
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
