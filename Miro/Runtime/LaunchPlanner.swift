//
//  LaunchPlanner.swift
//  Miro
//
//  Decides, per game, which engine and graphics layer to try and in what order. The launcher starts the
//  first plan and moves to the next one by itself when a run fails, so the player only sees the game start.
//
//  Order for 자동:
//    1. what worked for this game last time
//    2. the graphics layer the compatibility database verified for it
//    3. the most efficient layers for the Direct3D version the game uses (measured on Apple silicon:
//       DXMT ≥ D3DMetal > DXVK for Direct3D 10/11; D3DMetal for 12; Wine's own for 9)
//    4. the classic engine (Wine 7.7 + D3DMetal) as the last resort
//
//  The miroe engine (experimental) runs a game only when it is chosen for that game, with Mullion, and nothing
//  else is tried after it: a failure there should show, not be hidden by another engine.
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
    static func plans(for game: Game) -> [LaunchPlan] {
        let engines = EngineManager.shared
        var plans: [LaunchPlan] = []
        func add(_ plan: LaunchPlan) {
            switch plan.engine {
            case .modern:
                guard let graphics = plan.graphics, graphics != .mullion, engines.offers(graphics) else { return }
            case .classic:
                guard engines.isReady(.classic) else { return }
            case .miroe:
                guard engines.isReady(.miroe) else { return }
            }
            if !plans.contains(plan) { plans.append(plan) }
        }

        switch game.winePreference {
        case .miroe:
            add(.miroe)
        case .classic:
            add(.classic)
        case .modern, .auto:
            if let chosen = game.graphicsPreference.backend {
                add(.modern(chosen))
            } else {
                if let learned = game.graphicsLearned, game.wineLearned == .modern || game.wineLearned == nil {
                    add(.modern(learned))
                }
                if game.wineLearned == .classic, game.winePreference == .auto { add(.classic) }
                if let verified = CompatibilityDatabase.entry(for: game)?.graphics { add(.modern(verified)) }
                for graphics in order(for: api(of: game)) { add(.modern(graphics)) }
            }
            if game.winePreference == .auto { add(.classic) }
        }
        return plans
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
