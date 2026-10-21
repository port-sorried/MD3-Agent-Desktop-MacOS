import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct InputBarView: View {
    @Bindable var model: AppModel
    @State private var importing = false
    var body: some View {
        VStack(spacing: 10) {
            TextField("message or drop a text file", text: $model.draft, axis: .vertical)
                .lineLimit(2...10).textFieldStyle(.plain).font(Theme.body).padding(.horizontal, 4)
                .onSubmit { model.send() }.disabled(model.isRunning)
                .accessibilityLabel("message")
            HStack {
                Button { importing = true } label: { Image(systemName: "paperclip") }
                    .help("attach text files").disabled(model.isRunning)
                Text("return to send").font(.caption).foregroundStyle(.secondary)
                if model.voice.isListening {
                    Label("микрофон включен", systemImage: "mic.fill").font(.caption).foregroundStyle(.orange)
                    Button("выкл. микрофон") { UserDefaults.standard.set(false, forKey: "voice.enabled"); model.voice.stop() }
                        .font(.caption)
                }
                Spacer()
                if model.isRunning {
                    Button { model.stop() } label: { Label("stop", systemImage: "stop.fill") }
                } else {
                    Button { model.send() } label: { Label("send", systemImage: "arrow.up") }
                        .buttonStyle(MaterialButtonStyle(filled: true)).disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.storage == nil)
                }
            }
        }
        .padding(20)
        .background(Theme.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay { RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.outline.opacity(0.15), lineWidth: 1) }
        .padding(.horizontal, 24).padding(.bottom, 20).padding(.top, 8)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.text, .sourceCode, .json], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): Task { await model.importFiles(urls) }
            case .failure(let error): model.errorMessage = error.localizedDescription
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !model.isRunning else { return false }
            Task { await model.importFiles(urls) }; return true
        }
    }
}
