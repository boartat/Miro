//
//  SteamClient.swift
//  Miro
//
//  The Windows Steam client inside the miroe engine's prefix: Miro installs it (Valve's own installer) and starts it.
//  Signing in happens in Steam's own window only; Miro reads who is signed in (config/loginusers.vdf, the avatar
//  cache) and what the library holds (appcache/appinfo.vdf for the apps in appcache/librarycache) from Steam's own
//  files, so there is no second sign-in in a browser. Games Steam has finished installing (app manifests) join
//  Miro's library; they start through Steam (-applaunch) with Steam running.
//

import AppKit
import Foundation
import WhiskyKit

@MainActor
final class SteamClient: ObservableObject {
    static let shared = SteamClient()

    enum State: Equatable {
        case notInstalled
        case installing(String)
        case installed
        case failed(String)
    }

    /// A game Steam is installing for Miro, as its app manifest reports it
    struct Download: Equatable {
        var name: String
        var progress: Double?   // 0…1 once Steam knows the size
        var phase: String
    }

    @Published private(set) var state: State = .notInstalled
    @Published private(set) var downloads: [Int: Download] = [:]
    /// App IDs with a complete install in Steam's library folder
    @Published private(set) var installedApps: Set<Int> = []

    private var process: RunningProcess?
    private var poller: Task<Void, Never>?

    static let installerURL = URL(string: "https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe")!
    static let installerSize = "약 2MB, 처음 실행할 때 Steam이 스스로 약 300MB를 더 받아요"

    var engine: WineEngine { .miroe }
    var steamFolder: URL { engine.bottleURL.appending(path: "drive_c/Program Files (x86)/Steam") }
    var steamExe: URL { steamFolder.appending(path: "steam.exe") }
    var appsFolder: URL { steamFolder.appending(path: "steamapps") }
    var isInstalled: Bool { steamExe.fileExists }
    var isRunning: Bool { process?.isRunning == true || steamProcessRunning || launching }

    private init() {
        refreshState()
        startSync()
    }

    func refreshState() {
        if case .installing = state { return }
        state = isInstalled ? .installed : .notInstalled
    }

    // MARK: Install the client

    /// No client yet: install it now (quietly skipped while the miroe engine is missing)
    func installClientIfNeeded() async {
        guard !isInstalled, EngineManager.shared.isReady(.miroe) else { return }
        if case .installing = state { return }
        await installClient()
    }

    /// Downloads Valve's installer and runs it silently in the modern engine's prefix
    func installClient() async {
        guard !isInstalled else { state = .installed; return }
        guard let bottle = EngineManager.shared.bottle(for: .miroe), EngineManager.shared.isReady(.miroe) else {
            state = .failed("Steam은 miroe 엔진에서 돌아요. 설정 → 호환 레이어에서 miroe의 Windows 환경을 먼저 준비해 주세요.")
            return
        }
        state = .installing("Steam을 설치하고 있어요 · 설치 파일 받는 중…")
        do {
            MiroPaths.ensure(MiroPaths.downloads)
            let setup = MiroPaths.downloads.appending(path: "SteamSetup.exe")
            let (temporary, response) = try await URLSession.shared.download(from: Self.installerURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            try? FileManager.default.removeItem(at: setup)
            try FileManager.default.moveItem(at: temporary, to: setup)
            state = .installing("Steam을 설치하고 있어요 · 끝나면 자동으로 준비돼요")
            _ = try await engine.run([setup.path(percentEncoded: false), "/S"], bottle: bottle)
            // the installer can finish writing just after wine returns
            for _ in 0..<20 where !isInstalled { try? await Task.sleep(for: .seconds(1)) }
            guard isInstalled else { throw URLError(.cannotCreateFile) }
            state = .installed
        } catch {
            state = .failed("Steam을 설치하지 못했어요. 인터넷 연결을 확인하고 다시 시도해 주세요.")
        }
    }

    // MARK: Run it

    /// Starts Steam (its own window: sign-in the first time, then its library). With Steam up, a second steam.exe
    /// hands its arguments (steam://…, -applaunch) to it and exits; without arguments it brings Steam's window up.
    /// Only once Steam is up (its window process is there): a second steam.exe that comes while the first one is still
    /// starting does not hand over but becomes a second Steam beside it, whose window process never comes up
    /// ("steamwebhelper가 응답하지 않습니다"). Requests that come meanwhile wait and are handed over then.
    func start(_ extra: [String] = []) {
        guard isInstalled, EngineManager.shared.bottle(for: .miroe) != nil else { return }
        if launching || (isRunning && !steamWebHelperRunning()) {
            // being prepared (prefix update, fonts, display) or still starting: starting steam.exe now would skip the
            // preparation (the updater then drew Korean as boxes) or make a second Steam
            if !extra.isEmpty { pending.append(extra) }
            if !launching { Task { await handOverWhenUp() } }
            return
        }
        if isRunning {
            handOver(extra)
            return
        }
        guard let bottle = EngineManager.shared.bottle(for: .miroe) else { return }
        launching = true
        Task {
            await EngineManager.shared.updateMiroePrefixIfNeeded()
            MiroeMigration.linkSteam()
            await MiroeMigration.installSteamService()
            // Steam's window is DPI-aware: Retina pixels at 200 % keep it sharp and at its normal size; games get
            // their own DPI flag (MiroeMigration.prepareDisplay)
            await MiroeMigration.prepareDisplay(games: GameLibrary.shared.games)
            await CJKFonts.applyIfNeeded(engine: engine, bottle: bottle)
            if let (running, _) = try? ProcessRunner.start(executable: engine.wineBinary, arguments: arguments(extra),
                                                             environment: environment(bottle), logURL: logURL()) {
                process = running
            }
            launching = false
            await handOverWhenUp()
        }
    }
    private var launching = false
    private var waiting = false
    private var pending: [[String]] = []

    private func arguments(_ extra: [String]) -> [String] { [steamExe.path(percentEncoded: false), "-no-cef-sandbox"] + extra }
    private func logURL() -> URL { MiroPaths.logs.appending(path: "steam-\(Int(Date.now.timeIntervalSince1970)).log") }
    private func environment(_ bottle: Bottle) -> [String: String] {
        var environment = ProcessRunner.baseEnvironment
        environment.merge(engine.environment(for: bottle)) { $1 }
        return environment
    }

    /// A second steam.exe for a Steam that is up: it hands the arguments over and exits
    private func handOver(_ extra: [String]) {
        guard let bottle = EngineManager.shared.bottle(for: .miroe) else { return }
        _ = try? ProcessRunner.start(executable: engine.wineBinary, arguments: arguments(extra),
                                     environment: environment(bottle), logURL: logURL())
    }

    /// Hands the waiting requests over once Steam's window process is there (one waiter at a time). Steam takes from
    /// 20 seconds to a couple of minutes to come up under Wine, longer while it updates itself
    private func handOverWhenUp() async {
        guard !waiting else { return }
        waiting = true
        defer { waiting = false }
        let deadline = Date.now.addingTimeInterval(300)
        while Date.now < deadline, !steamWebHelperRunning() {
            if !launching, process?.isRunning != true, ProcessTree.findWindowsProcess(named: "steam.exe") == nil { break }
            try? await Task.sleep(for: .seconds(1))
        }
        let queued = pending
        pending = []
        guard steamWebHelperRunning() else { return }
        for extra in queued { handOver(extra) }
    }

    /// Before a Steam game starts: Steam must be up for the game's Steam API and for -applaunch.
    /// Starts it (in the background) when it is not running and waits until its window process is there.
    @discardableResult
    func ensureRunning() async -> Bool {
        guard isInstalled else { return false }
        if steamWebHelperRunning() { return true }
        if !isRunning { start(["-silent"]) }
        // Steam takes from 20 seconds to a couple of minutes to come up under Wine (longer after an update)
        let deadline = Date.now.addingTimeInterval(240)
        while Date.now < deadline {
            try? await Task.sleep(for: .seconds(2))
            if steamWebHelperRunning() {
                try? await Task.sleep(for: .seconds(8))   // its sign-in finishes after the window process starts
                return true
            }
            if !launching, process?.isRunning != true, ProcessTree.findWindowsProcess(named: "steam.exe") == nil { return false }
        }
        return false
    }

    private func steamWebHelperRunning() -> Bool {
        ProcessTree.findWindowsProcess(named: "steam.exe") != nil && ProcessTree.findWindowsProcess(named: "steamwebhelper.exe") != nil
    }

    /// Opens a game's page in Steam's own library (or the store page for a game not in it)
    func openInSteam(_ appID: Int, store: Bool = false) {
        start([store ? "steam://store/\(appID)" : "steam://nav/games/details/\(appID)"])
    }

    /// Ends Steam and every other Windows program of the miroe prefix
    func stopAll() {
        engine.killAll()
        process = nil
        steamProcessRunning = false
    }

    // MARK: Install a game

    /// Installs the client if needed, then asks Steam to install `appID`. Steam shows its own install dialog
    /// (where to install, size); from then on the sync below follows and registers the game by itself.
    func install(_ appID: Int, name: String) async {
        if !isInstalled { await installClient() }
        guard isInstalled else { return }
        requested[appID] = name
        start(["steam://install/\(appID)"])
        sync()
    }

    // MARK: Library sync

    /// What Steam's app manifest says about an app (StateFlags bits: 2 update required, 4 fully installed,
    /// 256 update running, 512 update paused, 1024 update started, 2048 uninstalling)
    enum AppPhase: Equatable {
        case queued, downloading, paused, installed, updateRequired, uninstalling
        var label: String {
            switch self {
            case .queued: return "다운로드 대기"
            case .downloading: return "다운로드 중"
            case .paused: return "일시 정지"
            case .installed: return "실행 가능"
            case .updateRequired: return "업데이트 필요"
            case .uninstalling: return "삭제 중"
            }
        }
    }

    struct AppStatus: Equatable {
        var appID: Int
        var name: String
        var phase: AppPhase
        var progress: Double?
        /// The game's folder (steamapps/common/<installdir> of the library it is in)
        var folder: URL
    }

    /// Every app in every Steam library folder of this prefix
    @Published private(set) var apps: [Int: AppStatus] = [:]
    /// Steam itself (steam.exe) is running in this prefix, however it was started
    @Published private(set) var steamProcessRunning = false
    /// Apps Miro asked Steam to install and has not seen a manifest for yet
    @Published private(set) var requested: [Int: String] = [:]
    private var syncTimer: Timer?

    /// The account the Steam app itself is signed in with (config/loginusers.vdf, the most recent user)
    struct ClientAccount: Equatable { var steamID: String; var name: String }
    @Published private(set) var clientAccount: ClientAccount?

    private func readClientAccount() -> ClientAccount? {
        guard let text = try? String(contentsOf: steamFolder.appending(path: "config/loginusers.vdf"), encoding: .utf8) else { return nil }
        var current: String?
        var name: String?
        var best: ClientAccount?
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\"", omittingEmptySubsequences: false)
            if parts.count == 3, parts[1].count == 17, parts[1].allSatisfy(\.isNumber) { current = String(parts[1]); name = nil; continue }
            guard parts.count >= 5, let id = current else { continue }
            if parts[1] == "PersonaName" { name = String(parts[3]) }
            if parts[1] == "MostRecent", parts[3] == "1" { best = ClientAccount(steamID: id, name: name ?? "Steam") }
            if best == nil, let name { best = ClientAccount(steamID: id, name: name) }
        }
        return best
    }

    /// The signed-in account's avatar, from Steam's own avatar cache
    @Published private(set) var avatar: NSImage?

    // MARK: Library preview

    /// A game in the account's Steam library, as the Steam app has it cached
    struct LibraryApp: Identifiable, Hashable, Sendable {
        let appid: Int
        let name: String
        var id: Int { appid }
    }
    /// The Steam library (games only), read from Steam's files: the apps it keeps library art for
    /// (appcache/librarycache/<appid>) with their names and types from its app info cache (appcache/appinfo.vdf)
    @Published private(set) var libraryApps: [LibraryApp] = []
    private var libraryStamp: Date?
    private var readingLibrary = false

    private func refreshLibraryPreview(force: Bool = false) {
        let appinfo = steamFolder.appending(path: "appcache/appinfo.vdf")
        let stamp = (try? appinfo.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard !readingLibrary, force || stamp != libraryStamp else { return }
        readingLibrary = true
        let folder = steamFolder
        Task {
            let apps = await Task.detached(priority: .utility) { Self.readLibrary(steamFolder: folder) }.value
            if apps != libraryApps { libraryApps = apps }
            libraryStamp = stamp
            readingLibrary = false
        }
    }

    func refreshLibrary() { sync(); refreshLibraryPreview(force: true) }

    nonisolated static func readLibrary(steamFolder: URL) -> [LibraryApp] {
        let cache = steamFolder.appending(path: "appcache/librarycache")
        let ids = Set(((try? FileManager.default.contentsOfDirectory(atPath: cache.path(percentEncoded: false))) ?? []).compactMap(Int.init))
        guard !ids.isEmpty, let data = try? Data(contentsOf: steamFolder.appending(path: "appcache/appinfo.vdf"), options: .alwaysMapped)
        else { return [] }
        let info = AppInfoReader.common(of: ids, in: data)
        return ids.compactMap { id -> LibraryApp? in
            guard let common = info[id], common["type"]?.lowercased() == "game", let name = common["name"], !name.isEmpty else { return nil }
            return LibraryApp(appid: id, name: name)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Not games: Steam's shared redistributables, Proton/Steam Linux Runtime and similar tools
    static let tools: Set<Int> = [228980, 1070560, 1391110, 1628350, 1493710, 1826330, 2180100]

    /// Watches Steam's library every few seconds while Miro runs (cheap: a directory listing and small text files)
    func startSync() {
        guard syncTimer == nil else { return }
        sync()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in
            Task { @MainActor in SteamClient.shared.sync() }
        }
    }

    /// Reads libraryfolders.vdf and every appmanifest, then makes Miro's library match:
    /// downloading and installed games are registered (once per app ID), moved games follow their new folder,
    /// and games Steam uninstalled leave the library.
    func sync() {
        refreshState()
        guard isInstalled else { return }
        steamProcessRunning = ProcessTree.findWindowsProcess(named: "steam.exe") != nil
        let account = readClientAccount()
        if account != clientAccount {
            clientAccount = account
            avatar = account.flatMap { NSImage(contentsOf: steamFolder.appending(path: "config/avatarcache/\($0.steamID).png")) }
        }
        refreshLibraryPreview()
        var found: [Int: AppStatus] = [:]
        for library in libraryFolders() {
            let steamapps = library.appending(path: "steamapps")
            guard let files = try? FileManager.default.contentsOfDirectory(at: steamapps, includingPropertiesForKeys: nil) else { continue }
            for file in files where file.lastPathComponent.hasPrefix("appmanifest_") && file.pathExtension == "acf" {
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
                let values = Self.keyValues(text)
                guard let appID = values["appid"].flatMap(Int.init), !Self.tools.contains(appID),
                      let installDir = values["installdir"] else { continue }
                let flags = values["StateFlags"].flatMap(Int.init) ?? 0
                let total = values["BytesToDownload"].flatMap(Double.init) ?? 0
                let done = values["BytesDownloaded"].flatMap(Double.init) ?? 0
                found[appID] = AppStatus(
                    appID: appID, name: values["name"] ?? requested[appID] ?? "Steam 게임",
                    phase: Self.phase(flags: flags, total: total, done: done),
                    progress: total > 0 ? min(done / total, 1) : nil,
                    folder: steamapps.appending(path: "common").appending(path: installDir))
            }
        }
        if found != apps { apps = found }
        for appID in found.keys { requested[appID] = nil }
        reconcileLibrary(with: found)
        installedApps = Set(found.values.filter { $0.phase == .installed || $0.phase == .updateRequired }.map(\.appID))
        downloads = Dictionary(uniqueKeysWithValues: found.values
            .filter { [.queued, .downloading, .paused].contains($0.phase) }
            .map { ($0.appID, Download(name: $0.name, progress: $0.progress, phase: $0.phase.label)) })
            .merging(requested.mapValues { Download(name: $0, progress: nil, phase: "Steam 창에서 설치를 확인해 주세요") }) { a, _ in a }
    }

    nonisolated static func phase(flags: Int, total: Double, done: Double) -> AppPhase {
        if flags & 2048 != 0 { return .uninstalling }
        if flags & 512 != 0 { return .paused }
        if flags & (256 | 1024) != 0 { return .downloading }
        if flags & 4 != 0 { return flags & 2 != 0 ? .updateRequired : .installed }
        return total > 0 && done > 0 ? .paused : .queued
    }

    /// The Steam library folders as Mac paths ("C:\\Games\\SteamLibrary" → …/drive_c/Games/SteamLibrary).
    /// Other drive letters follow the prefix's dosdevices links.
    func libraryFolders() -> [URL] {
        var folders = [steamFolder]
        let vdf = appsFolder.appending(path: "libraryfolders.vdf")
        if let text = try? String(contentsOf: vdf, encoding: .utf8) {
            for line in text.split(whereSeparator: \.isNewline) {
                let parts = line.split(separator: "\"", omittingEmptySubsequences: false)
                guard parts.count >= 5, parts[1] == "path" else { continue }
                let windows = parts[3].replacingOccurrences(of: "\\\\", with: "\\")
                if let url = macURL(windowsPath: windows),
                   !folders.contains(where: { $0.resolvingSymlinksInPath().path == url.resolvingSymlinksInPath().path }) {
                    folders.append(url)
                }
            }
        }
        return folders
    }

    func macURL(windowsPath: String) -> URL? {
        let parts = windowsPath.split(separator: "\\").map(String.init)
        guard let drive = parts.first?.lowercased(), drive.count == 2, drive.hasSuffix(":") else { return nil }
        let root = engine.bottleURL.appending(path: "dosdevices").appending(path: drive).resolvingSymlinksInPath()
        return parts.dropFirst().reduce(root) { $0.appending(path: $1) }
    }

    /// Makes the Miro library match Steam's (only for games Steam manages)
    private func reconcileLibrary(with found: [Int: AppStatus]) {
        let library = GameLibrary.shared
        // a game added by hand from a Steam folder becomes a Steam game
        for game in library.games where game.steamAppID == nil {
            if let status = found.values.first(where: { game.executablePath.hasPrefix($0.folder.path(percentEncoded: false) + "/") }) {
                library.update(game.id) { $0.steamAppID = status.appID; $0.winePreference = .miroe }
            }
        }
        for status in found.values where status.phase != .uninstalling {
            let existing = library.games.filter { $0.steamAppID == status.appID }
            // only games Steam has finished installing are in the library; an entry Miro made for a download
            // in progress (earlier versions did) and never played leaves until the download is done (a game
            // being updated after it was played stays)
            guard status.phase == .installed || status.phase == .updateRequired else {
                for game in existing where game.launchCount == 0 && game.playSeconds == 0 { library.remove(game.id) }
                continue
            }
            // one entry per app: keep the first, drop the duplicates
            for duplicate in existing.dropFirst() { library.remove(duplicate.id) }
            let executable = bestExecutable(in: status.folder)
            if let game = existing.first {
                // moved to another library folder, or finished downloading: point at the real file
                if let executable, !game.exists || !game.executablePath.hasPrefix(status.folder.path(percentEncoded: false) + "/") {
                    library.relocate(game.id, to: executable)
                }
                continue
            }
            register(status, executable: executable)
        }
        // uninstalled in Steam: the manifest is gone and so are the files
        for game in library.games where game.steamAppID != nil {
            guard let appID = game.steamAppID, found[appID] == nil, requested[appID] == nil, !game.exists,
                  game.executablePath.contains("/steamapps/common/") else { continue }
            library.remove(game.id)
            library.showToastMessage("Steam에서 삭제된 '\(game.name)'을(를) 라이브러리에서 뺐어요")
        }
    }

    private func bestExecutable(in folder: URL) -> URL? {
        GameImporter.candidates(in: folder).first.map { folder.appending(path: $0) }
    }

    /// A new Steam game in the library: while it downloads it points at its future folder and shows Steam's progress
    private func register(_ status: AppStatus, executable: URL?) {
        let library = GameLibrary.shared
        let target = executable ?? status.folder.appending(path: "\(status.folder.lastPathComponent).exe")
        guard let id = library.add([target]).first else { return }
        library.update(id) {
            $0.steamAppID = status.appID
            $0.name = status.name
            $0.winePreference = .miroe
            $0.artworkLookupDone = true
        }
        library.showToastMessage("'\(status.name)'을(를) 라이브러리에 추가했어요")
        Task {
            for file in ["library_hero.jpg", "header.jpg"] {
                let url = URL(string: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/\(status.appID)/\(file)")!
                if let (data, response) = try? await URLSession.shared.data(from: url),
                   (response as? HTTPURLResponse)?.statusCode == 200, data.count > 2_000 {
                    library.storeCover(id, data: data)
                    break
                }
            }
        }
    }

    /// `"key"  "value"` pairs of a Valve KeyValues file (first occurrence; nested blocks are flattened)
    nonisolated static func keyValues(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\"", omittingEmptySubsequences: false)
            guard parts.count >= 5 else { continue }
            let key = String(parts[1])
            if values[key] == nil { values[key] = String(parts[3]) }
        }
        return values
    }

    /// The library game for a Steam app
    func libraryGame(_ appID: Int) -> Game? {
        GameLibrary.shared.games.first { $0.steamAppID == appID }
    }

    /// Kept for callers that only need a quick re-read
    func scanManifests() { sync() }
}

/// Reads Steam's binary app info cache (appcache/appinfo.vdf, versions 28 and 29): for the asked apps, the string
/// values directly under appinfo → common (name, type …). Bounds-checked: a file Steam is rewriting gives fewer apps.
enum AppInfoReader {
    static func common(of wanted: Set<Int>, in data: Data) -> [Int: [String: String]] {
        data.withUnsafeBytes { raw -> [Int: [String: String]] in
            let bytes = raw.bindMemory(to: UInt8.self)
            var reader = Reader(bytes: bytes)
            guard let magic = reader.u32(), magic == 0x07564429 || magic == 0x07564428, reader.u32() != nil else { return [:] }
            var strings: [String]?
            if magic == 0x07564429 {
                guard let offset = reader.i64(), offset > 0, Int(offset) < bytes.count else { return [:] }
                var table = Reader(bytes: bytes, at: Int(offset))
                guard let count = table.u32() else { return [:] }
                var list: [String] = []
                list.reserveCapacity(Int(count))
                for _ in 0..<count { guard let text = table.cString() else { return [:] }; list.append(text) }
                strings = list
            }
            var result: [Int: [String: String]] = [:]
            while let appID = reader.u32(), appID != 0, let size = reader.u32() {
                let end = reader.position + Int(size)
                guard end <= bytes.count else { break }
                if wanted.contains(Int(appID)) {
                    // info state, last updated, PICS token, SHA-1, change number, binary SHA-1
                    reader.position += 4 + 4 + 8 + 20 + 4 + 20
                    var common: [String: String] = [:]
                    if reader.readSection(strings: strings, path: [], into: &common) { result[Int(appID)] = common }
                }
                reader.position = end
            }
            return result
        }
    }

    private struct Reader {
        let bytes: UnsafeBufferPointer<UInt8>
        var position: Int

        init(bytes: UnsafeBufferPointer<UInt8>, at position: Int = 0) {
            self.bytes = bytes
            self.position = position
        }

        mutating func u8() -> UInt8? {
            guard position < bytes.count else { return nil }
            defer { position += 1 }
            return bytes[position]
        }

        mutating func u32() -> UInt32? {
            guard position + 4 <= bytes.count else { return nil }
            var value: UInt32 = 0
            for index in 0..<4 { value |= UInt32(bytes[position + index]) << (8 * index) }
            position += 4
            return value
        }

        mutating func i64() -> Int64? {
            guard let low = u32(), let high = u32() else { return nil }
            return Int64(bitPattern: UInt64(high) << 32 | UInt64(low))
        }

        mutating func cString() -> String? {
            var end = position
            while end < bytes.count, bytes[end] != 0 { end += 1 }
            guard end < bytes.count else { return nil }
            let text = String(decoding: UnsafeBufferPointer(rebasing: bytes[position..<end]), as: UTF8.self)
            position = end + 1
            return text
        }

        mutating func key(_ strings: [String]?) -> String? {
            if let strings {
                guard let index = u32(), Int(index) < strings.count else { return nil }
                return strings[Int(index)]
            }
            return cString()
        }

        /// Binary KeyValues: type byte, key, value; 0x08 ends a section. Keeps strings at appinfo/common/<key>.
        mutating func readSection(strings: [String]?, path: [String], into common: inout [String: String]) -> Bool {
            while true {
                guard let type = u8() else { return false }
                if type == 0x08 { return true }
                guard let key = key(strings) else { return false }
                switch type {
                case 0x00:
                    guard readSection(strings: strings, path: path + [key], into: &common) else { return false }
                case 0x01:
                    guard let value = cString() else { return false }
                    if path.count == 2, path[0] == "appinfo", path[1] == "common" { common[key] = value }
                case 0x02, 0x03, 0x04, 0x06: position += 4
                case 0x07, 0x0A: position += 8
                default: return false
                }
                if position > bytes.count { return false }
            }
        }
    }
}
