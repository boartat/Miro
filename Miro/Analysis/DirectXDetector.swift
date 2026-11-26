//
//  DirectXDetector.swift
//  Miro
//
//  Guesses which graphics API a game draws with, from the DLLs its executable and the libraries next to
//  it import, and from its game engine. Only used to order the graphics layers Miro tries.
//

import Foundation

enum GraphicsAPI: String, Sendable {
    case direct3D12, direct3D11, direct3D9, openGL, unknown
}

enum DirectXDetector {
    static func detect(_ game: Game) -> GraphicsAPI {
        var imports = Set<String>()
        if let info = PEInspector.inspect(game.executableURL) {
            imports.formUnion(info.imports)
            imports.formUnion(info.delayImports)
        }
        // Engines keep their renderer in a DLL beside the exe (UnityPlayer.dll, *-Win64-Shipping.exe's modules …)
        let folder = game.folderURL
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        for file in files.prefix(300) where file.lowercased().hasSuffix(".dll") {
            if let info = PEInspector.inspect(folder.appending(path: file)) {
                imports.formUnion(info.imports)
                imports.formUnion(info.delayImports)
            }
        }
        return classify(imports: imports, engine: game.engine)
    }

    static func classify(imports: Set<String>, engine: GameEngine) -> GraphicsAPI {
        let names = Set(imports.map { $0.lowercased() })
        if names.contains("d3d12.dll") { return .direct3D12 }
        if names.contains(where: { $0 == "d3d11.dll" || $0 == "dxgi.dll" || $0.hasPrefix("d3d10") }) { return .direct3D11 }
        if names.contains(where: { $0 == "d3d9.dll" || $0 == "d3d8.dll" || $0 == "ddraw.dll" || $0.hasPrefix("d3dx9") }) {
            return .direct3D9
        }
        if names.contains("opengl32.dll") { return .openGL }
        switch engine {
        // Their Windows players default to Direct3D 11 (Unity loads it at run time, so imports don't show it)
        case .unity, .rpgMakerMV, .rpgMakerMZ, .nwjs, .electron, .gameMaker: return .direct3D11
        case .rpgMaker2000, .rpgMakerXP, .rpgMakerVX, .rpgMakerVXAce, .wolfRPG, .kirikiri, .xna: return .direct3D9
        default: return .unknown
        }
    }
}
