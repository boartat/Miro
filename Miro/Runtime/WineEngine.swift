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
    /// Wine 7.7 + D3DMetal (Apple Game Porting Toolkit), Miro's original runtime
    case classic
    /// Wine 11 (CrossOver 26.3 tree): newer Windows APIs, and every graphics layer
    case modern
    /// miroe (experimental): ARM64-native Wine + FEX with Mullion for Direct3D 10/11/12, 64-bit programs only
    case miroe

    var id: String { rawValue }
}

/// The engine choice stored per game in 게임 설정.
enum WinePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Miro picks the engine and tries the next one when a launch fails
    case auto
    case classic
    case modern
    /// Only when chosen: 자동 never picks the experimental engine
    case miroe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "자동 (추천)"
        case .classic: return WineEngine.classic.title
        case .modern: return WineEngine.modern.title
        case .miroe: return WineEngine.miroe.title
        }
    }
}

/// How the modern engine turns Direct3D into Metal.
enum GraphicsBackend: String, Codable, CaseIterable, Identifiable, Sendable {
    /// DXMT: Direct3D 10/11 straight to Metal
    case dxmt
    /// Apple's D3DMetal: Direct3D 11/12 to Metal (needs the Game Porting Toolkit licence accepted)
    case d3dmetal
    /// DXVK: Direct3D 9–11 → Vulkan → MoltenVK → Metal
    case dxvk
    /// Wine's own Direct3D (wined3d, and vkd3d for Direct3D 12)
    case wined3d
    /// Mullion (DXMT fork, Direct3D 10/11/12 straight to Metal) with miroe's patches — the miroe engine only
    case mullion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dxmt: return "DXMT"
        case .d3dmetal: return "D3DMetal"
        case .dxvk: return "DXVK"
        case .wined3d: return "Wine 기본"
        case .mullion: return "Mullion"
        }
    }
}

/// The graphics choice stored per game in 게임 설정 (used on the modern engine).
enum GraphicsPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Miro's order for the game's Direct3D version, moving on when one fails
    case auto
    case dxmt
    case d3dmetal
    case dxvk
    case wined3d

    var id: String { rawValue }

    var backend: GraphicsBackend? {
        switch self {
        case .auto: return nil
        case .dxmt: return .dxmt
        case .d3dmetal: return .d3dmetal
        case .dxvk: return .dxvk
        case .wined3d: return .wined3d
        }
    }

    var title: String {
        switch self {
        case .auto: return "자동 (추천)"
        case .dxmt: return "DXMT · DirectX 10/11"
        case .d3dmetal: return "D3DMetal · DirectX 11/12"
        case .dxvk: return "DXVK · DirectX 9~11"
        case .wined3d: return "Wine 기본 · DirectX 9, 12"
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
        kind: .modern, root: ModernEngine.wineRoot, wineName: "wine", bottleURL: MiroPaths.modernBottle
    )
    static let miroe = WineEngine(
        kind: .miroe, root: MiroeEngine.root, wineName: "wine", bottleURL: MiroPaths.miroeBottle
    )

    static func of(_ kind: WineEngineKind) -> WineEngine {
        switch kind {
        case .classic: return .classic
        case .modern: return .modern
        case .miroe: return .miroe
        }
    }

    var wineBinary: URL { root.appending(path: "bin").appending(path: wineName) }
    var wineserverBinary: URL { root.appending(path: "bin").appending(path: "wineserver") }
    var binFolder: URL { root.appending(path: "bin") }
    var driveC: URL { bottleURL.appending(path: "drive_c") }
    var hasPrefix: Bool { bottleURL.appending(path: "system.reg").fileExists }

    var title: String {
        switch kind {
        case .classic: return "클래식 · Wine 7.7 + D3DMetal"
        case .modern: return "최신 · Wine \(ModernEngine.wineVersion)"
        case .miroe: return "miroe · ARM64 Wine + FEX"
        }
    }

    /// Title for a game that runs on this engine with `graphics`
    func title(graphics: GraphicsBackend?) -> String {
        guard kind == .modern, let graphics else { return title }
        return "\(title) + \(graphics.title)"
    }

    var shortName: String {
        switch kind {
        case .classic: return "클래식"
        case .modern: return "최신"
        case .miroe: return "miroe"
        }
    }

    var summary: String {
        switch kind {
        case .classic:
            return "Apple Game Porting Toolkit. 예전 Wine이지만 오래 검증됐어요. 최신 엔진에서 안 되는 게임의 마지막 예비 엔진이에요."
        case .modern:
            return "CrossOver 26.3 오픈소스 기반 Wine 11. DXMT·D3DMetal·DXVK·Wine 기본 그래픽을 게임마다 바꿔 끼우고, "
                + "안 되면 다음 방식으로 알아서 넘어가요. 최신 Windows 기능이 필요한 게임(예: Unity 6.3)도 실행돼요."
        case .miroe:
            return "Rosetta 없이 ARM64로 돌고(게임의 Intel 코드는 FEX가 번역), DirectX 10/11/12는 Mullion, "
                + "DirectX 1~9는 WineD3D로 자동으로 그려요(D3DMetal 없음). 32비트 게임도 돼요(DirectX 12는 64비트만). "
                + "Steam도 이 엔진에서 돌아요."
        }
    }

    /// Environment for every Wine process of this engine (prefix, debug level, the bottle's toggles).
    /// `graphics` picks how the modern engine draws Direct3D; the classic engine ignores it.
    func environment(for bottle: Bottle, graphics: GraphicsBackend? = nil) -> [String: String] {
        var env = Wine.environment(for: bottle)
        env["WINEPREFIX"] = bottleURL.path(percentEncoded: false)
        if kind == .miroe { return Self.miroeEnvironment(env) }
        guard kind == .modern else { return env }

        // Host libraries (FreeType, GStreamer, MoltenVK …) live in the runtime frameworks folder
        let frameworks = ModernEngine.frameworks.path(percentEncoded: false)
        var libraryPath = "\(frameworks):\(frameworks)/GStreamer.framework/Versions/1.0/lib"
        var frameworkPath = frameworks
        env["GST_PLUGIN_PATH"] = "\(frameworks)/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0"
        env["CX_FWD_COMPAT_GL_CTX"] = "1"
        env["MVK_CONFIG_LOG_LEVEL"] = "2"
        env["DXMT_ALLOW_CROSS_PROCESS_SWAPCHAIN"] = "1"
        var overrides = "winemenubuilder.exe=d"

        switch graphics ?? .wined3d {
        case .dxmt:
            env["WINEDLLPATH_PREPEND"] = ModernEngine.dxmtOverlay.path(percentEncoded: false)
            env["DXMT_SHADER_CACHE_PATH"] = MiroPaths.shaderCache.appending(path: "dxmt").path(percentEncoded: false)
        case .d3dmetal:
            // 32-bit Direct3D 10/11 falls through to DXMT: D3DMetal is 64-bit only
            let external = ModernEngine.d3dmetalExternal.path(percentEncoded: false)
            env["WINEDLLPATH_PREPEND"] = ModernEngine.d3dmetalOverlay.path(percentEncoded: false) + ":"
                + ModernEngine.dxmtOverlay.path(percentEncoded: false)
            env["CX_D3DMETALPATH"] = external
            libraryPath += ":\(external)"
            frameworkPath += ":\(external)"
            env["DXMT_SHADER_CACHE_PATH"] = MiroPaths.shaderCache.appending(path: "dxmt").path(percentEncoded: false)
        case .dxvk:
            // DXVK-macOS (with its dxgi) sits in the prefix's system32 as native DLLs
            overrides += ";dxgi,d3d10core,d3d11=n,b"
            env["DXVK_ASYNC"] = "1"
            env["DXVK_CONFIG_FILE"] = ModernEngine.dxvkFolder.appending(path: "dxvk.conf").path(percentEncoded: false)
            env["DXVK_STATE_CACHE_PATH"] = MiroPaths.shaderCache.path(percentEncoded: false)
        case .wined3d, .mullion:  // Mullion runs on the miroe engine only
            break
        }
        env["DYLD_FALLBACK_LIBRARY_PATH"] = libraryPath
        env["DYLD_FALLBACK_FRAMEWORK_PATH"] = frameworkPath
        env["WINEDLLOVERRIDES"] = Self.mergeOverrides(env["WINEDLLOVERRIDES"], overrides)
        if graphics != .d3dmetal { env.removeValue(forKey: "D3DM_SUPPORT_DXR") }
        return env
    }

    /// The miroe engine: FreeType bundled in the engine, FEX's code cache on disk, Mullion for every Direct3D
    private static func miroeEnvironment(_ base: [String: String]) -> [String: String] {
        var env = base
        env["DYLD_FALLBACK_LIBRARY_PATH"] = MiroeEngine.libraries.path(percentEncoded: false)
        env.removeValue(forKey: "DYLD_FALLBACK_FRAMEWORK_PATH")
        env["FEX_DISKCACHE"] = "1"
        env["FEX_DISKCACHEMAXFILESIZE"] = "4294967296"
        env["MTLD3D_NO_CRASH_HANDLER"] = "1"
        env.removeValue(forKey: "D3DM_SUPPORT_DXR")
        // Set, not merged: a bottle's DXVK toggle would make dxgi/d3d11 native and hide Mullion's builtins
        env["WINEDLLOVERRIDES"] = "d3d11,dxgi,d3d10core,d3d12,d3d12core,winemetal=b;mshtml=;winemenubuilder.exe=d"
        env.removeValue(forKey: "DXVK_HUD")
        return env
    }

    /// Extra arguments a game engine needs on this Wine engine
    func launchArguments(for gameEngine: GameEngine, graphics: GraphicsBackend?) -> [String] {
        // Unity probes Direct3D 12 first; only D3DMetal and Wine's vkd3d serve it, so the others get D3D11
        guard kind == .modern, gameEngine == .unity else { return [] }
        return graphics == .dxmt || graphics == .dxvk ? ["-force-d3d11"] : []
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

    /// Mac Driver key options (prefix-wide): ⌘ as Ctrl, and Option always as Alt (Windows programs and games
    /// expect Alt; macOS's Option characters are not useful there)
    func setKeyboard(commandAsCtrl: Bool, bottle: Bottle) async {
        let key = #"HKCU\Software\Wine\Mac Driver"#
        let values = [("LeftCommandIsCtrl", commandAsCtrl), ("RightCommandIsCtrl", commandAsCtrl),
                      ("LeftOptionIsAlt", true), ("RightOptionIsAlt", true)]
        for (name, on) in values {
            _ = try? await run(["reg", "add", key, "/v", name, "/t", "REG_SZ", "/d", on ? "y" : "n", "/f"], bottle: bottle)
        }
    }

    /// Windows DPI of the prefix (prefix-wide, read when a program starts): 96 = 100 %, 192 = 200 %
    func setDisplayDPI(_ dpi: Int, bottle: Bottle) async {
        for key in [#"HKCU\Control Panel\Desktop"#, #"HKLM\System\CurrentControlSet\Hardware Profiles\Current\Software\Fonts"#] {
            _ = try? await run(["reg", "add", key, "/v", "LogPixels", "/t", "REG_DWORD", "/d", String(dpi), "/f"], bottle: bottle)
        }
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
