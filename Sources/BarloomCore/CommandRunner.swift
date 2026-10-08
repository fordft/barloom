import Darwin
import Foundation

public struct CommandResult: Sendable {
    public let output: String
    public let errorOutput: String
    public let exitCode: Int32
}

public enum CommandError: Error, LocalizedError, Sendable {
    case timedOut, outputTooLarge
    public var errorDescription: String? {
        switch self {
        case .timedOut: "The port scan took too long. Try refreshing."
        case .outputTooLarge: "The port scan returned more data than expected."
        }
    }
}

public enum CommandRunner {
    public static func run(executable: String, arguments: [String], timeout: TimeInterval = 5) async throws -> CommandResult {
        let handle = RunningCommand(executable: executable, arguments: arguments, timeout: timeout)
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .utility) { try await handle.run() }.value
        } onCancel: {
            handle.cancel()
        }
    }
}

/// Lock protects cancellation and timeout state; pipes are drained on separate worker tasks.
private final class RunningCommand: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private let timeout: TimeInterval
    private var cancelled = false
    private var timedOut = false

    init(executable: String, arguments: [String], timeout: TimeInterval) {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        self.timeout = timeout
    }

    func cancel() {
        lock.withLock {
            cancelled = true
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) { [self] in
            lock.withLock {
                if cancelled && process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
            }
        }
    }

    func run() async throws -> CommandResult {
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try lock.withLock {
            guard !cancelled else { throw CancellationError() }
            try process.run()
        }

        let deadline = DispatchWorkItem { [self] in
            lock.withLock {
                if process.isRunning {
                    timedOut = true
                    process.terminate()
                }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) { [self] in
                lock.withLock {
                    if timedOut && process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
                }
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: deadline)
        defer { deadline.cancel() }
        let outputTask = Task.detached(priority: .utility) { try Self.readBounded(outputPipe.fileHandleForReading) }
        let errorTask = Task.detached(priority: .utility) { try Self.readBounded(errorPipe.fileHandleForReading) }

        do {
            let output = try await outputTask.value
            let errorOutput = try await errorTask.value
            process.waitUntilExit()
            try lock.withLock {
                if cancelled { throw CancellationError() }
                if timedOut { throw CommandError.timedOut }
            }
            return CommandResult(output: String(decoding: output, as: UTF8.self), errorOutput: String(decoding: errorOutput, as: UTF8.self), exitCode: process.terminationStatus)
        } catch {
            cancel()
            process.waitUntilExit()
            _ = try? await outputTask.value
            _ = try? await errorTask.value
            throw error
        }
    }

    private static func readBounded(_ handle: FileHandle) throws -> Data {
        defer { try? handle.close() }
        var result = Data()
        while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
            guard result.count + chunk.count <= 1_048_576 else { throw CommandError.outputTooLarge }
            result.append(chunk)
        }
        return result
    }
}
