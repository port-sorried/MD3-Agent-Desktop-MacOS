import Carbon
import Foundation
import AgentCore

// Only HotkeyManager mutates registration on the main actor. The owner makes
// cleanup independent of the executor on which Swift releases the last reference.
private final class HotkeyRegistration: @unchecked Sendable {
    var hotkey: EventHotKeyRef?
    var handler: EventHandlerRef?
    func clear() {
        if let hotkey { UnregisterEventHotKey(hotkey); self.hotkey = nil }
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }
    deinit { clear() }
}

@MainActor
final class HotkeyManager {
    private let registration = HotkeyRegistration()
    private var action: (@MainActor () -> Void)?

    func configure(enabled: Bool, action: @escaping @MainActor () -> Void) throws {
        registration.clear()
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
        }, 1, &eventType, context, &registration.handler)
        guard status == noErr else { throw AgentError.invalidConfiguration("could not install global shortcut handler: \(status)") }
        let keyID = EventHotKeyID(signature: 0x4d443341, id: 1)
        let registrationStatus = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), keyID,
                                               GetApplicationEventTarget(), 0, &self.registration.hotkey)
        guard registrationStatus == noErr else {
            self.registration.clear()
            throw AgentError.invalidConfiguration("global shortcut is unavailable: \(registrationStatus)")
        }
    }
}
