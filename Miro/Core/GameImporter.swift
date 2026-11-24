//
//  GameImporter.swift
//  Miro
//
//  Dropping a game *folder* copies the whole folder into Miro (C:\Games\<name> in the Windows 11
//  prefix) so the exe keeps every file it needs. Dropping a single exe only registers that file.
//

import Foundation

/// A folder being copied into Miro (shown as a row with a loading bar in the sidebar)
struct ImportJob: Identifiable, Equatable, Sendable {
    let id = UUID()
    let name: String
    var progress: Double = 0
    var detail = "준비 중…"
}

/// A dropped folder with more than one plausible exe — the user picks which one starts the game
struct FolderChoice: Identifiable, Sendable {
    let id = UUID()
    let folder: URL
    /// Paths relative to `folder`, best guess first
    let candidates: [String]
}

struct ImportError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum GameImporter {
    /// Installers, redistributables and tools that are never the game itself
    private static let ignoredPrefixes = [
        "unins", "uninst", "crash", "setup", "install", "update", "patch", "redist", "vc_redist", "vcredist",
        "dxsetup", "dxwebsetup", "directx", "dotnet", "ndp4", "ue4prereq", "ueprereq", "oalinst", "physx",
        "notification_helper", "unitycrashhandler", "cefsharp", "dxdiag", "7z", "unrar", "winrar"
    ]
    private static let ignoredFolders: Set<String> = [
        "_commonredist", "commonredist", "redist", "_redist", "redistributables", "directx", "vcredist",
        "dotnet", "support", "installers", "__installer", "prereqs", "prerequisites", "engine", "monobleedingedge"
    ]
    private static let preferredNames = ["game.exe", "rpg_rt.exe", "nw.exe"]

    /// Every plausible game executable inside `folder` (up to 3 levels deep), best guess first.
    static func candidates(in folder: URL) -> [String] {
        let fileManager = FileManager.default
        let root = folder.path(percentEncoded: false)
        guard let enumerator = fileManager.enumerator(atPath: root) else { return [] }

        var found: [(path: String, score: Int, size: Int64)] = []
        let folderName = folder.lastPathComponent.lowercased()
        while let relative = enumerator.nextObject() as? String {
            let components = relative.split(separator: "/").map { $0.lowercased() }
            if enumerator.level > 4 { enumerator.skipDescendants(); continue }
            if let attributes = enumerator.fileAttributes, attributes[.type] as? FileAttributeType == .typeDirectory {
                if let last = components.last, ignoredFolders.contains(last) || last.hasSuffix(".app") {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard let fileName = components.last, fileName.hasSuffix(".exe") else { continue }
            if ignoredPrefixes.contains(where: { fileName.hasPrefix($0) }) { continue }

            let size = (enumerator.fileAttributes?[.size] as? NSNumber)?.int64Value ?? 0
            var score = 0
            if preferredNames.contains(fileName) { score += 40 }
            if fileName == "\(folderName).exe" { score += 50 }
            if fileName.hasSuffix("-win64-shipping.exe") { score += 10 }
            if fileName.contains("launcher") { score -= 5 }
            if fileName.contains("config") || fileName.contains("editor") || fileName.contains("server") { score -= 20 }
            score -= (components.count - 1) * 15  // prefer files near the top
            found.append((relative, score, size))
        }
        return found
            .sorted { ($0.score, $0.size) > ($1.score, $1.size) }
            .map(\.path)
    }

    /// `C:\Games\<name>` (with " 2", " 3" … if it already exists)
    static func destination(for folder: URL) -> URL {
        let base = folder.lastPathComponent
        var candidate = MiroPaths.gamesFolder.appending(path: base)
        var index = 2
        while candidate.fileExists {
            candidate = MiroPaths.gamesFolder.appending(path: "\(base) \(index)")
            index += 1
        }
        return candidate
    }

    /// Copies `source` into `destination`, reporting (fraction, detail). Uses APFS clones when possible.
    static func copyFolder(
        _ source: URL, to destination: URL,
        progress: @escaping @Sendable (Double, String) -> Void
    ) throws {
        let fileManager = FileManager.default
        let root = source.path(percentEncoded: false)
        guard let enumerator = fileManager.enumerator(atPath: root) else {
            throw ImportError(message: "폴더를 읽을 수 없어요")
        }

        // 1. Inventory
        var items: [(relative: String, type: FileAttributeType, size: Int64)] = []
        var total: Int64 = 0
        while let relative = enumerator.nextObject() as? String {
            let type = enumerator.fileAttributes?[.type] as? FileAttributeType ?? .typeRegular
            let size = (enumerator.fileAttributes?[.size] as? NSNumber)?.int64Value ?? 0
            items.append((relative, type, type == .typeRegular ? size : 0))
            if type == .typeRegular { total += size }
        }

        // 2. Disk space (clones on the same volume cost nothing)
        MiroPaths.ensure(destination.deletingLastPathComponent())
        let keys: Set<URLResourceKey> = [.volumeIdentifierKey, .volumeAvailableCapacityForImportantUsageKey]
        if let sourceValues = try? source.resourceValues(forKeys: keys),
           let targetValues = try? destination.deletingLastPathComponent().resourceValues(forKeys: keys),
           let free = targetValues.volumeAvailableCapacityForImportantUsage,
           !(sourceValues.volumeIdentifier?.isEqual(targetValues.volumeIdentifier) ?? false),
           total > free {
            throw ImportError(message: "저장 공간이 부족해요 (필요 \(total.byteString), 남은 공간 \(free.byteString))")
        }

        // 3. Copy
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        var copied: Int64 = 0
        var lastReport = Date.distantPast
        for item in items {
            let target = destination.appending(path: item.relative)
            switch item.type {
            case .typeDirectory:
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            default:
                try fileManager.copyItem(at: source.appending(path: item.relative), to: target)
                copied += item.size
            }
            if Date.now.timeIntervalSince(lastReport) > 0.1 {
                lastReport = .now
                let fraction = total > 0 ? Double(copied) / Double(total) : 1
                progress(fraction, "\(copied.byteString) / \(total.byteString)")
            }
        }
        progress(1, "\(total.byteString) 복사 완료")
    }
}
