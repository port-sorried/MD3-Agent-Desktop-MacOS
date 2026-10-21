import AppKit
import SwiftUI
import AgentCore

@MainActor
final class NotchPanelController: NSWindowController {
    private var model: AppModel?
    private var enabled = false
    private var hovered = false
    private var openConversation: (@MainActor () -> Void)?

    init() {
        let panel = TaskNotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        super.init(window: panel)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func update(model: AppModel, enabled: Bool, openConversation: @escaping @MainActor () -> Void) {
        self.model = model
        self.enabled = enabled
        self.openConversation = openConversation
        if !enabled { hovered = false; window?.orderOut(nil); return }
        layout()
        window?.orderFrontRegardless()
    }

    @objc private func screenChanged() { if enabled { layout() } }

    private func layout() {
        guard let model, let window,
              let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let expanded = hovered || model.pendingApproval != nil
        let geometry = NotchLayout(screen: screen.frame, topInset: screen.safeAreaInsets.top,
                                   leftArea: screen.auxiliaryTopLeftArea, rightArea: screen.auxiliaryTopRightArea, expanded: expanded)
        window.setFrame(geometry.frame, display: true)
        let content = NotchTaskView(model: model, expanded: expanded, cameraWidth: geometry.cameraWidth,
                                    headerHeight: geometry.headerHeight, openConversation: { [weak self] in self?.openConversation?() },
                                    hoverChanged: { [weak self] hovering in
            guard let self, hovered != hovering else { return }
            hovered = hovering
            layout()
        })
        if let hosting = window.contentView as? NotchHostingView<NotchTaskView> {
            hosting.rootView = content
        } else { window.contentView = NotchHostingView(rootView: content) }
    }
}

private final class TaskNotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct NotchIntegration: ViewModifier {
    let model: AppModel
    @AppStorage("notch.enabled") private var enabled = true
    @State private var controller = NotchPanelController()
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .onChange(of: enabled, initial: true) { _, _ in update() }
            .onChange(of: model.isRunning) { _, _ in update() }
            .onChange(of: model.pendingApproval?.id) { _, _ in update() }
    }

    private func update() {
        controller.update(model: model, enabled: enabled) {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
    }
}
