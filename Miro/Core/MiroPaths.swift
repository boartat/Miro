//
//  MiroPaths.swift
//  Miro
//

import Foundation
import WhiskyKit

/// Every folder Miro reads or writes.
enum MiroPaths {
    /// ~/Library/Application Support/<bundle id>
    static let support = WhiskyWineInstaller.applicationFolder
    /// The game list, covers and icons. `-MiroLibraryFolder <path>` on the command line swaps in another
    /// library (demo screenshots, testing) without touching the real one.
    static let libraryFolder: URL = {
        // Command-line arguments only, so a stray saved preference can never redirect the library
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        if let custom = arguments["MiroLibraryFolder"] as? String, !custom.isEmpty {
            return URL(filePath: custom, directoryHint: .isDirectory)
        }
        return support.appending(path: "Library")
    }()
    static let libraryFile = libraryFolder.appending(path: "games.json")
    static let covers = libraryFolder.appending(path: "Covers")
    static let icons = libraryFolder.appending(path: "Icons")
    static let downloads = support.appending(path: "Downloads")

    /// The Wine runtime (Game Porting Toolkit build)
    static let wineFolder = WhiskyWineInstaller.wineFolder
    static let wineBin = WhiskyWineInstaller.binFolder
    static let winetricks = WhiskyWineInstaller.libraryFolder.appending(path: "winetricks")
    /// Additional Wine engines (Libraries/Engines/<name>) — short paths on purpose, see `ModernEngine.root`
    static let engines = WhiskyWineInstaller.libraryFolder.appending(path: "Engines")
    /// DXVK pipeline caches (kept out of game folders)
    static let shaderCache = support.appending(path: "ShaderCache")

    /// Miro's shared Windows 11 prefix (classic engine)
    static let bottle = BottleData.defaultBottleDir.appending(path: "Miro")
    /// The modern engine's prefix: an APFS clone (of the previous modern prefix, or of `bottle`) whose
    /// C:\Games links back to `bottle`
    static let modernBottle = BottleData.defaultBottleDir.appending(path: "Miro-CX")
    /// Prefix of the modern engine Miro 1.1 used (WineHQ 11.21); the new one starts as a copy of it
    static let previousModernBottle = BottleData.defaultBottleDir.appending(path: "Miro-W11")
    static var driveC: URL { bottle.appending(path: "drive_c") }
    /// Game folders imported into Miro live at C:\Games\<name>
    static var gamesFolder: URL { driveC.appending(path: "Games") }

    static let logs = Wine.logsFolder

    static func ensure(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

extension URL {
    /// `…/drive_c/Games/foo` → `C:\Games\foo`; anything else → `Z:\Users\…` (Wine maps Z: to /)
    var windowsPath: String {
        let path = standardizedFileURL.path(percentEncoded: false)
        var driveC = MiroPaths.driveC.standardizedFileURL.path(percentEncoded: false)
        // Existing directories come back with a trailing slash
        while driveC.hasSuffix("/") { driveC.removeLast() }
        if path == driveC || path.hasPrefix(driveC + "/") {
            let rest = String(path.dropFirst(driveC.count))
            return "C:" + (rest.isEmpty ? "\\" : rest.replacingOccurrences(of: "/", with: "\\"))
        }
        return "Z:" + path.replacingOccurrences(of: "/", with: "\\")
    }

    /// Whether this file lives inside `folder`
    func isInside(_ folder: URL) -> Bool {
        var path = standardizedFileURL.path(percentEncoded: false)
        var root = folder.standardizedFileURL.path(percentEncoded: false)
        while path.hasSuffix("/") { path.removeLast() }
        while root.hasSuffix("/") { root.removeLast() }
        return path == root || path.hasPrefix(root + "/")
    }

    var fileExists: Bool {
        FileManager.default.fileExists(atPath: path(percentEncoded: false))
    }

    /// The path with the home folder abbreviated to `~`
    var abbreviatedPath: String {
        (path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
    }
}
