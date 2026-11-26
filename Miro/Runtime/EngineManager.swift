//
//  EngineManager.swift
//  Miro
//
//  Installs the modern Wine engine next to the classic one, keeps its prefix ready and decides which
//  engine runs a game.
//

import CryptoKit
import Foundation
import WhiskyKit

/// Where the modern engine comes from. Every download is pinned to a SHA-256.
enum ModernEngine {
    static let wineVersion = "11.21"
    /// WineHQ Staging for macOS (official WineHQ packages built by Gcenx), LGPL-2.1
    static let wineURL = URL(string:
        "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.21/wine-staging-11.21-osx64.tar.xz")!
    static let wineSHA256 = "d7bcd5abf4df27aae397a7898aef074fea4a2e0b51e0a55aa9659517bbf9d452"
    /// DXVK-macOS 1.10.3 (Direct3D 9/10/11 → Vulkan → MoltenVK), zlib license
    static let dxvkURL = URL(string:
        "https://github.com/Gcenx/DXVK-macOS/releases/download/v1.10.3-20230507/dxvk-macOS-async-v1.10.3-20230507.tar.gz")!
    static let dxvkSHA256 = "f67d99d0a8eeedd7d406b283a3df9f939b5965acb00efcb33d0c6235c195a516"
    /// DXMT (Direct3D 10/11 → Metal), MIT license up to v0.80
    static let dxmtVersion = "v0.80"
    static let dxmtURL = URL(string:
        "https://github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz")!
    static let dxmtSHA256 = "8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d"
    static let dxmtDownloadSize = "약 18MB"
    static let downloadSize = "약 255MB"

    /// Keep this path short: Wine's font loader copies `<root>/share/wine/fonts` into a MAX_PATH buffer and
    /// a long root crashes every process at startup (then explorer.exe is restarted in a loop).
    static let root = MiroPaths.engines.appending(path: "wine-\(wineVersion)")
    static let dxvkFolder = root.appending(path: "miro/dxvk")
    static let marker = root.appending(path: "miro/engine.json")

    /// DLLs DXVK provides, per prefix folder
    static let dxvkDLLs = ["d3d11", "dxgi", "d3d10core"]

    static var isInstalled: Bool {
        root.appending(path: "bin/wine").fileExists && marker.fileExists
            && dxvkFolder.appending(path: "x64/d3d11.dll").fileExists
    }

    // MARK: DXMT

    /// DXMT's builtin DLLs go where Wine looks for its own builtins
    static let dxmtDLLs = ["d3d10core", "d3d11", "dxgi", "winemetal"]
    static let dxmtMarker = root.appending(path: "miro/dxmt.json")
    /// The engine's own files that DXMT replaces, kept so DXMT can be taken out again
    static let originals = root.appending(path: "miro/original")
    static let unixFolder = root.appending(path: "lib/wine/x86_64-unix")

    /// Miro's build of this engine's winemac.so: the same Wine 11.21 Staging source plus the `macdrv_functions`
    /// table DXMT looks for (source and build script: Engine/winemac-dxmt in the repository). Stored as `.so.bin`
    /// so Xcode copies it as a resource instead of trying to link it.
    static var bridgedWinemac: URL? {
        Bundle.main.url(forResource: "winemac-\(wineVersion)-dxmt.so", withExtension: "bin")
    }

    static var hasDXMT: Bool {
        dxmtMarker.fileExists && unixFolder.appending(path: "winemetal.so").fileExists
    }
}

struct DXMTMarker: Codable {
    var dxmtVersion: String
    var dxmtSHA256: String
    var winemacSHA256: String
    var installedAt: Date
}

struct EngineMarker: Codable {
    var wineVersion: String
    var wineSHA256: String
    var dxvkSHA256: String
    var installedAt: Date
}

@MainActor
final class EngineManager: ObservableObject {
    static let shared = EngineManager()

    enum State: Equatable {
        case notInstalled, installing, installed, failed(String)
    }

    @Published private(set) var modernState: State = .notInstalled
    @Published private(set) var progress: Double = 0
    @Published private(set) var detail = ""
    @Published private(set) var modernBottle: Bottle?
    /// DXMT is installed into the modern engine
    @Published private(set) var dxmtReady = false
    @Published private(set) var dxmtInstalling = false
    @Published private(set) var dxmtError: String?

    private init() {
        refresh()
    }

    func refresh() {
        guard modernState != .installing else { return }
        let ready = ModernEngine.isInstalled && WineEngine.modern.hasPrefix
        modernState = ready ? .installed : .notInstalled
        dxmtReady = ready && ModernEngine.hasDXMT
        if ready, modernBottle == nil {
            modernBottle = Bottle(bottleUrl: MiroPaths.modernBottle, isAvailable: true)
        }
    }

    /// How `game` draws Direct3D 10/11 when it runs on the modern engine
    func graphics(for game: Game) -> GraphicsBackend {
        switch game.graphicsPreference {
        case .dxvk: return .dxvk
        case .dxmt, .auto: return dxmtReady ? .dxmt : .dxvk
        }
    }

    func isReady(_ kind: WineEngineKind) -> Bool {
        switch kind {
        case .classic: return RuntimeManager.shared.isReady
        case .modern: return modernState == .installed && modernBottle != nil
        }
    }

    func bottle(for kind: WineEngineKind) -> Bottle? {
        kind == .classic ? RuntimeManager.shared.bottle : modernBottle
    }

    /// The engine `game` runs with right now
    func engine(for game: Game) -> WineEngineKind {
        switch game.winePreference {
        case .classic: return .classic
        case .modern: return .modern
        case .auto: return game.wineLearned ?? .classic
        }
    }

    // MARK: - Install

    /// Downloads (or adopts an existing copy of) Wine + DXVK, then prepares the modern prefix.
    func installModern() async {
        guard modernState != .installing else { return }
        modernState = .installing
        progress = 0
        do {
            try await installEngineFiles()
            if !ModernEngine.hasDXMT {
                // DXMT is an extra: if it can't be installed, DXVK still draws every game
                do {
                    try await installDXMTFiles(span: 0.86...0.9)
                    dxmtError = nil
                } catch {
                    dxmtError = error.localizedDescription
                }
            }
            detail = "Windows 11 환경 준비 중… (처음 한 번은 1~2분 걸려요)"
            progress = 0.9
            try await prepareBottle()
            progress = 1
            detail = "설치 완료"
            modernState = .installed
            dxmtReady = ModernEngine.hasDXMT
            modernBottle = Bottle(bottleUrl: MiroPaths.modernBottle, isAvailable: true)
        } catch {
            modernState = .failed(error.localizedDescription)
            detail = error.localizedDescription
        }
    }

    /// Adds DXMT to a modern engine that was installed before Miro shipped it.
    func installDXMT() async {
        guard modernState == .installed, !dxmtInstalling else { return }
        guard !GameLauncher.shared.runningEngine.values.contains(.modern) else {
            dxmtError = "최신 엔진으로 실행 중인 게임을 먼저 종료해 주세요."
            return
        }
        dxmtInstalling = true
        dxmtError = nil
        progress = 0
        defer { dxmtInstalling = false }
        do {
            // Wine's background services would keep the old winemac.so loaded
            WineEngine.modern.killAll()
            try await installDXMTFiles(span: 0...0.95)
            progress = 1
            detail = "DXMT 설치 완료"
        } catch {
            dxmtError = error.localizedDescription
        }
        dxmtReady = ModernEngine.hasDXMT
    }

    private func installDXMTFiles(span: ClosedRange<Double>) async throws {
        guard let winemac = ModernEngine.bridgedWinemac else {
            throw InstallError(message: "이 Miro에는 DXMT용 Wine 부품이 들어 있지 않아요")
        }
        detail = "DXMT 받는 중…"
        let archive = MiroPaths.downloads.appending(path: ModernEngine.dxmtURL.lastPathComponent)
        try await download(ModernEngine.dxmtURL, to: archive, sha256: ModernEngine.dxmtSHA256, span: span)
        detail = "DXMT 설치 중…"
        let winemacDigest = try await Task.detached(priority: .userInitiated) { () -> String in
            defer { try? FileManager.default.removeItem(at: archive) }
            try Self.applyDXMT(archive, winemac: winemac)
            return try Self.sha256(of: winemac)
        }.value
        let marker = DXMTMarker(dxmtVersion: ModernEngine.dxmtVersion, dxmtSHA256: ModernEngine.dxmtSHA256,
                                winemacSHA256: winemacDigest, installedAt: .now)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(marker).write(to: ModernEngine.dxmtMarker, options: .atomic)
    }

    func uninstallModern() {
        guard modernState != .installing else { return }
        WineEngine.modern.killAll()
        try? FileManager.default.removeItem(at: ModernEngine.root)
        // The prefix holds save data of games that ran on this engine — move it to the Trash, never delete
        if WineEngine.modern.hasPrefix {
            try? FileManager.default.trashItem(at: MiroPaths.modernBottle, resultingItemURL: nil)
        }
        modernBottle = nil
        modernState = .notInstalled
    }

    private func installEngineFiles() async throws {
        let fileManager = FileManager.default
        let root = ModernEngine.root
        if !(root.appending(path: "bin/wine").fileExists && Self.reportsVersion(root)) {
            detail = "Wine \(ModernEngine.wineVersion) 받는 중…"
            let archive = MiroPaths.downloads.appending(path: ModernEngine.wineURL.lastPathComponent)
            try await download(ModernEngine.wineURL, to: archive, sha256: ModernEngine.wineSHA256, span: 0...0.75)
            detail = "압축 푸는 중…"
            progress = 0.78
            try await Task.detached(priority: .userInitiated) {
                try Self.extractWine(archive, to: root)
            }.value
            try? fileManager.removeItem(at: archive)
        }

        if !ModernEngine.dxvkFolder.appending(path: "x64/d3d11.dll").fileExists {
            detail = "DXVK 받는 중…"
            let archive = MiroPaths.downloads.appending(path: ModernEngine.dxvkURL.lastPathComponent)
            try await download(ModernEngine.dxvkURL, to: archive, sha256: ModernEngine.dxvkSHA256, span: 0.8...0.86)
            try await Task.detached(priority: .userInitiated) {
                try Self.extractDXVK(archive, to: ModernEngine.dxvkFolder)
            }.value
            try? fileManager.removeItem(at: archive)
        }

        let marker = EngineMarker(wineVersion: ModernEngine.wineVersion, wineSHA256: ModernEngine.wineSHA256,
                                  dxvkSHA256: ModernEngine.dxvkSHA256, installedAt: .now)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(marker).write(to: ModernEngine.marker, options: .atomic)
    }

    private func download(_ url: URL, to archive: URL, sha256: String, span: ClosedRange<Double>) async throws {
        _ = try await Downloader.download(url, to: archive) { fraction, received, total in
            Task { @MainActor in
                let manager = EngineManager.shared
                manager.progress = span.lowerBound + max(0, fraction) * (span.upperBound - span.lowerBound)
                if total > 0 {
                    manager.detail = "다운로드 중… \(received.byteString) / \(total.byteString)"
                }
            }
        }
        detail = "파일 확인 중…"
        let digest = try await Task.detached(priority: .userInitiated) { try Self.sha256(of: archive) }.value
        guard digest == sha256 else {
            try? FileManager.default.removeItem(at: archive)
            throw InstallError(message: "받은 파일이 손상되었거나 바뀌었어요 (\(url.lastPathComponent)). 다시 시도해 주세요.")
        }
    }

    nonisolated private static func reportsVersion(_ root: URL) -> Bool {
        // `wine --version` needs no prefix; a quick way to accept a copy that is already in place
        let process = Process()
        process.executableURL = root.appending(path: "bin/wine")
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return output.contains("wine-\(ModernEngine.wineVersion)")
    }

    nonisolated private static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// `Wine Staging.app/Contents/Resources/wine` → `Engines/wine-11.21`
    nonisolated private static func extractWine(_ archive: URL, to root: URL) throws {
        let fileManager = FileManager.default
        let staging = root.deletingLastPathComponent().appending(path: ".staging-\(UUID().uuidString.prefix(8))")
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        try Tar.untar(tarBall: archive, toURL: staging)

        guard let enumerator = fileManager.enumerator(at: staging, includingPropertiesForKeys: nil),
              let wineRoot = (enumerator.compactMap { $0 as? URL }.first { url in
                  url.lastPathComponent == "wine" && url.deletingLastPathComponent().lastPathComponent == "bin"
                      && url.deletingLastPathComponent().deletingLastPathComponent()
                          .appending(path: "lib/wine/x86_64-unix/ntdll.so").fileExists
              })?.deletingLastPathComponent().deletingLastPathComponent()
        else { throw InstallError(message: "받은 파일 안에서 Wine을 찾지 못했어요") }

        // Keep Miro's own files (DXVK, marker) if they are already there
        let keep = root.appending(path: "miro")
        let kept = staging.appending(path: "miro-kept")
        if keep.fileExists { try fileManager.moveItem(at: keep, to: kept) }
        if root.fileExists { try fileManager.removeItem(at: root) }
        try fileManager.moveItem(at: wineRoot, to: root)
        if kept.fileExists { try fileManager.moveItem(at: kept, to: keep) }
        try fileManager.createDirectory(at: keep, withIntermediateDirectories: true)
    }

    nonisolated private static func extractDXVK(_ archive: URL, to folder: URL) throws {
        let fileManager = FileManager.default
        let staging = folder.deletingLastPathComponent().appending(path: ".dxvk-staging")
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        try Tar.untar(tarBall: archive, toURL: staging)
        guard let x64 = fileManager.enumerator(at: staging, includingPropertiesForKeys: nil)?
            .compactMap({ $0 as? URL })
            .first(where: { $0.lastPathComponent == "x64" && $0.appending(path: "d3d11.dll").fileExists })
        else { throw InstallError(message: "받은 DXVK 파일이 올바르지 않아요") }
        let source = x64.deletingLastPathComponent()
        try? fileManager.removeItem(at: folder)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        for item in ["x64", "x32", "dxvk.conf"] where source.appending(path: item).fileExists {
            try fileManager.copyItem(at: source.appending(path: item), to: folder.appending(path: item))
        }
    }

    /// Puts DXMT's builtin DLLs and Miro's winemac.so into the modern engine. The files they replace (Wine's
    /// own d3d11/dxgi/d3d10core and winemac.so) are kept in `miro/original` first.
    nonisolated private static func applyDXMT(_ archive: URL, winemac: URL) throws {
        let fileManager = FileManager.default
        let root = ModernEngine.root
        let staging = root.appending(path: "miro/.dxmt-staging")
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        try Tar.untar(tarBall: archive, toURL: staging)
        guard let release = fileManager.enumerator(at: staging, includingPropertiesForKeys: nil)?
            .compactMap({ $0 as? URL })
            .first(where: { $0.lastPathComponent == "x86_64-unix" && $0.appending(path: "winemetal.so").fileExists })?
            .deletingLastPathComponent()
        else { throw InstallError(message: "받은 DXMT 파일이 올바르지 않아요") }

        let lib = root.appending(path: "lib/wine")
        func replace(_ relative: String, with source: URL) throws {
            let target = lib.appending(path: relative)
            let backup = ModernEngine.originals.appending(path: relative)
            if target.fileExists && !backup.fileExists {
                try fileManager.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: target, to: backup)
            }
            try? fileManager.removeItem(at: target)
            try fileManager.copyItem(at: source, to: target)
        }

        for arch in ["x86_64-windows", "i386-windows"] {
            for dll in ModernEngine.dxmtDLLs {
                let source = release.appending(path: "\(arch)/\(dll).dll")
                guard source.fileExists else { throw InstallError(message: "DXMT에 \(arch)/\(dll).dll이 없어요") }
                try replace("\(arch)/\(dll).dll", with: source)
            }
        }
        try replace("x86_64-unix/winemetal.so", with: release.appending(path: "x86_64-unix/winemetal.so"))
        try replace("x86_64-unix/winemac.so", with: winemac)
    }

    // MARK: - Prefix

    /// The modern prefix starts as an APFS clone of the classic one (fonts, Visual C++, .NET … carry over,
    /// no extra disk space), shares C:\Games through a symlink, and is then updated by Wine 11 once.
    private func prepareBottle() async throws {
        let engine = WineEngine.modern
        if !engine.hasPrefix {
            let classic = MiroPaths.bottle
            if classic.appending(path: "system.reg").fileExists {
                try await Self.clonePrefix(from: classic, to: MiroPaths.modernBottle)
            }
            let bottle = Bottle(bottleUrl: MiroPaths.modernBottle, isAvailable: true)
            var env = ProcessRunner.baseEnvironment
            env.merge(engine.environment(for: bottle)) { $1 }
            // Skip the wine-mono / wine-gecko installers: .NET and the browser engine come from the libraries
            env["WINEDLLOVERRIDES"] = "mscoree,mshtml="
            let arguments = classic.appending(path: "system.reg").fileExists ? ["wineboot", "-u"] : ["wineboot", "-i"]
            try await Self.runGuarded(engine: engine, arguments: arguments, environment: env, timeout: 240)
            guard engine.hasPrefix else {
                throw InstallError(message: "최신 엔진의 Windows 환경을 만들지 못했어요. 로그를 확인해 주세요.")
            }
            if !classic.appending(path: "system.reg").fileExists {
                _ = try? await engine.run(["winecfg", "-v", "win11"], bottle: bottle)
            }
        }
        try Self.installDXVK(into: MiroPaths.modernBottle)
    }

    nonisolated private static func clonePrefix(from source: URL, to target: URL) async throws {
        let fileManager = FileManager.default
        let staging = target.deletingLastPathComponent().appending(path: ".\(target.lastPathComponent)-staging")
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging.appending(path: "drive_c"), withIntermediateDirectories: true)

        var sources: [URL] = []
        for item in try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            switch item.lastPathComponent {
            case "drive_c", "dosdevices": continue
            default: sources.append(item)
            }
        }
        for item in try fileManager.contentsOfDirectory(
            at: source.appending(path: "drive_c"), includingPropertiesForKeys: nil
        ) where item.lastPathComponent != "Games" {
            sources.append(item)
        }
        // cp -c clones on APFS: instant and no extra disk space
        for item in sources {
            let destination = item.deletingLastPathComponent().lastPathComponent == "drive_c"
                ? staging.appending(path: "drive_c") : staging
            let (code, output) = try await ProcessRunner.run(
                executable: URL(fileURLWithPath: "/bin/cp"),
                arguments: ["-c", "-R", item.path(percentEncoded: false), destination.path(percentEncoded: false)],
                environment: ProcessRunner.baseEnvironment
            )
            guard code == 0 else { throw InstallError(message: "Windows 환경 복제 실패: \(output)") }
        }
        let gamesFolder = source.appending(path: "drive_c/Games")
        MiroPaths.ensure(gamesFolder)
        try fileManager.createSymbolicLink(at: staging.appending(path: "drive_c/Games"), withDestinationURL: gamesFolder)
        let dosdevices = staging.appending(path: "dosdevices")
        try fileManager.createDirectory(at: dosdevices, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(atPath: dosdevices.appending(path: "c:").path(percentEncoded: false),
                                           withDestinationPath: "../drive_c")
        try fileManager.createSymbolicLink(atPath: dosdevices.appending(path: "z:").path(percentEncoded: false),
                                           withDestinationPath: "/")
        try fileManager.moveItem(at: staging, to: target)
    }

    /// Copies DXVK's native DLLs into the prefix (Wine's prefix update puts its own builtins back)
    nonisolated static func installDXVK(into bottle: URL) throws {
        let fileManager = FileManager.default
        let windows = bottle.appending(path: "drive_c/windows")
        for (folder, arch) in [("system32", "x64"), ("syswow64", "x32")] {
            let directory = windows.appending(path: folder)
            guard directory.fileExists else { continue }
            for dll in ModernEngine.dxvkDLLs {
                let source = ModernEngine.dxvkFolder.appending(path: "\(arch)/\(dll).dll")
                let target = directory.appending(path: "\(dll).dll")
                guard source.fileExists else { continue }
                let sourceSize = (try? fileManager.attributesOfItem(atPath: source.path(percentEncoded: false))[.size]) as? Int
                let targetSize = (try? fileManager.attributesOfItem(atPath: target.path(percentEncoded: false))[.size]) as? Int
                if sourceSize != nil && sourceSize == targetSize { continue }
                try? fileManager.removeItem(at: target)
                try fileManager.copyItem(at: source, to: target)
            }
        }
    }

    /// Runs a Wine command with a deadline and a process-storm brake, then stops the prefix's wineserver.
    nonisolated private static func runGuarded(
        engine: WineEngine, arguments: [String], environment: [String: String], timeout: TimeInterval
    ) async throws {
        let logURL = MiroPaths.logs.appending(path: "engine-\(engine.kind.rawValue)-\(arguments.joined(separator: "-"))-\(Int(Date.now.timeIntervalSince1970)).log")
        let (process, stream) = try ProcessRunner.start(
            executable: engine.wineBinary, arguments: arguments, environment: environment,
            directory: MiroPaths.support, logURL: logURL
        )
        let watchdog = Task.detached {
            let start = Date.now
            while process.isRunning {
                try? await Task.sleep(for: .seconds(2))
                if Date.now.timeIntervalSince(start) > timeout || engine.processCount() > ProcessGuard.stormLimit {
                    engine.killAll()
                    process.terminate()
                    return
                }
            }
        }
        for await _ in stream {}
        watchdog.cancel()
        // wineboot leaves services running; stop them so the prefix is consistent before games use it
        let env = ProcessRunner.baseEnvironment.merging(["WINEPREFIX": engine.bottleURL.path(percentEncoded: false)]) { $1 }
        _ = try? await ProcessRunner.run(executable: engine.wineserverBinary, arguments: ["-k"], environment: env)
    }
}

/// Stops Wine when it starts processes without end (e.g. a crashing explorer.exe being restarted forever),
/// before the Mac runs out of process slots.
enum ProcessGuard {
    /// A game plus Wine's services is normally 10–20 processes
    static let stormLimit = 120
}
