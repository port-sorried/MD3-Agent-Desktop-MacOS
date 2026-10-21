import Foundation
import Darwin

public struct ProcessResult: Codable, Sendable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
    public var timedOut: Bool
    public var truncated: Bool
}

private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

public enum ProcessRunner {
    public static func run(executable: URL, arguments: [String], directory: URL, input: String = "",
                           timeout: TimeInterval = 60, maximumOutputBytes: Int = 1_048_576) async throws -> ProcessResult {
        guard timeout > 0, timeout <= 600, maximumOutputBytes > 0, input.utf8.count <= 1_048_576 else {
            throw AgentError.limit("invalid process limits")
        }
        let cancellation = CancellationFlag()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                if cancellation.cancelled { throw CancellationError() }
                let process = Process()
                let outputPipe = Pipe(), errorPipe = Pipe()
                // Use a file for stdin so a child that never reads cannot block its parent.
                let inputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try Data(input.utf8).write(to: inputURL, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: inputURL.path)
                defer { try? FileManager.default.removeItem(at: inputURL) }
                let inputHandle = try FileHandle(forReadingFrom: inputURL)
                defer { try? inputHandle.close() }
                process.executableURL = executable
                process.arguments = arguments
                process.currentDirectoryURL = directory
                process.environment = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                                       "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                                       "LANG": "en_US.UTF-8", "TMPDIR": FileManager.default.temporaryDirectory.path]
                process.standardInput = inputHandle
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                try process.run()
                try outputPipe.fileHandleForWriting.close()
                try errorPipe.fileHandleForWriting.close()
                let outputFD = outputPipe.fileHandleForReading.fileDescriptor
                let errorFD = errorPipe.fileHandleForReading.fileDescriptor
                defer {
                    try? outputPipe.fileHandleForReading.close()
                    try? errorPipe.fileHandleForReading.close()
                }
                _ = fcntl(outputFD, F_SETFL, O_NONBLOCK)
                _ = fcntl(errorFD, F_SETFL, O_NONBLOCK)
                let started = ProcessInfo.processInfo.systemUptime
                var stopTime: TimeInterval?
                var timedOut = false
                var stdout = Data(), stderr = Data()
                var truncated = false
                var buffer = [UInt8](repeating: 0, count: 16_384)
                func drain(_ fd: Int32, into captured: inout Data) {
                    // Limit work per poll as well as retained bytes, even for a noisy child.
                    for _ in 0..<16 {
                        let count = Darwin.read(fd, &buffer, buffer.count)
                        if count <= 0 { break }
                        let room = max(0, maximumOutputBytes - captured.count)
                        captured.append(contentsOf: buffer.prefix(min(count, room)))
                        if count > room { truncated = true }
                    }
                }
                while process.isRunning {
                    drain(outputFD, into: &stdout); drain(errorFD, into: &stderr)
                    let now = ProcessInfo.processInfo.systemUptime
                    if stopTime == nil && (cancellation.cancelled || now - started >= timeout) {
                        timedOut = !cancellation.cancelled
                        stopTime = now
                        process.terminate()
                    }
                    if let stopTime, now - stopTime >= 1 { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
                    usleep(10_000)
                }
                process.waitUntilExit()
                drain(outputFD, into: &stdout); drain(errorFD, into: &stderr)
                if cancellation.cancelled { throw CancellationError() }
                return ProcessResult(exitCode: process.terminationStatus, stdout: String(decoding: stdout, as: UTF8.self),
                                     stderr: String(decoding: stderr, as: UTF8.self), timedOut: timedOut, truncated: truncated)
            }.value
        } onCancel: { cancellation.cancel() }
    }
}
