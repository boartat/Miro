//
//  WhiskyWineInstaller.swift
//  WhiskyKit
//
//  This file is part of Whisky (modified for Miro).
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import Foundation
import SemanticVersion

/// Installs and locates the Wine runtime used by Miro.
///
/// The original Whisky download server (data.getwhisky.app) has been shut down, so Miro
/// installs Gcenx's build of Apple's Game Porting Toolkit (Wine + D3DMetal) from GitHub.
public class WhiskyWineInstaller {
    /// Where the runtime is downloaded from.
    public static let runtimeDownloadURL = URL(
        string: "https://github.com/Gcenx/game-porting-toolkit/releases/download/"
        + "Game-Porting-Toolkit-3.0-3/game-porting-toolkit-3.0-3.tar.xz"
    )!
    /// Version recorded for the runtime above.
    public static let runtimeVersion = SemanticVersion(3, 0, 3)
    /// Human readable runtime name.
    public static let runtimeName = "Game Porting Toolkit 3.0 (Wine + D3DMetal)"

    /// The application support folder
    public static let applicationFolder = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appending(path: Bundle.whiskyBundleIdentifier)

    /// The folder of all the library files
    public static let libraryFolder = applicationFolder.appending(path: "Libraries")

    /// URL to the installed `wine` folder
    public static let wineFolder: URL = libraryFolder.appending(path: "Wine")

    /// URL to the installed `wine` `bin` directory
    public static let binFolder: URL = wineFolder.appending(path: "bin")

    private static var versionPlist: URL {
        libraryFolder.appending(path: "WhiskyWineVersion").appendingPathExtension("plist")
    }

    public static func isWhiskyWineInstalled() -> Bool {
        let wine = binFolder.appending(path: "wine64").path(percentEncoded: false)
        return whiskyWineVersion() != nil && FileManager.default.isExecutableFile(atPath: wine)
    }

    /// Extract a downloaded runtime archive (`.tar.xz` / `.tar.gz`) and install it.
    ///
    /// Supports both the old WhiskyWine layout (`Libraries/Wine/bin/wine64`) and the
    /// Game Porting Toolkit / macOS_Wine_builds layout (`*.app/Contents/Resources/wine`).
    public static func install(from archive: URL) throws {
        let fileManager = FileManager.default
        let staging = applicationFolder.appending(path: "RuntimeStaging")
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        try Tar.untar(tarBall: archive, toURL: staging)
        try? fileManager.removeItem(at: archive)

        guard let wineRoot = findWineRoot(in: staging) else {
            throw "Wine runtime not found inside the downloaded archive"
        }

        try fileManager.createDirectory(at: libraryFolder, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: wineFolder.path(percentEncoded: false)) {
            try fileManager.removeItem(at: wineFolder)
        }
        try fileManager.moveItem(at: wineRoot, to: wineFolder)

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(WhiskyWineVersion(version: runtimeVersion))
        try data.write(to: versionPlist)
    }

    /// Locate a folder that contains `bin/wine64`.
    private static func findWineRoot(in folder: URL) -> URL? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let url as URL in enumerator {
            guard url.lastPathComponent == "wine64",
                  url.deletingLastPathComponent().lastPathComponent == "bin" else { continue }
            return url.deletingLastPathComponent().deletingLastPathComponent()
        }
        return nil
    }

    public static func uninstall() {
        do {
            try FileManager.default.removeItem(at: libraryFolder)
        } catch {
            print("Failed to uninstall runtime: \(error)")
        }
    }

    /// The Whisky update server no longer exists; Miro pins a known-good runtime instead.
    public static func shouldUpdateWhiskyWine() async -> (Bool, SemanticVersion) {
        guard let local = whiskyWineVersion() else { return (false, SemanticVersion(0, 0, 0)) }
        return (local < runtimeVersion, runtimeVersion)
    }

    public static func whiskyWineVersion() -> SemanticVersion? {
        do {
            let data = try Data(contentsOf: versionPlist)
            return try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data).version
        } catch {
            return nil
        }
    }
}

struct WhiskyWineVersion: Codable {
    var version: SemanticVersion = SemanticVersion(1, 0, 0)
}
