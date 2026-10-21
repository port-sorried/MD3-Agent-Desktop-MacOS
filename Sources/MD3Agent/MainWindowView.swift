import SwiftUI
import AppKit
import AgentCore

struct MainWindowView: View {
    @Bindable var model: AppModel
    @State private var search = ""
    @State private var showInspector = false
    @State private var hotkey = HotkeyManager()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").font(.title2).foregroundStyle(Theme.primary)
                    Text("MD3Agent").font(.system(size: 22, weight: .semibold, design: .rounded))
                }.padding(.horizontal, 20).padding(.top, 20)
                Button { model.newConversation() } label: {
                    Label("новый разговор", systemImage: "plus").frame(maxWidth: .infinity)
                }.buttonStyle(MaterialButtonStyle()).padding(.horizontal, 16).disabled(model.isRunning)
            List(selection: $model.selectedID) {
                ForEach(model.conversations.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { conversation in
                    Label(conversation.title, systemImage: "bubble.left")
                        .font(.system(size: 14)).lineLimit(2).padding(.vertical, 9).tag(conversation.id)
                        .listRowBackground(model.selectedID == conversation.id ? Theme.secondaryContainer : Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .disabled(model.isRunning)
            .navigationTitle("conversations")
            .searchable(text: $search, prompt: "search titles")
            .navigationSplitViewColumnWidth(min: 200, ideal: 250)
            .toolbar {
                Button { model.newConversation() } label: { Image(systemName: "square.and.pencil") }
                    .help("new conversation").disabled(model.isRunning)
                Button(role: .destructive) { Task { await model.deleteSelected() } } label: { Image(systemName: "trash") }
                    .help("delete conversation").disabled(model.isRunning || model.selectedID == nil)
            }
            }.background(Theme.surfaceContainer).foregroundStyle(Theme.onSurface)
        } detail: {
            VStack(spacing: 0) {
                if let error = model.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                        Text(error).textSelection(.enabled)
                        Spacer()
                        Button("dismiss") { model.errorMessage = nil }
                    }.padding(12).background(Theme.error.opacity(0.12))
                }
                ChatTimelineView(messages: model.selectedConversation?.messages ?? [], streamedText: model.streamedText)
                if let call = model.pendingApproval {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("allow \(call.name)?", systemImage: "hand.raised")
                        ScrollView { Text(call.arguments).font(Theme.code).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                            .frame(maxHeight: 150)
                        HStack {
                            Text("approval applies to this invocation only").foregroundStyle(.secondary)
                            Spacer()
                            Button("deny") { model.resolveApproval(false) }
                            Button("allow once") { model.resolveApproval(true) }.buttonStyle(MaterialButtonStyle(filled: true))
                        }
                    }.padding(20).background(Theme.primaryContainer, in: RoundedRectangle(cornerRadius: 24)).padding(16)
                }
                InputBarView(model: model)
            }
            .background(Theme.surface).foregroundStyle(Theme.onSurface)
            .navigationTitle(model.selectedConversation?.title ?? "MD3Agent")
            .toolbar {
                if model.isRunning { ProgressView().controlSize(.small) }
                Button { showInspector.toggle() } label: { Image(systemName: "sidebar.right") }.help("toggle inspector")
            }
            .inspector(isPresented: $showInspector) {
                Form {
                    Section("model") {
                        LabeledContent("provider", value: model.preferences.provider.kind.rawValue)
                        LabeledContent("model", value: model.preferences.provider.model.isEmpty ? "not configured" : model.preferences.provider.model)
                        LabeledContent("input tokens", value: String(model.usage.input))
                        LabeledContent("output tokens", value: String(model.usage.output))
                    }
                    Section("execution") {
                        Text(model.activeTool ?? (model.isRunning ? "generating" : "idle"))
                        Text("tools require approval unless you explicitly change their policy").font(.caption).foregroundStyle(.secondary)
                        if let workspace = model.storage?.workspace {
                            Link("open workspace", destination: workspace)
                        }
                    }
                    SettingsLink()
                }.formStyle(.grouped).inspectorColumnWidth(min: 230, ideal: 260, max: 350)
            }
        }
        .frame(minWidth: 740, minHeight: 500)
        .onChange(of: model.preferences.enableHotkey, initial: true) { _, enabled in
            do {
                try hotkey.configure(enabled: enabled) {
                    NSApp.activate(ignoringOtherApps: true); openWindow(id: "main")
                }
            } catch { model.errorMessage = error.localizedDescription }
        }
        .onExitCommand { model.stop() }
    }
}
