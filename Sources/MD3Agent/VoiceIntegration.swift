import SwiftUI
import AppKit

struct VoiceIntegration: ViewModifier {
    let model: AppModel
    @AppStorage("voice.enabled") private var enabled = false
    @AppStorage("voice.wakeName") private var name = "агент"
    @AppStorage("voice.locale") private var locale = "ru-RU"

    func body(content: Content) -> some View {
        content
            .task(id: "\(enabled)|\(name)|\(locale)") {
                await model.configureVoice(enabled: enabled, name: name, locale: locale)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.voice.stop() }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in model.voice.stop() }
    }
}
