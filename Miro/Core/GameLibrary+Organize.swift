//
//  GameLibrary+Organize.swift
//  Miro
//
//  Folders (drag a game onto another, or tick games and "폴더 만들기") and hiding games
//  in the secret box.
//

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct GameFolder: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var gameIDs: [UUID]
    var isExpanded = true
}

/// Drag payload for moving games around the sidebar (custom type so Finder file drops are unaffected)
struct GameDragItem: Codable, Transferable {
    let gameID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .miroGame)
    }
}

extension UTType {
    static let miroGame = UTType(exportedAs: "app.miro.game-reference")
}

extension GameLibrary {
    // MARK: - Queries

    func folder(containing gameID: UUID) -> GameFolder? {
        folders.first { $0.gameIDs.contains(gameID) }
    }

    /// Visible (not hidden) games of a folder, filtered and sorted like the main list
    func games(in folder: GameFolder, filter: String) -> [Game] {
        sorted(filter: filter).filter { folder.gameIDs.contains($0.id) }
    }

    /// Visible games that are not in any folder
    func ungroupedGames(filter: String) -> [Game] {
        let grouped = Set(folders.flatMap(\.gameIDs))
        return sorted(filter: filter).filter { !grouped.contains($0.id) }
    }

    /// Folders in display order (A–Z, or by most recent activity of their games)
    var sortedFolders: [GameFolder] {
        switch sortOrder {
        case .alphabetical:
            return folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .recent:
            func latest(_ folder: GameFolder) -> Date {
                folder.gameIDs.compactMap { game($0)?.recentActivity }.max() ?? .distantPast
            }
            return folders.sorted { latest($0) > latest($1) }
        }
    }

    // MARK: - Folders

    @discardableResult
    func createFolder(named name: String, with gameIDs: [UUID]) -> UUID {
        let ids = gameIDs.filter { game($0) != nil }
        for id in ids { removeFromFolder(id, keepEmpty: true) }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = GameFolder(name: trimmed.isEmpty ? "새 폴더" : trimmed, gameIDs: ids)
        folders.append(folder)
        pruneEmptyFolders()
        showToastMessage("'\(folder.name)' 폴더를 만들었어요")
        return folder.id
    }

    /// Dropping `dragged` onto `target`: joins target's folder, or makes a new folder with both
    @discardableResult
    func drop(_ dragged: UUID, onto target: UUID) -> UUID? {
        guard dragged != target, game(dragged) != nil, game(target) != nil else { return nil }
        if let folder = folder(containing: target) {
            addToFolder(dragged, folderID: folder.id)
            return nil
        }
        return createFolder(named: "새 폴더", with: [target, dragged])
    }

    func addToFolder(_ gameID: UUID, folderID: UUID) {
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return }
        guard !folders[index].gameIDs.contains(gameID) else { return }
        removeFromFolder(gameID, keepEmpty: true)
        guard let target = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[target].gameIDs.append(gameID)
        folders[target].isExpanded = true
        pruneEmptyFolders()
    }

    func removeFromFolder(_ gameID: UUID, keepEmpty: Bool = false) {
        guard folders.contains(where: { $0.gameIDs.contains(gameID) }) else { return }
        for index in folders.indices {
            folders[index].gameIDs.removeAll { $0 == gameID }
        }
        if !keepEmpty { pruneEmptyFolders() }
    }

    func renameFolder(_ folderID: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[index].name = trimmed
    }

    /// Removes the folder; its games go back to the main list
    func dissolveFolder(_ folderID: UUID) {
        folders.removeAll { $0.id == folderID }
    }

    func toggleFolder(_ folderID: UUID) {
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[index].isExpanded.toggle()
    }

    private func pruneEmptyFolders() {
        let valid = Set(games.map(\.id))
        var changed = false
        var cleaned = folders
        for index in cleaned.indices {
            let before = cleaned[index].gameIDs.count
            cleaned[index].gameIDs.removeAll { !valid.contains($0) }
            changed = changed || before != cleaned[index].gameIDs.count
        }
        let nonEmpty = cleaned.filter { !$0.gameIDs.isEmpty }
        if changed || nonEmpty.count != folders.count { folders = nonEmpty }
    }

    // MARK: - Checkbox mode ("폴더 만들기")

    func beginFolderSelection(with gameID: UUID?) {
        checked = gameID.map { [$0] } ?? []
        selectionMode = true
    }

    func toggleChecked(_ gameID: UUID) {
        if checked.contains(gameID) { checked.remove(gameID) } else { checked.insert(gameID) }
    }

    func endFolderSelection() {
        selectionMode = false
        checked = []
    }

    // MARK: - Hiding (secret box)

    func setHidden(_ gameID: UUID, _ hidden: Bool) {
        update(gameID) { $0.isHidden = hidden }
        if hidden {
            removeFromFolder(gameID)
            checked.remove(gameID)
            if selectedID == gameID && !SecretBox.shared.isUnlocked { selectedID = nil }
            showToastMessage("시크릿 박스로 옮겼어요")
        } else {
            if selectedID == gameID && SecretBox.shared.isUnlocked { selectedID = nil }
            showToastMessage("숨기기를 해제했어요")
        }
    }

    // MARK: - Persistence

    static var foldersFile: URL { MiroPaths.libraryFolder.appending(path: "folders.json") }

    func loadFolders() {
        guard let data = try? Data(contentsOf: Self.foldersFile),
              let decoded = try? JSONDecoder().decode([GameFolder].self, from: data) else { return }
        folders = decoded
    }

    func saveFolders() {
        MiroPaths.ensure(MiroPaths.libraryFolder)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(folders) else { return }
        try? data.write(to: Self.foldersFile, options: .atomic)
    }
}
