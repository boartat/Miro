//
//  Downloader.swift
//  Miro
//

import Foundation

enum DownloadError: LocalizedError {
    case badStatus(Int)

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "서버가 응답하지 않아요 (HTTP \(code))"
        }
    }
}

/// File downloads with byte-level progress (drives Miro's loading bars).
enum Downloader {
    static func download(
        _ url: URL, to destination: URL,
        progress: @escaping @Sendable (_ fraction: Double, _ received: Int64, _ total: Int64) -> Void
    ) async throws -> URL {
        MiroPaths.ensure(destination.deletingLastPathComponent())
        let delegate = DownloadDelegate(destination: destination, onProgress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.setContinuation(continuation)
                session.downloadTask(with: url).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let onProgress: @Sendable (Double, Int64, Int64) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var lastReported: Double = -1

    init(destination: URL, onProgress: @escaping @Sendable (Double, Int64, Int64) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    func setContinuation(_ continuation: CheckedContinuation<URL, Error>) {
        lock.lock(); defer { lock.unlock() }
        self.continuation = continuation
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else {
            onProgress(-1, totalBytesWritten, -1)
            return
        }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        // Throttle UI updates to 0.25 % steps
        if fraction - lastReported >= 0.0025 || fraction >= 1 {
            lastReported = fraction
            onProgress(fraction, totalBytesWritten, totalBytesExpectedToWrite)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            finish(.failure(DownloadError.badStatus(http.statusCode)))
            return
        }
        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: location, to: destination)
            finish(.success(destination))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }
}

extension Int64 {
    var byteString: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
