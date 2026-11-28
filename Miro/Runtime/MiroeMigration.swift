//
//  MiroeMigration.swift
//  Miro
//
//  Moving to the miroe engine without moving or deleting anything:
//    - Steam: the miroe prefix's "Program Files (x86)\Steam" becomes a link to the Steam folder in the earlier
//      engine's prefix (Miro-CX), so the installed games, downloads and Steam's own settings stay where they are and
//      are used by Steam on miroe. Nothing is copied; removing the link brings the old setup back unchanged.
//    - Save data and settings: AppData (Local, LocalLow, Roaming), Documents and Saved Games of the earlier prefixes
//      are cloned into the miroe prefix's user folder. An APFS clone takes no extra space; anything already there is
//      never overwritten; the originals stay. What was cloned is written to .miro-migration.json in the prefix.
//  The earlier prefixes (Miro, Miro-CX, Miro-W11) are kept as they are.
//
//  The miroe prefix's display: Retina pixels at 200 % (192 DPI) so Steam's window is sharp at its normal size, and
//  each game marked "not DPI-aware" (AppCompatFlags\Layers, matched by executable name) unless it is set to the
//  Mac's own resolution: such a game sees a 96-DPI screen of the Mac's size in points and Wine scales it up,
//  which is how games looked before. Measured on miroe: with the flag a program that asks for per-monitor DPI
//  awareness is refused and sees 96 DPI and 1512x982; without it, 192 DPI and 3024x1964.
//

import Foundation
import WhiskyKit

@MainActor
enum MiroeMigration {
    static var prefix: URL { MiroPaths.miroeBottle }
    static var steamLink: URL { prefix.appending(path: "drive_c/Program Files (x86)/Steam") }
    /// The Steam folder of the earlier engine
    static var previousSteam: URL { MiroPaths.modernBottle.appending(path: "drive_c/Program Files (x86)/Steam") }

    /// Every step; cheap when there is nothing to do
    static func run() async {
        guard EngineManager.shared.isReady(.miroe) else { return }
        await EngineManager.shared.updateMiroePrefixIfNeeded()
        linkSteam()
        await importSteamSettings()
        await cloneUserData()
    }

    /// Steam's own registry values from the earlier prefix (language, the account it signs in automatically, first-run
    /// done …): HKCU\Software\Valve\Steam. Plain values only (ASCII strings, DWORDs); Steam rewrites the rest.
    static func importSteamSettings() async {
        let marker = prefix.appending(path: ".miro-steam-settings-1")
        guard !marker.fileExists, let bottle = EngineManager.shared.bottle(for: .miroe),
              let text = try? String(contentsOf: MiroPaths.modernBottle.appending(path: "user.reg"), encoding: .utf8) else { return }
        let wanted: Set<String> = [#"[Software\\Valve\\Steam]"#, #"[Software\\Valve\\Steamsteamglobal]"#]
        var lines = ["REGEDIT4", ""]
        var inside = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("[") {
                let key = line.split(separator: " ").first.map(String.init) ?? ""
                inside = wanted.contains(key)
                if inside { lines += ["", "[HKEY_CURRENT_USER\\" + key.dropFirst().dropLast().replacingOccurrences(of: #"\\"#, with: #"\"#) + "]"] }
                continue
            }
            guard inside, line.hasPrefix("\""), line.allSatisfy(\.isASCII), !line.contains(#"\x"#) else { continue }
            let value = line.split(separator: "=", maxSplits: 1).last ?? ""
            if value.hasPrefix("\"") || value.hasPrefix("dword:") { lines.append(String(line)) }
        }
        guard lines.count > 3 else { FileManager.default.createFile(atPath: marker.path(percentEncoded: false), contents: Data()); return }
        let file = FileManager.default.temporaryDirectory.appending(path: "miro-steam-\(UUID().uuidString).reg")
        guard (try? (lines.joined(separator: "\r\n") + "\r\n").write(to: file, atomically: true, encoding: .ascii)) != nil else { return }
        defer { try? FileManager.default.removeItem(at: file) }
        if let (status, _) = try? await WineEngine.miroe.run(["regedit", "/S", file.path(percentEncoded: false)], bottle: bottle), status == 0 {
            FileManager.default.createFile(atPath: marker.path(percentEncoded: false), contents: Data())
        }
    }

    // MARK: Steam

    static func linkSteam() {
        let fm = FileManager.default
        let link = steamLink.path(percentEncoded: false)
        // already a folder or a link of its own: leave it
        if fm.fileExists(atPath: link) || (try? fm.destinationOfSymbolicLink(atPath: link)) != nil { return }
        guard previousSteam.appending(path: "steam.exe").fileExists else { return }
        try? fm.createDirectory(at: steamLink.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.createSymbolicLink(at: steamLink, withDestinationURL: previousSteam)
    }

    /// Steam's helper service (installs and updates games; some anti-cheat uses it) lives in the prefix, not in the
    /// Steam folder: a new prefix needs it installed once, or Steam shows "Steam Service Error" behind its window
    static func installSteamService() async {
        let common = prefix.appending(path: "drive_c/Program Files (x86)/Common Files/Steam")
        let installed = ((try? FileManager.default.contentsOfDirectory(atPath: common.path(percentEncoded: false))) ?? [])
            .contains { $0.lowercased() == "steamservice.exe" }
        guard !installed, steamLink.appending(path: "bin/steamservice.exe").fileExists,
              let bottle = EngineManager.shared.bottle(for: .miroe) else { return }
        _ = try? await WineEngine.miroe.run([#"C:\Program Files (x86)\Steam\bin\steamservice.exe"#, "/install"], bottle: bottle)
    }

    // MARK: Save data

    /// Earlier prefixes, newest first (their user folders: the Mac user name, or "crossover" on the older engines)
    private static var previousPrefixes: [URL] { [MiroPaths.modernBottle, MiroPaths.previousModernBottle, MiroPaths.bottle] }
    nonisolated private static let userFolders = ["AppData/Local", "AppData/LocalLow", "AppData/Roaming", "Documents", "Saved Games"]
    /// Wine's and Windows' own folders, not a game's
    nonisolated private static let skipped: Set<String> = ["Temp", "Microsoft", "Packages", "wine", "Wine", "CrashDumps",
                                               "D3DSCache", "desktop.ini", "Desktop.ini"]

    static func cloneUserData() async {
        let marker = prefix.appending(path: ".miro-migrated-1")
        guard !marker.fileExists, let target = miroeUser() else { return }
        let sources = previousPrefixes.flatMap { bottle -> [URL] in
            let users = bottle.appending(path: "drive_c/users")
            let names = (try? FileManager.default.contentsOfDirectory(atPath: users.path(percentEncoded: false))) ?? []
            return names.filter { $0 != "Public" && $0 != "Default" }.map { users.appending(path: $0) }
        }
        let copied: [String] = await Task.detached(priority: .utility) {
            var copied: [String] = []
            let fm = FileManager.default
            for user in sources {
                for folder in userFolders {
                    let from = user.appending(path: folder)
                    // Wine links Documents and the like to the Mac's own folders: those are not prefix data, and
                    // opening one makes macOS ask for folder access (the listing waits for the answer)
                    guard (try? fm.destinationOfSymbolicLink(atPath: from.path(percentEncoded: false))) == nil,
                          (try? fm.destinationOfSymbolicLink(atPath: from.deletingLastPathComponent().path(percentEncoded: false))) == nil,
                          let entries = try? fm.contentsOfDirectory(atPath: from.path(percentEncoded: false)) else { continue }
                    let destination = target.appending(path: folder)
                    for entry in entries where !skipped.contains(entry) && !entry.hasPrefix(".") {
                        let source = from.appending(path: entry)
                        let to = destination.appending(path: entry)
                        // never over what is there; a link (Wine's Documents → Mac folder) is not followed
                        guard !fm.fileExists(atPath: to.path(percentEncoded: false)),
                              (try? fm.destinationOfSymbolicLink(atPath: source.path(percentEncoded: false))) == nil else { continue }
                        try? fm.createDirectory(at: destination, withIntermediateDirectories: true)
                        if (try? fm.copyItem(at: source, to: to)) != nil {
                            copied.append("\(source.path(percentEncoded: false)) -> \(to.path(percentEncoded: false))")
                        }
                    }
                }
            }
            return copied
        }.value
        let record: [String: Any] = ["date": ISO8601DateFormatter().string(from: .now), "cloned": copied]
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted]) {
            try? data.write(to: prefix.appending(path: ".miro-migration.json"))
        }
        FileManager.default.createFile(atPath: marker.path(percentEncoded: false), contents: Data())
    }

    /// The miroe prefix's own user folder (Wine names it after the Mac user)
    private static func miroeUser() -> URL? {
        let users = prefix.appending(path: "drive_c/users")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: users.path(percentEncoded: false))) ?? []
        let mine = NSUserName()
        if names.contains(mine) { return users.appending(path: mine) }
        return names.first { $0 != "Public" && $0 != "Default" && $0 != "crossover" }.map { users.appending(path: $0) }
    }

    // MARK: Display

    /// Retina at 200 % for the whole prefix (Steam), each game's DPI flag, and the Mac Driver keys. Wine reads these
    /// when a program starts, so this runs before Steam or a game starts.
    static func prepareDisplay(games: [Game], commandAsCtrl: Bool? = nil) async {
        let engine = WineEngine.miroe
        guard let bottle = EngineManager.shared.bottle(for: .miroe) else { return }
        var lines = ["Windows Registry Editor Version 5.00", ""]
        if RetinaSetting.current(in: engine.bottleURL) != true {
            lines += [#"[HKEY_CURRENT_USER\Software\Wine\Mac Driver]"#, #""RetinaMode"="y""#, ""]
        }
        if RetinaSetting.dpi(in: engine.bottleURL) != 192 {
            lines += [#"[HKEY_CURRENT_USER\Control Panel\Desktop]"#, #""LogPixels"=dword:000000c0"#, "",
                      #"[HKEY_LOCAL_MACHINE\System\CurrentControlSet\Hardware Profiles\Current\Software\Fonts]"#,
                      #""LogPixels"=dword:000000c0"#, ""]
        }
        // one value per executable name (Wine matches the lower-cased file name); "-" removes it
        var flags: [String: String] = [:]
        for game in games where game.exists || game.steamAppID != nil {
            let name = game.executableURL.lastPathComponent.lowercased()
            guard name.hasSuffix(".exe") else { continue }
            flags[name] = game.nativeResolution ? "-" : "\"~ DPIUNAWARE\""
        }
        let applied = UserDefaults.standard.dictionary(forKey: "miroeDPIFlags") as? [String: String] ?? [:]
        // names no longer in the library lose their flag too
        for name in applied.keys where flags[name] == nil { flags[name] = "-" }
        let wanted = flags.filter { $0.value != "-" }
        if wanted != applied {
            lines += [#"[HKEY_CURRENT_USER\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers]"#]
            lines += flags.sorted { $0.key < $1.key }.map { "\"\($0.key)\"=\($0.value)" }
            lines.append("")
        }
        if let commandAsCtrl {
            let keys = RetinaSetting.keyboard(in: engine.bottleURL)
            if keys?.commandIsCtrl != commandAsCtrl || keys?.optionIsAlt != true {
                let value = commandAsCtrl ? "\"y\"" : "\"n\""
                lines += [#"[HKEY_CURRENT_USER\Software\Wine\Mac Driver]"#,
                          "\"LeftCommandIsCtrl\"=\(value)", "\"RightCommandIsCtrl\"=\(value)",
                          #""LeftOptionIsAlt"="y""#, #""RightOptionIsAlt"="y""#, ""]
            }
        }
        guard lines.count > 2 else { return }
        let file = FileManager.default.temporaryDirectory.appending(path: "miro-display-\(UUID().uuidString).reg")
        var data = Data([0xFF, 0xFE])
        data.append((lines.joined(separator: "\r\n") + "\r\n").data(using: .utf16LittleEndian) ?? Data())
        guard (try? data.write(to: file)) != nil else { return }
        defer { try? FileManager.default.removeItem(at: file) }
        if let (status, _) = try? await engine.run(["regedit", "/S", file.path(percentEncoded: false)], bottle: bottle), status == 0 {
            UserDefaults.standard.set(wanted, forKey: "miroeDPIFlags")
        }
    }
}
