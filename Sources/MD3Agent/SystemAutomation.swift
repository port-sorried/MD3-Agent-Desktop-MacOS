import AppKit
import ApplicationServices
import AgentCore

@MainActor
final class SystemAutomation {
    var enabled = false {
        didSet { if !enabled { elements.removeAll() } }
    }
    private struct InspectedElement {
        let element: AXUIElement
        let bundleID: String
        let pid: pid_t
        let expires: Date
        let role: String
        let subrole: String
    }
    private var elements: [String: InspectedElement] = [:]

    var accessibilityGranted: Bool { AXIsProcessTrusted() }
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func execute(_ call: ToolCall) async throws -> String {
        try Task.checkCancellation()
        guard enabled else { throw AgentError.denied("управление системой выключено в настройках") }
        let arguments = try JSONDecoder().decode(JSONValue.self, from: Data(call.arguments.utf8))
        let bundleID = arguments["bundle_id"].string ?? ""
        if call.name == "list_applications" {
            let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
            return try JSONValue.array(apps.map { .object(["name": .string($0.localizedName ?? ""), "bundle_id": .string($0.bundleIdentifier ?? "")]) }).encoded()
        }
        guard !bundleID.isEmpty, bundleID != Bundle.main.bundleIdentifier else {
            throw AgentError.denied("укажите bundle id другого приложения")
        }
        if call.name == "open_application" {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                throw AgentError.invalidConfiguration("приложение не найдено: \(bundleID)")
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            let app = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return "application opened: \(app.bundleIdentifier ?? bundleID)"
        }
        guard AXIsProcessTrusted() else {
            throw AgentError.denied("разрешите MD3Agent в системных настройках: конфиденциальность и безопасность, универсальный доступ")
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first, !app.isTerminated else {
            throw AgentError.invalidConfiguration("сначала откройте приложение")
        }
        if call.name == "inspect_application" {
            elements.removeAll()
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.3)
            var queue: [(AXUIElement, Int)] = [(root, 0)]
            var rows: [JSONValue] = []
            let deadline = Date().addingTimeInterval(5)
            var cursor = 0
            while cursor < queue.count, rows.count < 160, Date() < deadline {
                try Task.checkCancellation()
                let (element, depth) = queue[cursor]; cursor += 1
                AXUIElementSetMessagingTimeout(element, 0.2)
                let role = text(element, kAXRoleAttribute)
                let subrole = text(element, kAXSubroleAttribute)
                // Never expose secure text fields or retain them as action targets.
                if subrole == "AXSecureTextField" { continue }
                let id = UUID().uuidString
                elements[id] = InspectedElement(element: element, bundleID: bundleID, pid: app.processIdentifier,
                                                  expires: Date().addingTimeInterval(60), role: role, subrole: subrole)
                var actions: CFArray?
                _ = AXUIElementCopyActionNames(element, &actions)
                rows.append(.object(["element_id": .string(id), "role": .string(role), "depth": .number(Double(depth)),
                                     "title": .string(String(text(element, kAXTitleAttribute).prefix(300))),
                                     "description": .string(String(text(element, kAXDescriptionAttribute).prefix(300))),
                                     "value": .string(String(text(element, kAXValueAttribute).prefix(500))),
                                     "actions": .array((actions as? [String] ?? []).map(JSONValue.string))]))
                if depth < 8, queue.count < 500 {
                    var children: CFArray?
                    if AXUIElementCopyAttributeValues(element, kAXChildrenAttribute as CFString, 0, 40, &children) == .success,
                       let children = children as? [AXUIElement] {
                        queue.append(contentsOf: children.prefix(500 - queue.count).map { ($0, depth + 1) })
                    }
                }
            }
            return try JSONValue.object(["bundle_id": .string(bundleID), "elements": .array(rows),
                                         "limited": .bool(cursor < queue.count)]).encoded()
        }
        guard let id = arguments["element_id"].string, let inspected = elements[id],
              inspected.bundleID == bundleID, inspected.pid == app.processIdentifier, inspected.expires > Date() else {
            throw AgentError.denied("элемент устарел: выполните inspect_application заново")
        }
        guard text(inspected.element, kAXRoleAttribute) == inspected.role,
              text(inspected.element, kAXSubroleAttribute) == inspected.subrole,
              inspected.subrole != "AXSecureTextField" else { throw AgentError.denied("элемент изменился") }
        let status: AXError
        switch call.name {
        case "press_element": status = AXUIElementPerformAction(inspected.element, kAXPressAction as CFString)
        case "set_element_text":
            let value = arguments["text"].string ?? ""
            guard value.utf8.count <= 16_384 else { throw AgentError.limit("слишком длинный текст") }
            guard ["AXTextField", "AXTextArea", "AXComboBox"].contains(inspected.role) else {
                throw AgentError.denied("элемент не является текстовым полем")
            }
            var settable = DarwinBoolean(false)
            guard AXUIElementIsAttributeSettable(inspected.element, kAXValueAttribute as CFString, &settable) == .success,
                  settable.boolValue else { throw AgentError.denied("поле нельзя редактировать") }
            status = AXUIElementSetAttributeValue(inspected.element, kAXValueAttribute as CFString, value as CFString)
        default: throw AgentError.denied("неизвестный системный инструмент")
        }
        elements.removeAll()
        guard status == .success else { throw AgentError.invalidConfiguration("accessibility error \(status.rawValue); действие не повторялось автоматически") }
        return "action completed; inspect the application again to verify its resulting state"
    }

    private func text(_ element: AXUIElement, _ attribute: String) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return "" }
        return value as? String ?? ""
    }
}
