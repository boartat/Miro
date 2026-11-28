//
//  ProcessRunner.swift
//  Miro
//

import Foundation

enum ProcessEvent: Sendable {
    case output(String)
    case exited(Int32)
}

/// A running child process that can be stopped from any thread.
final class RunningProcess: @unchecked Sendable {
    let process: Process
    let logURL: URL?

    init(process: Process, logURL: URL?) {
        self.process = process
        self.logURL = logURL
    }

    var isRunning: Bool { process.isRunning }

    func terminate() {
        if process.isRunning { process.terminate() }
    }
}

enum ProcessRunner {
    /// Environment variables every child process needs (GUI apps start with an almost empty environment)
    static var baseEnvironment: [String: String] {
        let current = ProcessInfo.processInfo.environment
        var env: [String: String] = [:]
        for key in ["HOME", "USER", "LOGNAME", "TMPDIR", "SHELL", "LANG", "__CF_USER_TEXT_ENCODING"] {
            if let value = current[key] { env[key] = value }
        }
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        return env
    }

    /// Start a process; stdout and stderr are merged, streamed and (optionally) written to `logURL`.
    static func start(
        executable: URL, arguments: [String], environment: [String: String],
        directory: URL? = nil, logURL: URL? = nil, qualityOfService: QualityOfService = .userInitiated
    ) throws -> (RunningProcess, AsyncStream<ProcessEvent>) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = directory
        process.qualityOfService = qualityOfService

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        var logHandle: FileHandle?
        if let logURL {
            MiroPaths.ensure(logURL.deletingLastPathComponent())
            FileManager.default.createFile(atPath: logURL.path(percentEncoded: false), contents: nil)
            logHandle = try? FileHandle(forWritingTo: logURL)
            let header = "Miro — \(Date.now.formatted())\n$ \(executable.lastPathComponent) \(arguments.joined(separator: " "))\n\n"
            logHandle?.write(Data(header.utf8))
        }
        let log = logHandle.map { LockedHandle($0) }

        let stream = AsyncStream<ProcessEvent> { continuation in
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    handle.readabilityHandler = nil
                    return
                }
                log?.write(data)
                continuation.yield(.output(String(decoding: data, as: UTF8.self)))
            }
            process.terminationHandler = { process in
                let status = process.terminationStatus
                // Let the last buffered output arrive, but never block on children that keep the pipe open
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    log?.write(Data("\n[exit code \(status)]\n".utf8))
                    log?.close()
                    continuation.yield(.exited(status))
                    continuation.finish()
                }
            }
        }

        try process.run()
        return (RunningProcess(process: process, logURL: logURL), stream)
    }

    /// Run to completion and return (exit code, full output)
    static func run(
        executable: URL, arguments: [String], environment: [String: String], directory: URL? = nil
    ) async throws -> (Int32, String) {
        let (_, stream) = try start(executable: executable, arguments: arguments,
                                    environment: environment, directory: directory)
        var output = ""
        var status: Int32 = -1
        for await event in stream {
            switch event {
            case .output(let text): output += text
            case .exited(let code): status = code
            }
        }
        return (status, output)
    }
}

/// Serialises writes to a log file from the pipe and termination handlers. A log stops growing at `limit`
/// (a game that prints without end once filled 40 GB); the exit line is still written.
private final class LockedHandle: @unchecked Sendable {
    static let limit = 64 * 1024 * 1024
    private let handle: FileHandle
    private let lock = NSLock()
    private var closed = false
    private var written = 0
    private var full = false

    init(_ handle: FileHandle) { self.handle = handle }

    func write(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        if full {
            // only the closing "[exit code …]" line gets through
            guard data.count < 64, String(decoding: data, as: UTF8.self).contains("[exit code") else { return }
        } else if written + data.count > Self.limit {
            full = true
            try? handle.write(contentsOf: Data("\n[Miro: 로그가 64MB를 넘어 이후 출력은 저장하지 않았어요]\n".utf8))
            return
        }
        written += data.count
        try? handle.write(contentsOf: data)
    }

    func close() {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        try? handle.close()
    }
}
