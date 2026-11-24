//
//  WineEngine.swift
//  Miro
//
//  The Wine engines Miro can run a game with. They live side by side, each with its own Windows prefix,
//  so a newer engine never changes the C: drive that the proven engine uses.
//

import Darwin
import Foundation
import WhiskyKit

/// Which Wine engine runs a game.
enum WineEngineKind: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Wine 7.7 + D3DMetal (Apple Game Porting Toolkit) — Miro's original runtime
    case classic
    /// Wine 11 (WineHQ Staging) + DXVK — newer Windows APIs, e.g. what Unity 6.3 calls at startup
    case modern

    var id: String { rawValue }
}

/// The engine choice stored per game in 게임 설정.
enum WinePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Classic first; Miro switches to the modern engine by itself when the classic one is missing a function
    case auto
    case classic
    case modern

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "자동 (추천)"
        case .classic: return WineEngine.classic.title
        case .modern: return WineEngine.modern.title
        }
    }
}

/// One installed (or installable) Wine engine and its prefix.
struct WineEngine: Sendable {
    let kind: WineEngineKind
    /// Folder that holds bin/, lib/ and share/
    let root: URL
    /// `wine64` (classic, old WoW64) or `wine` (modern, new WoW64)
    let wineName: String
    /// The Windows prefix (virtual C: drive) this engine uses
    let bottleURL: URL

    static let classic = WineEngine(
        kind: .classic, root: WhiskyWineInstaller.wineFolder, wineName: "wine64", bottleURL: MiroPaths.bottle
    )
    static let modern = WineEngine(
        kind: .modern, root: ModernEngine.root, wineName: "wine", bottleURL: MiroPaths.modernBottle
    )

    static func of(_ kind: WineEngineKind) -> WineEngine {
        kind == .classic ? .classic : .modern
    }

    var wineBinary: URL { root.appending(path: "bin").appending(path: wineName) }
    var wineserverBinary: URL { root.appending(path: "bin").appending(path: "wineserver") }
    var binFolder: URL { root.appending(path: "bin") }
    var driveC: URL { bottleURL.appending(path: "drive_c") }
    var hasPrefix: Bool { bottleURL.appending(path: "system.reg").fileExists }

    var title: String {
        switch kind {
        case .classic: return "클래식 · Wine 7.7 + D3DMetal"
        case .modern: return "최신 · Wine \(ModernEngine.wineVersion) + DXVK"
        }
    }

    var shortName: String { kind == .classic ? "클래식" : "최신" }

    var summary: String {
        switch kind {
        case .classic:
            return "Apple Game Porting Toolkit. DirectX 11/12를 Metal로 바로 옮겨서 가장 빠르고, 대부분의 게임은 이걸로 충분해요."
        case .modern:
            return "WineHQ \(ModernEngine.wineVersion) Staging + DXVK(DirectX 9~11 → Vulkan → Metal). "
                + "최신 Windows 기능이 필요한 게임(예: Unity 6.3)이 실행돼요. DirectX 12 전용 게임은 클래식을 쓰세요."
        }
    }

    /// Environment for every Wine process of this engine (prefix, debug level, the bottle's toggles)
    func environment(for bottle: Bottle) -> [String: String] {
        var env = Wine.environment(for: bottle)
        env["WINEPREFIX"] = bottleURL.path(percentEncoded: false)
        guard kind == .modern else { return env }
        // DXVK's d3d11/dxgi sit in system32 as native DLLs; Wine's own (wined3d) stays as the fallback
        env["WINEDLLOVERRIDES"] = Self.mergeOverrides(env["WINEDLLOVERRIDES"], "d3d11,dxgi,d3d10core=n,b")
        env["DXVK_ASYNC"] = "1"
        env["DXVK_CONFIG_FILE"] = ModernEngine.dxvkFolder.appending(path: "dxvk.conf").path(percentEncoded: false)
        env["DXVK_STATE_CACHE_PATH"] = MiroPaths.shaderCache.path(percentEncoded: false)
        // D3DMetal-only switches mean nothing to this engine
        for key in ["D3DM_SUPPORT_DXR", "WINEMSYNC"] { env.removeValue(forKey: key) }
        return env
    }

    /// Extra arguments a game engine needs on this Wine engine
    func launchArguments(for gameEngine: GameEngine) -> [String] {
        // Unity probes D3D12 first; vkd3d on MoltenVK only offers feature level 11.0, so go straight to D3D11/DXVK
        kind == .modern && gameEngine == .unity ? ["-force-d3d11"] : []
    }

    /// Runs `wine <args>` in this engine's prefix and waits for it
    @discardableResult
    func run(_ arguments: [String], bottle: Bottle) async throws -> (Int32, String) {
        var env = ProcessRunner.baseEnvironment
        env.merge(environment(for: bottle)) { $1 }
        return try await ProcessRunner.run(executable: wineBinary, arguments: arguments, environment: env)
    }

    /// `wineserver -k`: ends every Windows process of this engine's prefix
    func killAll() {
        let env = ProcessRunner.baseEnvironment.merging(
            ["WINEPREFIX": bottleURL.path(percentEncoded: false)]
        ) { $1 }
        _ = try? ProcessRunner.start(executable: wineserverBinary, arguments: ["-k"], environment: env)
    }

    /// Sets the Mac driver's Retina mode with this engine's own `reg.exe` (never the other engine's)
    func setRetina(_ enabled: Bool, bottle: Bottle) async {
        _ = try? await run(
            ["reg", "add", #"HKCU\Software\Wine\Mac Driver"#, "/v", "RetinaMode", "/t", "REG_SZ",
             "/d", enabled ? "y" : "n", "/f"],
            bottle: bottle
        )
    }

    /// Number of running processes whose executable lives inside this engine (wine loaders, wineserver …)
    func processCount() -> Int {
        Self.countProcesses(under: root)
    }

    nonisolated static func countProcesses(under root: URL) -> Int {
        var prefix = root.standardizedFileURL.path(percentEncoded: false)
        if !prefix.hasSuffix("/") { prefix += "/" }
        var pids = [pid_t](repeating: 0, count: 16_384)
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return 0 }
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        var count = 0
        for pid in pids.prefix(Int(bytes) / MemoryLayout<pid_t>.size) where pid > 0 {
            let length = Int(proc_pidpath(pid, &buffer, UInt32(buffer.count)))
            guard length > 0 else { continue }
            let path = String(decoding: buffer.prefix(length).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if path.hasPrefix(prefix) { count += 1 }
        }
        return count
    }

    private static func mergeOverrides(_ existing: String?, _ added: String) -> String {
        guard let existing, !existing.isEmpty else { return added }
        return existing + ";" + added
    }
}
