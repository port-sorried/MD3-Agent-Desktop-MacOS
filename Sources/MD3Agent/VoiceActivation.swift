import Foundation
import Observation
@preconcurrency import AVFoundation
@preconcurrency import Speech
import AgentCore

// The audio callback only appends buffers. Stopping closes the request under
// the same lock, so an in-flight callback cannot append after endAudio().
private final class SpeechAudioSink: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        request?.append(buffer)
    }
    func finish() {
        lock.lock(); defer { lock.unlock() }
        request?.endAudio(); request = nil
    }
}

@MainActor @Observable
final class VoiceActivation {
    private(set) var status = "микрофон выключен"
    private(set) var isListening = false
    private(set) var lastCommand = ""
    private var engine: AVAudioEngine?
    private var recognition: SFSpeechRecognitionTask?
    private var sink: SpeechAudioSink?
    private var rotation: Task<Void, Never>?
    private var silence: Task<Void, Never>?
    private var sessionID = UUID()
    private var desired = false
    private var wakeName = ""
    private var localeID = "ru-RU"
    private var pendingCommand: String?
    private var commandHandler: (@MainActor (String) -> Void)?

    func configure(enabled: Bool, name: String, locale: String, onCommand: @escaping @MainActor (String) -> Void) async {
        stop()
        guard enabled else { return }
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 60, cleaned.contains(where: \.isLetter) else {
            status = "задайте имя из букв, не длиннее 60 символов"; return
        }
        desired = true; wakeName = cleaned; localeID = locale; commandHandler = onCommand
        let generation = sessionID
        status = "запрашиваю доступ к микрофону"
        let microphone = await AVCaptureDevice.requestAccess(for: .audio)
        guard generation == sessionID, desired else { return }
        guard microphone else { fail("нет доступа к микрофону: разрешите его в системных настройках"); return }
        let authorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { authorization in continuation.resume(returning: authorization == .authorized) }
        }
        guard generation == sessionID, desired else { return }
        guard authorized else { fail("нет разрешения на распознавание речи"); return }
        startSession()
    }

    func stop() {
        desired = false; sessionID = UUID()
        closeSession()
        commandHandler = nil; pendingCommand = nil
        status = "микрофон выключен"
    }

    private func closeSession() {
        rotation?.cancel(); rotation = nil
        silence?.cancel(); silence = nil
        if let engine { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        engine = nil
        sink?.finish(); sink = nil
        recognition?.cancel(); recognition = nil
        isListening = false
    }

    private func fail(_ message: String) {
        desired = false; sessionID = UUID(); closeSession(); status = message
    }

    private func startSession() {
        guard desired else { return }
        sessionID = UUID()
        let generation = sessionID
        pendingCommand = nil
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID)), recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            fail("локальное распознавание для этого языка недоступно; выберите другой язык или установите языковые ресурсы macos")
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.contextualStrings = [wakeName]
        let audioSink = SpeechAudioSink(request)
        let audioEngine = AVAudioEngine()
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { fail("микрофон недоступен"); return }
        sink = audioSink
        engine = audioEngine
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in audioSink.append(buffer) }
        recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let transcript = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            let failure = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, generation == self.sessionID, self.desired else { return }
                if let transcript { self.receive(transcript, final: final) }
                if generation != self.sessionID { return }
                if final { self.restart() }
                else if let failure { self.fail("распознавание остановлено: \(failure)") }
            }
        }
        do {
            audioEngine.prepare(); try audioEngine.start()
            isListening = true; status = "слушаю имя: \(wakeName)"
            rotation = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(45)) } catch { return }
                guard let self, generation == sessionID else { return }
                if pendingCommand?.isEmpty == false { deliver() } else { restart() }
            }
        } catch { fail("не удалось включить микрофон: \(error.localizedDescription)") }
    }

    private func receive(_ transcript: String, final: Bool) {
        guard let command = WakePhrase.command(in: transcript, name: wakeName) else { return }
        pendingCommand = command
        status = command.isEmpty ? "имя услышано, говорите команду" : "команда: \(String(command.prefix(100)))"
        silence?.cancel()
        guard !command.isEmpty else { return }
        if final { deliver(); return }
        let generation = sessionID
        silence = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(1600)) } catch { return }
            guard let self, generation == sessionID else { return }
            deliver()
        }
    }

    private func deliver() {
        guard let command = pendingCommand, !command.isEmpty else { return }
        lastCommand = command
        let handler = commandHandler
        restart()
        handler?(command)
    }

    private func restart() {
        sessionID = UUID(); closeSession()
        if desired { startSession() }
    }
}
