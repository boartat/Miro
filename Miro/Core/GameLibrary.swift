//
//  GameLibrary.swift
//  Miro
//

import AppKit
import Foundation
import WhiskyKit

@MainActor
final class GameLibrary: ObservableObject {
    static let shared = GameLibrary()

    enum SortOrder: String, CaseIterable, Identifiable {
        case alphabetical, recent
        var id: String { rawValue }
        var title: String { self == .alphabetical ? "A–Z" : "최신순" }
    }

    @Published private(set) var games: [Game] = []
    @Published var selectedID: Game.ID?
    @Published var sortOrder: SortOrder {
        didSet { UserDefaults.standard.set(sortOrder.rawValue, forKey: "librarySortOrder") }
    }
    /// Short message shown at the bottom of the window ("추가했어요", "exe 파일만 …")
    @Published var toast: String?
    /// Game folders currently being copied into Miro
    @Published private(set) var imports: [ImportJob] = []
    /// A dropped folder with several exes, waiting for the user to pick one
    @Published var folderChoice: FolderChoice?
    /// A game waiting for "remove from library" confirmation
    @Published var pendingRemoval: Game?
    /// Sidebar folders (a game belongs to at most one)
    @Published var folders: [GameFolder] = [] {
        didSet { saveFolders() }
    }
    /// "폴더 만들기" checkbox mode and the games ticked so far (kept while searching)
    @Published var selectionMode = false
    @Published var checked: Set<UUID> = []

    private var iconCache: [UUID: NSImage] = [:]
    private var coverCache: [UUID: NSImage] = [:]
    @Published private(set) var artworkRevision = 0

    private init() {
        sortOrder = SortOrder(rawValue: UserDefaults.standard.string(forKey: "librarySortOrder") ?? "") ?? .alphabetical
        load()
        loadFolders()
        selectedID = nil  // start on 홈
    }

    // MARK: - Queries

    func game(_ id: UUID?) -> Game? {
        guard let id else { return nil }
        return games.first { $0.id == id }
    }

    func sorted(filter: String, hidden: Bool = false) -> [Game] {
        let pool = games.filter { $0.isHidden == hidden }
        let filtered = filter.isEmpty ? pool : pool.filter {
            $0.name.localizedCaseInsensitiveContains(filter) || $0.fileName.localizedCaseInsensitiveContains(filter)
        }
        switch sortOrder {
        case .alphabetical:
            return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .recent:
            return filtered.sorted { $0.recentActivity > $1.recentActivity }
        }
    }

    // MARK: - Mutations

    func update(_ id: UUID, _ change: (inout Game) -> Void) {
        guard let index = games.firstIndex(where: { $0.id == id }) else { return }
        change(&games[index])
        save()
    }

    /// Asks for confirmation (shown by RootView); imported games can also send their files to the Trash
    func requestRemove(_ id: UUID) {
        pendingRemoval = game(id)
    }

    func remove(_ id: UUID, deleteFiles: Bool = false) {
        guard let game = game(id) else { return }
        for file in [game.coverFile, game.iconFile].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: MiroPaths.libraryFolder.appending(path: file))
        }
        if deleteFiles, let folder = game.importedFolder.map({ URL(fileURLWithPath: $0) }),
           folder.isInside(MiroPaths.gamesFolder), folder != MiroPaths.gamesFolder {
            NSWorkspace.shared.recycle([folder]) { _, error in
                if let error { print("Failed to move game to Trash: \(error)") }
            }
        }
        games.removeAll { $0.id == id }
        removeFromFolder(id)
        checked.remove(id)
        iconCache[id] = nil
        coverCache[id] = nil
        if selectedID == id { selectedID = nil }
        save()
        showToastMessage(deleteFiles ? "게임을 제거하고 파일을 휴지통으로 옮겼어요" : "라이브러리에서 제거했어요")
    }

    /// Handles files dropped on the window, opened from Finder or picked with the + button.
    ///  - exe / msi / bat / lnk → registered where it is
    ///  - folder → copied into Miro (C:\Games\…) together with everything the exe needs
    ///  - image → becomes the cover of the selected game
    func handle(urls: [URL]) {
        var executables: [URL] = []
        var folders: [URL] = []
        var images: [URL] = []
        var rejected = 0
        for url in urls {
            let ext = url.pathExtension.lowercased()
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
            if isDirectory.boolValue && ext != "app" {
                folders.append(url)
            } else if Game.supportedExtensions.contains(ext) {
                executables.append(url)
            } else if ["png", "jpg", "jpeg", "heic", "webp", "gif", "tiff"].contains(ext) {
                images.append(url)
            } else {
                rejected += 1
            }
        }

        if !executables.isEmpty {
            let added = add(executables)
            if let first = added.first { selectedID = first }
            showToastMessage(added.isEmpty ? "이미 라이브러리에 있어요" : "\(added.count)개의 게임을 추가했어요")
        }
        for folder in folders {
            importFolder(folder)
        }
        if executables.isEmpty && folders.isEmpty {
            if let image = images.first, let id = selectedID {
                setCover(id, imageURL: image)
                showToastMessage("커버 이미지를 바꿨어요")
            } else if rejected > 0 {
                showToastMessage("exe 파일이나 게임 폴더만 추가할 수 있어요")
            }
        }
    }

    // MARK: - Folder import

    func importFolder(_ folder: URL) {
        let source = folder.standardizedFileURL
        if let existing = games.first(where: { $0.sourcePath == source.path(percentEncoded: false) }), existing.exists {
            selectedID = existing.id
            showToastMessage("이미 라이브러리에 있는 폴더예요")
            return
        }
        let candidates = GameImporter.candidates(in: source)
        switch candidates.count {
        case 0:
            showToastMessage("'\(source.lastPathComponent)' 폴더에서 실행 파일(.exe)을 찾지 못했어요")
        case 1:
            startImport(source, executable: candidates[0])
        default:
            folderChoice = FolderChoice(folder: source, candidates: candidates)
        }
    }

    /// Copies `folder` into C:\Games and registers `executable` (a path relative to `folder`).
    func startImport(_ folder: URL, executable: String) {
        // Already inside Miro's games folder: nothing to copy
        if folder.isInside(MiroPaths.gamesFolder) {
            let added = add([folder.appending(path: executable)])
            if let id = added.first {
                update(id) { $0.importedFolder = folder.path(percentEncoded: false) }
                selectedID = id
            }
            return
        }

        let job = ImportJob(name: folder.lastPathComponent)
        imports.append(job)
        let jobID = job.id
        let destination = GameImporter.destination(for: folder)
        showToastMessage("'\(folder.lastPathComponent)' 폴더를 Miro로 복사하는 중…")

        Task.detached(priority: .userInitiated) {
            let result: Result<Void, Error> = Result {
                try GameImporter.copyFolder(folder, to: destination) { fraction, detail in
                    Task { @MainActor in GameLibrary.shared.updateImport(jobID, progress: fraction, detail: detail) }
                }
            }
            if case .failure = result { try? FileManager.default.removeItem(at: destination) }
            await GameLibrary.shared.finishImport(
                jobID, result: result, source: folder, destination: destination, executable: executable
            )
        }
    }

    private func updateImport(_ id: UUID, progress: Double, detail: String) {
        guard let index = imports.firstIndex(where: { $0.id == id }) else { return }
        imports[index].progress = progress
        imports[index].detail = detail
    }

    private func finishImport(
        _ jobID: UUID, result: Result<Void, Error>, source: URL, destination: URL, executable: String
    ) {
        imports.removeAll { $0.id == jobID }
        switch result {
        case .success:
            let added = add([destination.appending(path: executable)])
            guard let id = added.first else { return }
            update(id) { game in
                game.importedFolder = destination.path(percentEncoded: false)
                game.sourcePath = source.path(percentEncoded: false)
            }
            selectedID = id
            showToastMessage("'\(source.lastPathComponent)'을(를) 추가했어요 · C:\\Games\\\(destination.lastPathComponent)")
        case .failure(let error):
            showToastMessage("복사하지 못했어요: \(error.localizedDescription)")
        }
    }

    /// Changes which exe inside the game's folder is launched
    func setExecutable(_ id: UUID, relativePath: String) {
        guard let game = game(id) else { return }
        relocate(id, to: game.rootFolderURL.appending(path: relativePath))
    }

    @discardableResult
    func add(_ urls: [URL]) -> [UUID] {
        var added: [UUID] = []
        for url in urls {
            var target = url
            if url.pathExtension.lowercased() == "lnk",
               let resolved = Self.resolveShortcut(url) {
                target = resolved
            }
            let path = target.standardizedFileURL.path(percentEncoded: false)
            if let existing = games.first(where: { $0.executablePath == path }) {
                if added.isEmpty { selectedID = existing.id }
                continue
            }
            var game = Game(name: target.deletingPathExtension().lastPathComponent, executablePath: path)
            let quick = EngineDetector.detect(executable: target)
            game.engine = quick.engine
            game.name = EngineDetector.displayName(for: target, detected: quick)
            games.append(game)
            added.append(game.id)
            analyze(game.id)
        }
        save()
        return added
    }

    func relocate(_ id: UUID, to url: URL) {
        update(id) { $0.executablePath = url.standardizedFileURL.path(percentEncoded: false) }
        analyze(id)
    }

    func showToastMessage(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            if toast == message { toast = nil }
        }
    }

    // MARK: - Background analysis (icon, engine, architecture, cover art)

    func analyze(_ id: UUID) {
        guard let game = game(id) else { return }
        let url = game.executableURL
        let iconName = "Icons/\(id.uuidString).png"
        Task.detached(priority: .utility) {
            let engine = EngineDetector.detect(executable: url)
            let info = PEInspector.inspect(url)
            let iconData = Self.extractIcon(url)
            if let iconData {
                MiroPaths.ensure(MiroPaths.icons)
                try? iconData.write(to: MiroPaths.libraryFolder.appending(path: iconName))
            }
            await GameLibrary.shared.applyAnalysis(
                id: id, engine: engine, arch: info?.arch.rawValue, iconFile: iconData == nil ? nil : iconName
            )
        }
    }

    private func applyAnalysis(id: UUID, engine: EngineInfo, arch: String?, iconFile: String?) async {
        update(id) { game in
            game.engine = engine.engine
            game.architecture = arch
            if let iconFile { game.iconFile = iconFile }
        }
        iconCache[id] = nil
        artworkRevision += 1

        if let game = game(id), !game.artworkLookupDone, game.coverFile == nil, ArtworkService.autoLookupEnabled,
           ArtworkService.shouldLookUp(game) {
            await fetchArtwork(id)
        }
    }

    /// Searches Steam for matching artwork (only exact/near-exact title matches are accepted)
    func fetchArtwork(_ id: UUID, force: Bool = false) async {
        guard let game = game(id) else { return }
        update(id) { $0.artworkLookupDone = true }
        guard let data = await ArtworkService.steamArtwork(for: game.name, strict: !force) else {
            if force { showToastMessage("Steam에서 '\(game.name)' 아트워크를 찾지 못했어요") }
            return
        }
        storeCover(id, data: data)
        if force { showToastMessage("Steam 아트워크를 적용했어요") }
    }

    // MARK: - Artwork storage

    func setCover(_ id: UUID, imageURL: URL) {
        guard let data = try? Data(contentsOf: imageURL) else { return }
        storeCover(id, data: data)
    }

    func storeCover(_ id: UUID, data: Data) {
        MiroPaths.ensure(MiroPaths.covers)
        let name = "Covers/\(id.uuidString)-\(Int(Date.now.timeIntervalSince1970)).img"
        guard (try? data.write(to: MiroPaths.libraryFolder.appending(path: name))) != nil else { return }
        if let old = game(id)?.coverFile {
            try? FileManager.default.removeItem(at: MiroPaths.libraryFolder.appending(path: old))
        }
        update(id) { $0.coverFile = name }
        coverCache[id] = nil
        artworkRevision += 1
    }

    func removeCover(_ id: UUID) {
        if let old = game(id)?.coverFile {
            try? FileManager.default.removeItem(at: MiroPaths.libraryFolder.appending(path: old))
        }
        update(id) { $0.coverFile = nil }
        coverCache[id] = nil
        artworkRevision += 1
    }

    func icon(for game: Game) -> NSImage? {
        if let cached = iconCache[game.id] { return cached }
        guard let file = game.iconFile,
              let image = NSImage(contentsOf: MiroPaths.libraryFolder.appending(path: file)) else { return nil }
        iconCache[game.id] = image
        return image
    }

    func cover(for game: Game) -> NSImage? {
        if let cached = coverCache[game.id] { return cached }
        guard let file = game.coverFile,
              let image = NSImage(contentsOf: MiroPaths.libraryFolder.appending(path: file)) else { return nil }
        coverCache[game.id] = image
        return image
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: MiroPaths.libraryFile) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        games = (try? decoder.decode([Game].self, from: data)) ?? []
    }

    private func save() {
        MiroPaths.ensure(MiroPaths.libraryFolder)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(games) else { return }
        try? data.write(to: MiroPaths.libraryFile, options: .atomic)
    }

    // MARK: - Helpers

    nonisolated private static func extractIcon(_ url: URL) -> Data? {
        guard let peFile = try? PEFile(url: url), let image = peFile.bestIcon(),
              image.isValid, image.size.width > 0,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func resolveShortcut(_ url: URL) -> URL? {
        guard let bottle = RuntimeManager.shared.bottle,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return ShellLinkHeader.getProgram(url: url, handle: handle, bottle: bottle)?.url
    }
}
