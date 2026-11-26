//
//  update_compat_db.swift
//  Miro
//
//  Builds Miro's compact compatibility index from a checkout of highball-db
//  (https://github.com/gauthierpiarrette/highball-db). Only the curated game entries are read
//  (db/games, CC0-1.0); the ProtonDB-derived predictions (db/derived, ODbL) are not used.
//
//      swift Scripts/update_compat_db.swift <highball-db checkout> Miro/Data/compat-db.json
//

import Foundation

struct Entry: Codable {
    var title: String
    var steamAppID: Int?
    /// dxmt, d3dmetal, dxvk or wined3d: the renderer that worked
    var renderer: String?
    /// "blocked" when kernel anti-cheat keeps the game off macOS, "warning" when anti-cheat may block it
    var anticheat: String?
    var anticheatNames: [String]?
}

guard CommandLine.arguments.count == 3 else {
    print("usage: swift update_compat_db.swift <highball-db checkout> <output json>")
    exit(1)
}
let source = URL(filePath: CommandLine.arguments[1]).appending(path: "db/games")
let output = URL(filePath: CommandLine.arguments[2])
let known: Set<String> = ["dxmt", "d3dmetal", "dxvk", "wined3d"]

var entries: [Entry] = []
for file in try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil).sorted(by: { $0.path < $1.path })
where file.pathExtension == "json" {
    guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any],
          let title = object["title"] as? String else { continue }
    var entry = Entry(title: title, steamAppID: object["steam_appid"] as? Int)
    if let renderer = object["renderer"] as? String, known.contains(renderer) { entry.renderer = renderer }
    if let anticheat = object["anticheat"] as? [String: Any], let verdict = anticheat["macVerdict"] as? String,
       ["blocked", "warning"].contains(verdict) {
        entry.anticheat = verdict
        entry.anticheatNames = anticheat["names"] as? [String]
    }
    if (object["status"] as? String) == "blocked-anticheat" { entry.anticheat = "blocked" }
    guard entry.renderer != nil || entry.anticheat != nil else { continue }
    entries.append(entry)
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
try encoder.encode(entries).write(to: output)
print("\(entries.count) games → \(output.path)")
