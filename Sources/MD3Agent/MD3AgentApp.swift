import SwiftUI
import AppKit

@main @MainActor
struct MD3AgentApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        Window("MD3Agent", id: "main") {
            MainWindowView(model: model)
                .preferredColorScheme(Theme.scheme(model.preferences.appearance))
                .task { await model.initialize() }
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("new conversation") { model.newConversation() }
                    .keyboardShortcut("n").disabled(model.isRunning)
            }
        }
        Settings { SettingsView(model: model) }
        MenuBarExtra("MD3Agent", systemImage: "sparkles", isInserted: $model.preferences.showMenuBar) {
            MenuBarContent(model: model)
        }
    }
}

private struct MenuBarContent: View {
    var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("show conversation") { NSApp.activate(ignoringOtherApps: true); openWindow(id: "main") }
        Button("new conversation") {
            model.newConversation(); NSApp.activate(ignoringOtherApps: true); openWindow(id: "main")
        }.disabled(model.isRunning)
        if model.isRunning { Button("stop response") { model.stop() } }
        Divider()
        SettingsLink()
        Button("quit") { model.stop(); NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
