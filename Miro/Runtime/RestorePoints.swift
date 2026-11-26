//
//  RestorePoints.swift
//  Miro
//
//  Copies of an engine's C: drive taken before Miro changes it (library installs), so a change that breaks
//  something can be undone. Copies are APFS clones: instant, and they only use disk space for what differs
//  later. C:\Games (the game files) is left out; library installs never touch it.
//

import Foundation
import WhiskyKit

struct RestorePoint: Identifiable, Codable, Hashable, Sendable {
    /// Folder name under RestorePoints.folder
    let id: String
    let engine: WineEngineKind
    let createdAt: Date
    /// Why it was taken, e.g. "Visual C++ 2015–2022 설치 전"
    let reason: String

    var folder: URL { RestorePoints.folder.appending(path: id) }
}

enum RestorePoints {
    /// Next to the prefixes, so clones stay on the same APFS volume
    static let folder = BottleData.defaultBottleDir.appending(path: ".miro-restore")
    /// Newest restore points kept per engine
    static let keep = 3

    /// Takes a restore point of `engine`'s prefix. Stops the engine's Wine first so the registry is on disk.
    /// `keeping` is never pruned (the point being restored from).
    static func create(for engine: WineEngine, reason: String, keeping: RestorePoint? = nil) async throws -> RestorePoint {
        guard engine.hasPrefix else { throw InstallError(message: "복구 지점을 만들 C: 드라이브가 없어요") }
        await stop(engine)
        let stamp = Int(Date.now.timeIntervalSince1970 * 1000)
        let point = RestorePoint(id: "\(engine.kind.rawValue)-\(stamp)", engine: engine.kind, createdAt: .now, reason: reason)
        try FileManager.default.createDirectory(at: point.folder, withIntermediateDirectories: true)
        do {
            try await copyPrefix(from: engine.bottleURL, to: point.folder.appending(path: "prefix"))
            let data = try JSONEncoder.iso.encode(point)
            try data.write(to: point.folder.appending(path: "point.json"), options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: point.folder)
            throw error
        }
        prune(engine.kind, keeping: keeping)
        return point
    }

    /// Puts `point` back as the engine's C: drive. The current state is saved as a restore point first,
    /// so going back is itself undoable.
    static func restore(_ point: RestorePoint) async throws {
        let engine = WineEngine.of(point.engine)
        let saved = point.folder.appending(path: "prefix")
        guard saved.appending(path: "system.reg").fileExists else {
            throw InstallError(message: "복구 지점 파일이 없어요")
        }
        // Nothing is deleted unless the current state was saved first
        if engine.hasPrefix {
            _ = try await create(for: engine, reason: "되돌리기 직전 상태", keeping: point)
        }
        await stop(engine)
        let fileManager = FileManager.default
        let prefix = engine.bottleURL
        // Everything except C:\Games is replaced
        for item in try fileManager.contentsOfDirectory(at: prefix, includingPropertiesForKeys: nil)
        where item.lastPathComponent != "drive_c" {
            try fileManager.removeItem(at: item)
        }
        let driveC = prefix.appending(path: "drive_c")
        if driveC.fileExists {
            for item in try fileManager.contentsOfDirectory(at: driveC, includingPropertiesForKeys: nil)
            where item.lastPathComponent != "Games" {
                try fileManager.removeItem(at: item)
            }
        }
        try await copyPrefix(from: saved, to: prefix)
    }

    /// Newest first
    static func list() -> [RestorePoint] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { url in
            guard let data = try? Data(contentsOf: url.appending(path: "point.json")) else { return nil }
            return try? JSONDecoder.iso.decode(RestorePoint.self, from: data)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    private static func prune(_ kind: WineEngineKind, keeping: RestorePoint?) {
        let points = list().filter { $0.engine == kind && $0.id != keeping?.id }
        for old in points.dropFirst(keeping == nil ? keep : keep - 1) {
            try? FileManager.default.removeItem(at: old.folder)
        }
    }

    private static func stop(_ engine: WineEngine) async {
        engine.killAll()
        for _ in 0..<20 where engine.processCount() > 0 {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Clones a prefix without C:\Games (APFS `cp -c`), creating `target` if needed
    private static func copyPrefix(from source: URL, to target: URL) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: target.appending(path: "drive_c"), withIntermediateDirectories: true)
        var items: [(URL, URL)] = []
        for item in try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        where item.lastPathComponent != "drive_c" {
            items.append((item, target))
        }
        let driveC = source.appending(path: "drive_c")
        for item in (try? fileManager.contentsOfDirectory(at: driveC, includingPropertiesForKeys: nil)) ?? []
        where item.lastPathComponent != "Games" {
            items.append((item, target.appending(path: "drive_c")))
        }
        for (item, destination) in items {
            let (code, output) = try await ProcessRunner.run(
                executable: URL(fileURLWithPath: "/bin/cp"),
                arguments: ["-c", "-R", item.commandPath, destination.commandPath],
                environment: ProcessRunner.baseEnvironment
            )
            guard code == 0 else { throw InstallError(message: "C: 드라이브 복사 실패: \(output)") }
        }
    }
}

private extension JSONEncoder {
    static var iso: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var iso: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
