//
//  EngineManager.swift
//  Miro
//
//  Installs the modern Wine engine next to the classic one, keeps its prefix ready and knows which
//  graphics layers it can offer.
//

import CryptoKit
import Foundation
import WhiskyKit

/// One downloadable part of the modern engine, pinned to a SHA-256.
struct EngineComponent: Sendable {
    let name: String
    let url: URL
    let sha256: String
    let size: Int64
    /// Folder or file inside the archive to take
    let subpath: String
    /// Where it goes, relative to the engine root
    let destination: String
}

/// The modern engine: Highball's open build of CodeWeavers' CrossOver 26.3 Wine tree (Wine 11.0, LGPL), the
/// Sikarugir runtime frameworks, Highball's DXMT branch and MoltenVK, and DXVK-macOS for system32.
/// Every part comes from its own publisher and is checked against its SHA-256 before use.
enum ModernEngine {
    static let id = "cx26.3-r35"
    static let wineVersion = "11 (CrossOver 26.3)"
    static let downloadSize = "약 450MB"

    /// Keep this path short: Wine's font loader copies `<root>/share/wine/fonts` into a MAX_PATH buffer and
    /// a long root crashes every process at startup (then explorer.exe is restarted in a loop).
    static let root = MiroPaths.engines.appending(path: "cx26.3")
    static let wineRoot = root.appending(path: "engine")
    static let frameworks = root.appending(path: "frameworks")
    static let dxmtOverlay = root.appending(path: "renderers/dxmt/wine")
    static let d3dmetalRenderer = frameworks.appending(path: "renderer/d3dmetal")
    static let d3dmetalOverlay = d3dmetalRenderer.appending(path: "wine")
    static let d3dmetalExternal = d3dmetalRenderer.appending(path: "external")
    static let d3dmetalLicenseFile = d3dmetalRenderer.appending(path: "License.rtf")
    static let dxvkFolder = root.appending(path: "miro/dxvk")
    static let marker = root.appending(path: "miro/engine.json")
    /// Where Miro 1.1's modern engine (WineHQ 11.21) was installed
    static let previousRoot = MiroPaths.engines.appending(path: "wine-11.21")

    private static let highball = "https://github.com/gauthierpiarrette/highball-engine/releases/download"
    static let components: [EngineComponent] = [
        EngineComponent(
            name: "Wine", url: URL(string: "\(highball)/engine-wine-11.0-20261114T185735Z-fiber-mirror-switch/engine-wine-11.0-20261114T185735Z-fiber-mirror-switch.tar.gz")!,
            sha256: "ee1609f037b77d9a1896f3444c7d939ce91f39c81ffa729fdf4d6bdddb34af89", size: 335_457_194,
            subpath: "engine", destination: "engine"),
        EngineComponent(
            name: "런타임", url: URL(string: "https://github.com/Sikarugir-App/Template/releases/download/v1.0/Template-1.0.11.tar.xz")!,
            sha256: "9fa15479e7ff6abd99c1d07be285fb95f41fc6991586502427152b1f7d6ccb8a", size: 84_533_420,
            subpath: "Template-1.0.11.app/Contents/Frameworks", destination: "frameworks"),
        EngineComponent(
            name: "MoltenVK", url: URL(string: "https://github.com/gauthierpiarrette/highball/releases/download/engine-components/moltenvk-1.4.2-shadow-import-1-linear-fallback-1-shadow-readback-1-device-memory-cap-1-cache-drawid-present-1-lenient-interfaces-1-x86_64.tar.gz")!,
            sha256: "662d7c064ad51bbb20b96b3f13415462cfa89a2deb8a57cf651d068bbfbcdf69", size: 1_736_604,
            subpath: "libMoltenVK.dylib", destination: "frameworks/libMoltenVK.dylib"),
        EngineComponent(
            name: "DXMT", url: URL(string: "\(highball)/dxmt-highball-20260930T161516Z-a444716/dxmt-highball-20260930T161516Z-a444716.tar.gz")!,
            sha256: "96feaf5d98d3c6cdc3edea9503e2891d435df8d5bfdf7d3f6998a56ec62bbd58", size: 18_923_969,
            subpath: "highball", destination: "renderers/dxmt/wine"),
        EngineComponent(
            name: "오디오", url: URL(string: "\(highball)/audiobuf-20261103/audiobuf-20261103.tar.xz")!,
            sha256: "617b8feb3651227c9c27419e4dc58835e8ca471ef7ce3b13b0ddaea7c067454f", size: 8_124,
            subpath: "libhbaudiobuf.dylib", destination: "frameworks/libhbaudiobuf.dylib"),
        EngineComponent(
            name: "NVAPI", url: URL(string: "https://github.com/gauthierpiarrette/highball/releases/download/engine-components/nvapi-stub-2-i386.tar.gz")!,
            sha256: "cbda8aeee87e84ecf98c06759d2123b073dc99a7aa1c639480fade33383d18a2", size: 1_759,
            subpath: "nvapi.dll", destination: "engine/lib/wine/i386-windows/nvapi.dll"),
        // DXVK-macOS with its own dxgi, copied into the prefix's system32 (the runtime's DXVK has no dxgi)
        EngineComponent(
            name: "DXVK", url: URL(string: "https://github.com/Gcenx/DXVK-macOS/releases/download/v1.10.3-20230507/dxvk-macOS-async-v1.10.3-20230507.tar.gz")!,
            sha256: "f67d99d0a8eeedd7d406b283a3df9f939b5965acb00efcb33d0c6235c195a516", size: 7_077_450,
            subpath: "dxvk-macOS-async-v1.10.3-20230507", destination: "miro/dxvk")
    ]

    /// DLLs DXVK provides, per prefix folder
    static let dxvkDLLs = ["d3d11", "dxgi", "d3d10core"]

    static var isInstalled: Bool {
        wineRoot.appending(path: "bin/wine").fileExists && marker.fileExists
            && dxmtOverlay.appending(path: "x86_64-windows/d3d11.dll").fileExists
            && dxvkFolder.appending(path: "x64/d3d11.dll").fileExists
    }
}

struct EngineMarker: Codable {
    var id: String
    var components: [String: String]
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
    /// The Apple Game Porting Toolkit licence was accepted, so D3DMetal may be used on the modern engine
    @Published private(set) var d3dmetalAccepted = UserDefaults.standard.bool(forKey: EngineManager.licenseKey)

    /// Bumped with the licence text Miro shows
    nonisolated static let licenseKey = "acceptedAppleGPTKLicense-2023-08-17"

    private init() {
        refresh()
    }

    func refresh() {
        guard modernState != .installing else { return }
        let ready = ModernEngine.isInstalled && WineEngine.modern.hasPrefix
        modernState = ready ? .installed : .notInstalled
        if ready, modernBottle == nil {
            modernBottle = Bottle(bottleUrl: MiroPaths.modernBottle, isAvailable: true)
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

    /// Whether the modern engine can draw with `backend` right now
    func offers(_ backend: GraphicsBackend) -> Bool {
        guard isReady(.modern) else { return false }
        switch backend {
        case .dxmt: return ModernEngine.dxmtOverlay.fileExists
        case .d3dmetal: return d3dmetalAccepted && ModernEngine.d3dmetalOverlay.fileExists
        case .dxvk: return ModernEngine.dxvkFolder.appending(path: "x64/d3d11.dll").fileExists
        case .wined3d: return true
        }
    }

    func acceptD3DMetalLicense() {
        UserDefaults.standard.set(true, forKey: Self.licenseKey)
        d3dmetalAccepted = true
    }

    /// The engine `game` runs with first (see LaunchPlanner for the whole order)
    func engine(for game: Game) -> WineEngineKind {
        LaunchPlanner.plans(for: game).first?.engine ?? .classic
    }

    // MARK: - Install

    /// Downloads (or keeps) every engine part, then prepares the modern prefix.
    func installModern() async {
        guard modernState != .installing else { return }
        modernState = .installing
        progress = 0
        do {
            try await installEngineFiles()
            detail = "Windows 11 환경 준비 중… (처음 한 번은 1~2분 걸려요)"
            progress = 0.92
            try await prepareBottle()
            progress = 1
            detail = "설치 완료"
            modernState = .installed
            modernBottle = Bottle(bottleUrl: MiroPaths.modernBottle, isAvailable: true)
            retirePreviousEngine()
        } catch {
            modernState = .failed(error.localizedDescription)
            detail = error.localizedDescription
        }
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

    /// Miro 1.1's engine files are no longer used once the new engine works (its prefix stays: it may hold saves)
    private func retirePreviousEngine() {
        guard ModernEngine.previousRoot.fileExists else { return }
        try? FileManager.default.trashItem(at: ModernEngine.previousRoot, resultingItemURL: nil)
    }

    private func installEngineFiles() async throws {
        let fileManager = FileManager.default
        let root = ModernEngine.root
        try fileManager.createDirectory(at: root.appending(path: "miro"), withIntermediateDirectories: true)
        let total = Double(ModernEngine.components.reduce(0) { $0 + $1.size })
        var done = 0.0
        var installed: [String: String] = [:]
        let previous = Self.readMarker()

        for component in ModernEngine.components {
            let start = 0.9 * done / total
            done += Double(component.size)
            let end = 0.9 * done / total
            let target = root.appending(path: component.destination)
            // Keep a part that is already in place from the same archive
            if previous?.components[component.name] == component.sha256, target.fileExists {
                installed[component.name] = component.sha256
                continue
            }
            detail = "\(component.name) 받는 중…"
            let archive = MiroPaths.downloads.appending(path: "\(component.sha256.prefix(12))-\(component.url.lastPathComponent)")
            try await download(component.url, to: archive, sha256: component.sha256, span: start...end)
            detail = "\(component.name) 푸는 중…"
            try await Task.detached(priority: .userInitiated) {
                defer { try? FileManager.default.removeItem(at: archive) }
                try Self.extract(archive, component: component, into: root)
            }.value
            installed[component.name] = component.sha256
        }

        try Self.linkRuntimeLibraries(root: root)
        let marker = EngineMarker(id: ModernEngine.id, components: installed, installedAt: .now)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(marker).write(to: ModernEngine.marker, options: .atomic)
    }

    nonisolated private static func readMarker() -> EngineMarker? {
        guard let data = try? Data(contentsOf: ModernEngine.marker) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(EngineMarker.self, from: data)
    }

    private func download(_ url: URL, to archive: URL, sha256: String, span: ClosedRange<Double>) async throws {
        MiroPaths.ensure(MiroPaths.downloads)
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

    nonisolated private static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Unpacks one component and moves its `subpath` to its destination under the engine root.
    nonisolated private static func extract(_ archive: URL, component: EngineComponent, into root: URL) throws {
        let fileManager = FileManager.default
        let staging = root.appending(path: "miro/.staging-\(UUID().uuidString.prefix(8))")
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        try Tar.untar(tarBall: archive, toURL: staging)

        var source = staging.appending(path: component.subpath)
        if !source.fileExists {
            // Some archives wrap everything in one more folder
            guard let found = fileManager.enumerator(at: staging, includingPropertiesForKeys: nil)?
                .compactMap({ $0 as? URL })
                .first(where: { $0.path(percentEncoded: false).hasSuffix("/" + component.subpath) })
            else { throw InstallError(message: "받은 \(component.name) 파일에서 \(component.subpath)를 찾지 못했어요") }
            source = found
        }
        let target = root.appending(path: component.destination)
        try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if target.fileExists { try fileManager.removeItem(at: target) }
        try fileManager.moveItem(at: source, to: target)
    }

    /// The engine's Unix libraries find the runtime's dylibs beside them (as the CrossOver layout expects),
    /// also when a tool such as winetricks starts Wine without Miro's library path.
    nonisolated private static func linkRuntimeLibraries(root: URL) throws {
        let fileManager = FileManager.default
        let lib = root.appending(path: "engine/lib")
        for sub in ["frameworks", "frameworks/GStreamer.framework/Versions/1.0/lib"] {
            let folder = root.appending(path: sub)
            guard let entries = try? fileManager.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) else { continue }
            for name in entries where name.hasSuffix(".dylib") {
                let link = lib.appending(path: name)
                if (try? fileManager.destinationOfSymbolicLink(atPath: link.path(percentEncoded: false))) != nil
                    || link.fileExists { continue }
                try fileManager.createSymbolicLink(atPath: link.path(percentEncoded: false), withDestinationPath: "../../\(sub)/\(name)")
            }
        }
        let gstreamer = lib.appending(path: "GStreamer.framework")
        if !gstreamer.fileExists {
            try? fileManager.createSymbolicLink(atPath: gstreamer.path(percentEncoded: false),
                                                withDestinationPath: "../../frameworks/GStreamer.framework")
        }
    }

    // MARK: - Prefix

    /// The modern prefix starts as an APFS clone (no extra disk space) of Miro 1.1's modern prefix when there is
    /// one, so saves carry over, or else of the classic prefix (fonts, Visual C++, .NET … come along). It shares
    /// C:\Games through a symlink and is then updated by the new Wine once, without showing any window.
    private func prepareBottle() async throws {
        let engine = WineEngine.modern
        if !engine.hasPrefix {
            let source = MiroPaths.previousModernBottle.appending(path: "system.reg").fileExists
                ? MiroPaths.previousModernBottle : MiroPaths.bottle
            if source.appending(path: "system.reg").fileExists {
                try await Self.clonePrefix(from: source, to: MiroPaths.modernBottle)
            }
            let bottle = Bottle(bottleUrl: MiroPaths.modernBottle, isAvailable: true)
            var env = ProcessRunner.baseEnvironment
            env.merge(engine.environment(for: bottle)) { $1 }
            // No installers (Wine Mono / Gecko come with the engine) and no display: nothing appears on screen
            env["WINEDLLOVERRIDES"] = "mscoree,mshtml=;winemac.drv=d;winemenubuilder.exe=d"
            let update = source.appending(path: "system.reg").fileExists
            try await Self.runGuarded(engine: engine, arguments: ["wineboot", update ? "-u" : "-i"],
                                      environment: env, timeout: 240)
            guard engine.hasPrefix else {
                throw InstallError(message: "최신 엔진의 Windows 환경을 만들지 못했어요. 로그를 확인해 주세요.")
            }
            if !update {
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
                arguments: ["-c", "-R", item.commandPath, destination.commandPath],
                environment: ProcessRunner.baseEnvironment
            )
            guard code == 0 else { throw InstallError(message: "Windows 환경 복제 실패: \(output)") }
        }
        let gamesFolder = MiroPaths.gamesFolder
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
