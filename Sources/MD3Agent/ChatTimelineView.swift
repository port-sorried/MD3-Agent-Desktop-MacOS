import SwiftUI
import AppKit
import AgentCore

struct ChatTimelineView: View {
    let messages: [ChatMessage]
    let streamedText: String
    @State private var followLatest = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if messages.isEmpty {
                        ContentUnavailableView("start a conversation", systemImage: "sparkles",
                                               description: Text("choose your provider and model in settings, then send a message"))
                            .frame(maxWidth: .infinity).padding(.top, 80)
                    }
                    ForEach(messages) { message in
                        MessageRow(message: message).id(message.id)
                    }
                    if !streamedText.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("assistant", systemImage: "sparkles").font(.caption).foregroundStyle(.secondary)
                            MarkdownContent(text: streamedText)
                        }
                    }
                    Color.clear.frame(height: 1).id("latest")
                        .onAppear { followLatest = true }
                        .onDisappear { followLatest = false }
                }
                .padding(24).frame(maxWidth: 900).frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: messages.count) { _, _ in scroll(proxy) }
            .onChange(of: streamedText) { _, _ in if followLatest { scroll(proxy) } }
            .overlay(alignment: .bottomTrailing) {
                if !followLatest {
                    Button { followLatest = true; scroll(proxy) } label: { Image(systemName: "arrow.down") }
                        .buttonStyle(.bordered).help("scroll to latest message").padding()
                }
            }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        if reduceMotion { proxy.scrollTo("latest", anchor: .bottom) }
        else { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo("latest", anchor: .bottom) } }
    }
}

private struct MessageRow: View {
    let message: ChatMessage
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(message.role.rawValue, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.content, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain).help("copy message")
            }
            if message.role == .tool {
                DisclosureGroup("tool result") {
                    Text(message.content).font(Theme.code).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            } else { MarkdownContent(text: message.content) }
            ForEach(message.toolCalls) { call in
                DisclosureGroup {
                    Text(call.arguments).font(Theme.code).textSelection(.enabled)
                } label: { Label(call.name, systemImage: "wrench.and.screwdriver") }
                .font(.caption).padding(10).background(Theme.primaryContainer, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(message.role == .user ? 16 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(message.role == .user ? Theme.primaryContainer : .clear, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
    private var icon: String {
        switch message.role {
        case .user: "person.crop.circle"
        case .assistant: "sparkles"
        case .tool: "terminal"
        case .system: "gearshape"
        }
    }
}

private struct MarkdownBlock: Identifiable {
    let id: Int
    let text: String
    let language: String?
}

private struct MarkdownContent: View {
    let text: String
    private var blocks: [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        var lines: [String] = []
        var language: String?
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("```") {
                if !lines.isEmpty {
                    result.append(MarkdownBlock(id: result.count, text: lines.joined(separator: "\n"), language: language))
                    lines = []
                }
                if language != nil { language = nil }
                else { language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
            } else { lines.append(line) }
        }
        if !lines.isEmpty { result.append(MarkdownBlock(id: result.count, text: lines.joined(separator: "\n"), language: language)) }
        return result
    }
    var body: some View {
        ForEach(blocks) { block in
            if let language = block.language {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(language.isEmpty ? "code" : language).foregroundStyle(.secondary)
                        Spacer()
                        Button("copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(block.text, forType: .string)
                        }.buttonStyle(.plain)
                    }.font(.caption)
                    ScrollView(.horizontal) { Text(block.text).font(Theme.code).textSelection(.enabled) }
                }.padding(12).background(Theme.surfaceContainer, in: RoundedRectangle(cornerRadius: 10))
            } else {
                Text((try? AttributedString(markdown: block.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(block.text))
                    .font(Theme.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
