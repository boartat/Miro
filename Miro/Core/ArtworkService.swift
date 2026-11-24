//
//  ArtworkService.swift
//  Miro
//
//  Finds Steam library artwork for a game title (public store endpoints, no account needed).
//

import Foundation

enum ArtworkService {
    static var autoLookupEnabled: Bool {
        UserDefaults.standard.object(forKey: "autoArtworkLookup") as? Bool ?? true
    }

    /// Tiny RPG Maker / Wolf games are almost never on Steam under the same name.
    static func shouldLookUp(_ game: Game) -> Bool {
        guard !game.engine.isRPGMakerFamily else { return false }
        return normalize(game.name).count >= 4
    }

    static func steamArtwork(for title: String, strict: Bool) async -> Data? {
        var components = URLComponents(string: "https://store.steampowered.com/api/storesearch/")!
        components.queryItems = [
            URLQueryItem(name: "term", value: title),
            URLQueryItem(name: "l", value: "korean"),
            URLQueryItem(name: "cc", value: "KR")
        ]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let response = try? JSONDecoder().decode(SearchResponse.self, from: data) else { return nil }

        let wanted = normalize(title)
        let match = response.items.first { item in
            let name = normalize(item.name)
            if name == wanted { return true }
            guard !strict else { return false }
            return name.hasPrefix(wanted) || wanted.hasPrefix(name)
        } ?? (strict ? nil : response.items.first)
        guard let appID = match?.id else { return nil }

        let base = "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/\(appID)/"
        for file in ["library_hero.jpg", "header.jpg"] {
            guard let imageURL = URL(string: base + file),
                  let (imageData, response) = try? await URLSession.shared.data(from: imageURL),
                  (response as? HTTPURLResponse)?.statusCode == 200, imageData.count > 2_000 else { continue }
            return imageData
        }
        return nil
    }

    static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "™", with: "")
            .replacingOccurrences(of: "®", with: "")
            .filter { $0.isLetter || $0.isNumber }
    }

    private struct SearchResponse: Decodable {
        struct Item: Decodable {
            let id: Int
            let name: String
        }
        let items: [Item]
    }
}
