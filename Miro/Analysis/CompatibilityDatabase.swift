//
//  CompatibilityDatabase.swift
//  Miro
//
//  Per-game verdicts from highball-db's curated entries (CC0-1.0): the graphics layer that worked and
//  whether anti-cheat keeps the game off macOS. Bundled as Miro/Data/compat-db.json, rebuilt with
//  Scripts/update_compat_db.swift.
//

import Foundation

struct CompatibilityEntry: Codable, Sendable {
    var title: String
    var steamAppID: Int?
    var renderer: String?
    var anticheat: String?
    var anticheatNames: [String]?

    var graphics: GraphicsBackend? { renderer.flatMap(GraphicsBackend.init(rawValue:)) }
    /// Kernel anti-cheat: the game cannot run under Wine on a Mac
    var isBlocked: Bool { anticheat == "blocked" }
}

enum CompatibilityDatabase {
    private static let entries: [String: CompatibilityEntry] = {
        guard let url = Bundle.main.url(forResource: "compat-db", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([CompatibilityEntry].self, from: data) else { return [:] }
        var byTitle: [String: CompatibilityEntry] = [:]
        for entry in list { byTitle[key(entry.title)] = entry }
        return byTitle
    }()

    /// The entry for a game, matched by its title (letters and digits only, case-insensitive)
    static func entry(for game: Game) -> CompatibilityEntry? {
        entries[key(game.name)]
    }

    static func key(_ title: String) -> String {
        title.lowercased()
            .replacingOccurrences(of: "™", with: "")
            .replacingOccurrences(of: "®", with: "")
            .filter { $0.isLetter || $0.isNumber }
    }
}
