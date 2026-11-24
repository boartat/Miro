//
//  EngineDetector.swift
//  Miro
//
//  Guesses the engine and the real title of a game from the files next to its executable.
//

import Foundation

struct EngineInfo: Sendable {
    var engine: GameEngine = .unknown
    var title: String?
    /// Extra advice that can't be fixed by installing a library (e.g. RPG Maker RTP)
    var notes: [String] = []
    /// RTP packages (dependency ids) the game may ask for
    var rtpDependencies: [String] = []
    /// .NET (Core) desktop runtime major version requested by `*.runtimeconfig.json`
    var dotnetCoreMajor: Int?
}

enum EngineDetector {
    private static let genericNames: Set<String> = [
        "game", "rpg_rt", "start", "launcher", "launch", "main", "play", "app", "nw", "index",
        "client", "run", "player", "program", "default", "setup", "config"
    ]

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func detect(executable: URL) -> EngineInfo {
        let folder = executable.deletingLastPathComponent()
        let fileManager = FileManager.default
        let entries = (try? fileManager.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        let lower = Set(entries.map { $0.lowercased() })
        let exeBase = executable.deletingPathExtension().lastPathComponent
        func has(_ name: String) -> Bool { lower.contains(name) }
        func exists(_ relative: String) -> Bool { folder.appending(path: relative).fileExists }
        func hasPrefix(_ prefix: String) -> Bool { lower.contains { $0.hasPrefix(prefix) } }

        var info = EngineInfo()

        if has("unityplayer.dll") || exists("\(exeBase)_Data") {
            info.engine = .unity
            if let appInfo = try? String(contentsOf: folder.appending(path: "\(exeBase)_Data/app.info"), encoding: .utf8) {
                let lines = appInfo.split(whereSeparator: \.isNewline)
                if lines.count >= 2 { info.title = String(lines[1]) }
            }
        } else if executable.path.lowercased().contains("/binaries/win64/")
                    || exeBase.lowercased().hasSuffix("-win64-shipping") || has("engine") {
            info.engine = .unreal
        } else if has("rpg_rt.exe") || has("rpg_rt.ldb") || has("rpg_rt.lmt") {
            info.engine = .rpgMaker2000
            let ini = readINI(folder.appending(path: "RPG_RT.ini"))
            info.title = ini["gametitle"]
            if ini["fullpackageflag"] != "1" {
                info.rtpDependencies = ["rtp2000", "rtp2003"]
                info.notes.append("RPG Maker 2000/2003 게임은 RTP(공용 그래픽·사운드)가 필요할 수 있어요. 글자나 그림이 안 보이면 RTP를 설치하세요.")
            }
        } else if has("game.rgss3a") || hasPrefix("rgss3") || has("game.rgss2a") || hasPrefix("rgss2")
                    || has("game.rgssad") || hasPrefix("rgss1") || has("game.ini") && has("data") && hasPrefix("rgss") {
            let ini = readINI(folder.appending(path: "Game.ini"))
            let library = (ini["library"] ?? "").lowercased()
            if has("game.rgss3a") || hasPrefix("rgss3") || library.contains("rgss3") {
                info.engine = .rpgMakerVXAce
                info.rtpDependencies = ["rtpvxace"]
            } else if has("game.rgss2a") || hasPrefix("rgss2") || library.contains("rgss2") {
                info.engine = .rpgMakerVX
                info.rtpDependencies = ["rtpvx"]
            } else {
                info.engine = .rpgMakerXP
                info.rtpDependencies = ["rtpxp"]
            }
            info.title = ini["title"]
            let rtp = (ini["rtp"] ?? ini["rtp1"] ?? "").trimmingCharacters(in: .whitespaces)
            if rtp.isEmpty {
                info.rtpDependencies = []
            } else {
                info.notes.append("이 게임은 RPG Maker RTP(\(rtp))를 사용해요. 실행 시 리소스 오류가 나면 RTP를 설치하세요.")
            }
        } else if exists("www/js/rpg_core.js") || exists("www/js/rpg_managers.js") {
            info.engine = .rpgMakerMV
            info.title = jsonString(folder.appending(path: "www/data/System.json"), key: "gameTitle")
                ?? packageTitle(folder)
        } else if exists("js/rmmz_core.js") {
            info.engine = .rpgMakerMZ
            info.title = jsonString(folder.appending(path: "data/System.json"), key: "gameTitle")
                ?? packageTitle(folder)
        } else if has("data.wolf") || exists("Data/BasicData") || exists("data/basicdata") || hasPrefix("guruguru") {
            info.engine = .wolfRPG
            info.notes.append("일본어 울프 에디터 게임에서 글자가 깨지면 게임 설정에서 언어를 '日本語'로 바꿔보세요.")
        } else if has("data.win") {
            info.engine = .gameMaker
        } else if has("renpy") || exists("lib/py3-windows-x86_64") || exists("lib/windows-x86_64") {
            info.engine = .renpy
        } else if has("data.xp3") {
            info.engine = .kirikiri
        } else if lower.contains(where: { $0.hasSuffix(".pck") }) {
            info.engine = .godot
        } else if has("resources") && exists("resources/app.asar") {
            info.engine = .electron
        } else if has("nw.dll") || has("nw_elf.dll") {
            info.engine = .nwjs
            info.title = packageTitle(folder)
        } else if has("monogame.framework.dll") || has("fna.dll") || hasPrefix("microsoft.xna.framework") {
            info.engine = .xna
        }

        // .NET (Core) desktop apps
        let runtimeConfig = folder.appending(path: "\(exeBase).runtimeconfig.json")
        if let data = try? Data(contentsOf: runtimeConfig),
           let text = String(data: data, encoding: .utf8),
           let range = text.range(of: #"\"version\"\s*:\s*\"(\d+)\."#, options: .regularExpression) {
            let digits = text[range].filter(\.isNumber)
            info.dotnetCoreMajor = Int(digits)
            if info.engine == .unknown { info.engine = .dotnet }
        }

        if info.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            info.title = nil
        }
        return info
    }

    /// Best human readable name for a game executable
    static func displayName(for executable: URL, detected: EngineInfo) -> String {
        if let title = detected.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        var base = executable.deletingPathExtension().lastPathComponent
        for suffix in ["-Win64-Shipping", "-Win32-Shipping", "_x64", "-x64", "64"] where base.hasSuffix(suffix) {
            base = String(base.dropLast(suffix.count))
            break
        }
        if genericNames.contains(base.lowercased()) || base.count <= 2 {
            var folder = executable.deletingLastPathComponent()
            // Unreal: <Game>/Binaries/Win64/<exe>
            while ["win64", "win32", "binaries", "bin", "x64", "x86"].contains(folder.lastPathComponent.lowercased()) {
                folder.deleteLastPathComponent()
            }
            let folderName = folder.lastPathComponent
            if !folderName.isEmpty && folderName != "/" { return folderName }
        }
        return base
    }

    // MARK: - File helpers

    /// Reads an INI file, trying UTF-8, CP949 (Korean) and Shift-JIS (Japanese)
    static func readINI(_ url: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let text = decodeLegacyText(data)
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if result[key] == nil { result[key] = value }
        }
        return result
    }

    static func decodeLegacyText(_ data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        let korean = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.dosKorean.rawValue)))
        let order: [String.Encoding] = looksLikeKorean(data) ? [korean, .shiftJIS] : [.shiftJIS, korean]
        for encoding in order {
            if let text = String(data: data, encoding: encoding) { return text }
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// CP949 Korean text mostly uses KS X 1001 Hangul (lead 0xB0–0xC8, trail 0xA1–0xFE);
    /// Shift-JIS Japanese decoded as CP949 lands in the rare UHC extension area instead.
    static func looksLikeKorean(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        var standardHangul = 0, extended = 0, kana = 0
        var index = 0
        while index + 1 < bytes.count {
            let lead = bytes[index], trail = bytes[index + 1]
            guard lead >= 0x81 else {
                index += 1
                continue
            }
            if (0xB0...0xC8).contains(lead) && (0xA1...0xFE).contains(trail) { standardHangul += 1 }
            if (0x81...0xC6).contains(lead) && (0x41...0xA0).contains(trail) { extended += 1 }
            if (lead == 0x82 && (0x9F...0xF1).contains(trail)) || (lead == 0x83 && (0x40...0x96).contains(trail)) {
                kana += 1
            }
            index += 2
        }
        return standardHangul > extended && standardHangul >= kana
    }

    private static func jsonString(_ url: URL, key: String) -> String? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object[key] as? String
    }

    private static func packageTitle(_ folder: URL) -> String? {
        for candidate in ["package.json", "www/package.json"] {
            guard let data = try? Data(contentsOf: folder.appending(path: candidate)),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let window = object["window"] as? [String: Any], let title = window["title"] as? String, !title.isEmpty {
                return title
            }
        }
        return nil
    }
}
