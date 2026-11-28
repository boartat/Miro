//
//  SteamAccount.swift
//  Miro
//
//  The Steam account Miro shows is the one signed in to the Steam app itself (SteamClient reads Steam's own files:
//  config/loginusers.vdf, the avatar cache, the library cache). There is no separate browser sign-in any more:
//  signing in and out happens in Steam's window. The store search uses Steam's public store API.
//  Earlier versions signed in through Steam's web page and kept the cookies in a web storage of Miro's own; that
//  storage and the files it wrote are removed once, as signing out did.
//

import AppKit
import Combine
import Foundation

@MainActor
final class SteamAccount: ObservableObject {
    static let shared = SteamAccount()

    struct Profile: Equatable {
        var steamID: String
        var name: String
    }

    /// A game in the account's library preview
    struct OwnedGame: Identifiable, Hashable {
        let appid: Int
        let name: String
        var id: Int { appid }
        var headerURL: URL { SteamAccount.headerURL(appid) }
    }

    /// One store search result
    struct StoreItem: Decodable, Identifiable, Hashable {
        let id: Int
        let name: String
        var tiny_image: String?
        var headerURL: URL { SteamAccount.headerURL(id) }
    }

    @Published private(set) var profile: Profile?
    @Published private(set) var avatar: NSImage?
    @Published private(set) var ownedGames: [OwnedGame] = []
    @Published private(set) var storeResults: [StoreItem] = []
    @Published private(set) var isSearching = false
    /// The library preview page is showing in the main area
    @Published var pageOpen = false

    var isLoggedIn: Bool { profile != nil }
    var profileURL: URL? { profile.map { URL(string: "https://steamcommunity.com/profiles/\($0.steamID)")! } }

    nonisolated static func headerURL(_ appID: Int) -> URL {
        URL(string: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/\(appID)/header.jpg")!
    }

    private var subscriptions: Set<AnyCancellable> = []

    private init() {
        let client = SteamClient.shared
        client.$clientAccount
            .map { $0.map { Profile(steamID: $0.steamID, name: $0.name) } }
            .removeDuplicates()
            .sink { [weak self] in self?.profile = $0 }
            .store(in: &subscriptions)
        client.$avatar.sink { [weak self] in self?.avatar = $0 }.store(in: &subscriptions)
        client.$libraryApps
            .map { $0.map { OwnedGame(appid: $0.appid, name: $0.name) } }
            .sink { [weak self] in self?.ownedGames = $0 }
            .store(in: &subscriptions)
        Self.forgetBrowserSignIn()
    }

    func refresh() { SteamClient.shared.refreshLibrary() }

    func owns(_ appID: Int) -> Bool { ownedGames.contains { $0.appid == appID } }

    /// The browser sign-in of earlier versions: its files and its cookie storage
    private static func forgetBrowserSignIn() {
        let folder = MiroPaths.libraryFolder
        for name in ["steam.json", "steam-owned.json", "steam-avatar.jpg"] {
            try? FileManager.default.removeItem(at: folder.appending(path: name))
        }
        // WKWebsiteDataStore.remove(forIdentifier:) crashes when called this early in launch (WebKit's run loop is
        // not up yet), so the store's folder is removed directly: ~/Library/WebKit/<bundle id>/WebsiteDataStore/<UUID>
        if let id = UserDefaults.standard.string(forKey: "steamWebStoreID").flatMap(UUID.init(uuidString:)) {
            UserDefaults.standard.removeObject(forKey: "steamWebStoreID")
            let store = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/WebKit/\(Bundle.main.bundleIdentifier ?? "app.miro.Miro")/WebsiteDataStore/\(id.uuidString)")
            try? FileManager.default.removeItem(at: store)
        }
    }

    // MARK: Store search

    func searchStore(_ term: String) async {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { storeResults = []; return }
        isSearching = true
        defer { isSearching = false }
        var components = URLComponents(string: "https://store.steampowered.com/api/storesearch/")!
        components.queryItems = [.init(name: "term", value: trimmed), .init(name: "l", value: "korean"), .init(name: "cc", value: "KR")]
        struct Response: Decodable { var items: [StoreItem] }
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let response = try? JSONDecoder().decode(Response.self, from: data) else { return }
        storeResults = response.items
    }
}
