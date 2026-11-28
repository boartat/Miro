//
//  LaunchPlanner.swift
//  Miro
//
//  Decides, per game, which engine and graphics layer to try and in what order. The launcher starts the
//  first plan and moves to the next one by itself when a run fails, so the player only sees the game start.
//
//  Since 2026-11-28 every game runs on the miroe engine (ARM64 Wine + FEX) with automatic graphics: Mullion for
//  Direct3D 10/11/12, WineD3D for Direct3D 1-9. The order below (order(for:)) is kept for the earlier engines'
//  history; LaunchPlanner no longer offers them.
//

import Foundation

/// One way to run a game.
struct LaunchPlan: Hashable, Sendable {
    let engine: WineEngineKind
    /// Graphics layer on the modern engine; nil on the classic engine
    let graphics: GraphicsBackend?

    static let classic = LaunchPlan(engine: .classic, graphics: nil)
    static let miroe = LaunchPlan(engine: .miroe, graphics: .mullion)
    static func modern(_ graphics: GraphicsBackend) -> LaunchPlan { LaunchPlan(engine: .modern, graphics: graphics) }

    var title: String { WineEngine.of(engine).title(graphics: graphics) }
}

@MainActor
enum LaunchPlanner {
    /// Every game runs on miroe. Its graphics are picked by the engine itself for the Direct3D version the game
    /// uses (Mullion for 10-12, WineD3D for 1-9), so there is one plan and nothing to fall back to.
    /// The earlier engines (classic, modern) stay installed for their prefixes' data but are not offered.
    static func plans(for game: Game) -> [LaunchPlan] {
        EngineManager.shared.isReady(.miroe) ? [.miroe] : []
    }

    /// Reading every DLL next to a game takes a moment, so the answer is kept per executable
    private static var apiCache: [String: GraphicsAPI] = [:]

    static func api(of game: Game) -> GraphicsAPI {
        let key = game.executablePath
        if let cached = apiCache[key] { return cached }
        let api = DirectXDetector.detect(game)
        apiCache[key] = api
        return api
    }

    /// Most efficient first, for the API the game draws with
    static func order(for api: GraphicsAPI) -> [GraphicsBackend] {
        switch api {
        case .direct3D12: return [.d3dmetal, .wined3d]
        case .direct3D11: return [.dxmt, .d3dmetal, .dxvk, .wined3d]
        case .direct3D9: return [.wined3d, .dxvk]
        case .openGL: return [.wined3d]
        case .unknown: return [.dxmt, .d3dmetal, .dxvk, .wined3d]
        }
    }
}
