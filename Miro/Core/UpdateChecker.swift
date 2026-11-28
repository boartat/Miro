//
//  UpdateChecker.swift
//  Miro
//
//  Whether this Miro is the newest release on GitHub (the public releases API; nothing about the user is sent).
//

import Foundation

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    enum Status: Equatable {
        case checking
        case latest
        case available(version: String, url: URL)
        case unknown
    }

    @Published private(set) var status: Status = .checking
    private var lastCheck: Date?

    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    private init() {}

    /// Checks at most every 30 minutes unless forced
    func check(force: Bool = false) async {
        if !force, let lastCheck, Date.now.timeIntervalSince(lastCheck) < 1800 { return }
        lastCheck = .now
        status = .checking
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/boartat/Miro/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        struct Release: Decodable { var tag_name: String; var html_url: String }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let release = try? JSONDecoder().decode(Release.self, from: data),
              let url = URL(string: release.html_url) else {
            status = .unknown
            return
        }
        let latest = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        status = Self.isNewer(latest, than: currentVersion) ? .available(version: latest, url: url) : .latest
    }

    /// "1.10.0" > "1.9.2"
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let b = current.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}
