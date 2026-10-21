import SwiftUI
import AgentCore

struct NotchTaskView: View {
    let model: AppModel
    let expanded: Bool
    let cameraWidth: CGFloat
    let headerHeight: CGFloat
    let openConversation: @MainActor () -> Void
    let hoverChanged: @MainActor (Bool) -> Void

    private var tint: Color {
        if model.pendingApproval != nil { return .orange }
        if model.runOutcome == .failed { return .red }
        return model.isRunning ? .mint : .white.opacity(0.7)
    }

    private var status: String {
        if model.pendingApproval != nil { return "нужно разрешение" }
        if model.isRunning { return model.activeTool == nil ? "отвечает" : "выполняет инструмент" }
        switch model.runOutcome {
        case .completed: return "готово"
        case .failed: return "ошибка"
        case .stopped: return "остановлено"
        case .idle: return "готов к задаче"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button(action: openConversation) {
                    HStack(spacing: 7) {
                        Image(systemName: model.pendingApproval != nil ? "hand.raised.fill" : "sparkles").foregroundStyle(tint)
                        if cameraWidth == 0 { Text("MD3").fontWeight(.semibold) }
                    }.frame(maxWidth: .infinity, minHeight: headerHeight)
                }.help("открыть текущую задачу")
                if cameraWidth > 0 { Color.clear.frame(width: cameraWidth, height: headerHeight).allowsHitTesting(false) }
                HStack(spacing: 6) {
                    Circle().fill(tint).frame(width: 6, height: 6)
                    if let started = model.runStartedAt {
                        if model.isRunning { Text(started, style: .timer).monospacedDigit() }
                        else { Text(duration).monospacedDigit() }
                    } else { Text("готов") }
                }.font(.system(size: 11, weight: .medium, design: .monospaced))
                    .frame(maxWidth: .infinity, minHeight: headerHeight)
            }
            .padding(.horizontal, 12)

            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(status, systemImage: statusIcon).foregroundStyle(tint)
                        Spacer()
                        if model.isRunning { ProgressView().controlSize(.small).tint(.white) }
                    }.font(.system(size: 12, weight: .semibold))
                    Text(model.runTitle ?? "новая задача")
                        .font(.system(size: 16, weight: .semibold)).lineLimit(2)
                    if let call = model.pendingApproval {
                        Text(call.name).font(.system(size: 12, design: .monospaced)).foregroundStyle(.orange)
                        ScrollView {
                            Text(call.arguments).font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        }.frame(maxHeight: 70)
                        HStack {
                            Button("отклонить") { model.resolveApproval(false) }
                            Button("разрешить один раз") { model.resolveApproval(true) }.tint(.orange)
                        }.buttonStyle(.bordered)
                    } else {
                        Text(model.errorMessage ?? model.activeTool ?? (model.isRunning ? "генерирует ответ" : "можно вернуться в чат"))
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.7)).lineLimit(3)
                        HStack {
                            Text("токены: \(model.usage.input) / \(model.usage.output)")
                                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                            Spacer()
                            if model.isRunning { Button("стоп", role: .destructive) { model.stop() }.buttonStyle(.bordered) }
                        }
                    }
                    Spacer(minLength: 0)
                    Button("открыть чат", action: openConversation).buttonStyle(.plain).foregroundStyle(.mint)
                }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .foregroundStyle(.white)
        .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: expanded ? 24 : 14, bottomTrailingRadius: expanded ? 24 : 14))
        .overlay(alignment: .bottom) { Rectangle().fill(tint.opacity(model.isRunning ? 0.8 : 0.2)).frame(height: 2).padding(.horizontal, 24) }
        .contentShape(Rectangle())
        .onHover(perform: hoverChanged)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("статус задачи: \(status)")
    }

    private var statusIcon: String {
        if model.pendingApproval != nil { return "lock.shield" }
        if model.isRunning { return "waveform.path" }
        switch model.runOutcome {
        case .completed: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        case .stopped: return "stop.circle"
        case .idle: return "circle.dotted"
        }
    }

    private var duration: String {
        let seconds = max(0, Int((model.runFinishedAt ?? model.runStartedAt ?? Date()).timeIntervalSince(model.runStartedAt ?? Date())))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
