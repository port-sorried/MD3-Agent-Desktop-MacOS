import Carbon
import Foundation
import AgentCore

@MainActor
final class HotkeyManager {
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (@MainActor () -> Void)?

    func configure(enabled: Bool, action: @escaping @MainActor () -> Void) throws {
        if let hotkey { UnregisterEventHotKey(hotkey); self.hotkey = nil }
        if let handler { RemoveEventHandler(handler); self.handler = nil }
        self.action = action
        guard enabled else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            // Carbon dispatches application events on the main thread.
            MainActor.assumeIsolated {
                Unmanaged<HotkeyManager>.fromOpaque(context).takeUnretainedValue().action?()
            }
            return noErr
        }, 1, &eventType, context, &handler)
        guard status == noErr else { throw AgentError.invalidConfiguration("could not install global shortcut handler: \(status)") }
        let keyID = EventHotKeyID(signature: 0x4d443341, id: 1)
        let registration = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), keyID,
                                               GetApplicationEventTarget(), 0, &hotkey)
        guard registration == noErr else {
            if let handler { RemoveEventHandler(handler); self.handler = nil }
            throw AgentError.invalidConfiguration("global shortcut is unavailable: \(registration)")
        }
    }

    deinit {
        if let hotkey { UnregisterEventHotKey(hotkey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
