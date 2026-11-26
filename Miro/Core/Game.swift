//
//  Game.swift
//  Miro
//

import Foundation

/// The engine (or runtime) a game was made with. Used to recommend libraries.
enum GameEngine: String, Codable, Sendable, CaseIterable {
    case unity
    case unreal
    case rpgMaker2000
    case rpgMakerXP
    case rpgMakerVX
    case rpgMakerVXAce
    case rpgMakerMV
    case rpgMakerMZ
    case wolfRPG
    case godot
    case gameMaker
    case renpy
    case kirikiri
    case nwjs
    case electron
    case dotnet
    case xna
    case unknown

    var displayName: String {
        switch self {
        case .unity: return "Unity"
        case .unreal: return "Unreal Engine"
        case .rpgMaker2000: return "RPG Maker 2000/2003 (쯔꾸르)"
        case .rpgMakerXP: return "RPG Maker XP (쯔꾸르)"
        case .rpgMakerVX: return "RPG Maker VX (쯔꾸르)"
        case .rpgMakerVXAce: return "RPG Maker VX Ace (쯔꾸르)"
        case .rpgMakerMV: return "RPG Maker MV (쯔꾸르)"
        case .rpgMakerMZ: return "RPG Maker MZ (쯔꾸르)"
        case .wolfRPG: return "울프 RPG 에디터"
        case .godot: return "Godot"
        case .gameMaker: return "GameMaker"
        case .renpy: return "Ren'Py"
        case .kirikiri: return "KiriKiri (吉里吉里)"
        case .nwjs: return "NW.js"
        case .electron: return "Electron"
        case .dotnet: return ".NET"
        case .xna: return "XNA / MonoGame"
        case .unknown: return "Windows 프로그램"
        }
    }

    var shortName: String {
        switch self {
        case .rpgMaker2000, .rpgMakerXP, .rpgMakerVX, .rpgMakerVXAce, .rpgMakerMV, .rpgMakerMZ:
            return "쯔꾸르"
        case .wolfRPG: return "울프 에디터"
        case .unknown: return "Windows"
        default: return displayName
        }
    }

    var symbol: String {
        switch self {
        case .unity, .unreal, .godot: return "cube.transparent"
        case .rpgMaker2000, .rpgMakerXP, .rpgMakerVX, .rpgMakerVXAce, .rpgMakerMV, .rpgMakerMZ, .wolfRPG:
            return "map"
        case .renpy, .kirikiri: return "text.bubble"
        case .nwjs, .electron: return "globe"
        case .dotnet, .xna: return "chevron.left.forwardslash.chevron.right"
        case .gameMaker: return "gamecontroller"
        case .unknown: return "macwindow"
        }
    }

    /// Games made with these engines are typically Japanese/Korean indie titles
    var isRPGMakerFamily: Bool {
        switch self {
        case .rpgMaker2000, .rpgMakerXP, .rpgMakerVX, .rpgMakerVXAce, .rpgMakerMV, .rpgMakerMZ, .wolfRPG:
            return true
        default:
            return false
        }
    }
}

/// One entry in the Miro library.
struct Game: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var executablePath: String
    var addedAt: Date = .now
    var lastPlayedAt: Date?
    var playSeconds: Double = 0
    var launchCount: Int = 0
    var engine: GameEngine = .unknown
    var architecture: String?
    var coverFile: String?
    var iconFile: String?
    var arguments: String = ""
    /// A `Locales` raw value (e.g. `ja_JP.UTF-8`), empty for automatic
    var locale: String = ""
    var lastExitCode: Int32?
    var lastRunSucceeded: Bool?
    var lastLogPath: String?
    var artworkLookupDone: Bool = false
    /// Folder copied into Miro (C:\Games\…) when the game was added as a folder
    var importedFolder: String?
    /// Where an imported folder originally came from
    var sourcePath: String?
    /// Moved into the password-protected secret box
    var isHidden: Bool = false
    /// Core allocation: 효율 / 기본 / 성능
    var profile: PerformanceProfile = .balanced
    /// Wine Retina mode (full-resolution rendering) for this game
    var retina: Bool = true
    /// Borderless fullscreen at the display's full native size (notch + Dock area included)
    var fullscreen: Bool = true
    /// 기본 (game's own aspect, may letterbox) or 꽉 채우기 (fill the screen, edges cropped)
    var displayFit: DisplayFit = .fit
    /// Metal performance HUD (FPS / GPU time)
    var showFPS: Bool = false
    /// Wine engine chosen in 게임 설정 (자동 / 클래식 / 최신)
    var winePreference: WinePreference = .auto
    /// What 자동 learned for this game, e.g. the classic engine lacked a function it calls → modern
    var wineLearned: WineEngineKind?
    /// How Direct3D 10/11 is drawn on the modern engine (자동 / DXMT / DXVK)
    var graphicsPreference: GraphicsPreference = .auto

    init(name: String, executablePath: String) {
        self.name = name
        self.executablePath = executablePath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Game"
        executablePath = try container.decode(String.self, forKey: .executablePath)
        addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt) ?? .now
        lastPlayedAt = try container.decodeIfPresent(Date.self, forKey: .lastPlayedAt)
        playSeconds = try container.decodeIfPresent(Double.self, forKey: .playSeconds) ?? 0
        launchCount = try container.decodeIfPresent(Int.self, forKey: .launchCount) ?? 0
        engine = (try? container.decodeIfPresent(GameEngine.self, forKey: .engine)) ?? .unknown
        architecture = try container.decodeIfPresent(String.self, forKey: .architecture)
        coverFile = try container.decodeIfPresent(String.self, forKey: .coverFile)
        iconFile = try container.decodeIfPresent(String.self, forKey: .iconFile)
        arguments = try container.decodeIfPresent(String.self, forKey: .arguments) ?? ""
        locale = try container.decodeIfPresent(String.self, forKey: .locale) ?? ""
        lastExitCode = try container.decodeIfPresent(Int32.self, forKey: .lastExitCode)
        lastRunSucceeded = try container.decodeIfPresent(Bool.self, forKey: .lastRunSucceeded)
        lastLogPath = try container.decodeIfPresent(String.self, forKey: .lastLogPath)
        artworkLookupDone = try container.decodeIfPresent(Bool.self, forKey: .artworkLookupDone) ?? false
        importedFolder = try container.decodeIfPresent(String.self, forKey: .importedFolder)
        sourcePath = try container.decodeIfPresent(String.self, forKey: .sourcePath)
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        profile = (try? container.decodeIfPresent(PerformanceProfile.self, forKey: .profile)) ?? .balanced
        retina = try container.decodeIfPresent(Bool.self, forKey: .retina) ?? true
        fullscreen = try container.decodeIfPresent(Bool.self, forKey: .fullscreen) ?? true
        displayFit = (try? container.decodeIfPresent(DisplayFit.self, forKey: .displayFit)) ?? .fit
        showFPS = try container.decodeIfPresent(Bool.self, forKey: .showFPS) ?? false
        winePreference = (try? container.decodeIfPresent(WinePreference.self, forKey: .winePreference)) ?? .auto
        wineLearned = try? container.decodeIfPresent(WineEngineKind.self, forKey: .wineLearned)
        graphicsPreference = (try? container.decodeIfPresent(GraphicsPreference.self, forKey: .graphicsPreference)) ?? .auto
    }

    var executableURL: URL { URL(fileURLWithPath: executablePath) }
    var folderURL: URL { executableURL.deletingLastPathComponent() }
    var fileName: String { executableURL.lastPathComponent }
    var exists: Bool { executableURL.fileExists }
    var isImported: Bool { importedFolder != nil }
    /// The game's root folder: the imported folder, or the exe's folder
    var rootFolderURL: URL { importedFolder.map { URL(fileURLWithPath: $0) } ?? folderURL }

    /// Most recent activity, used by the "최신순" sort
    var recentActivity: Date { max(lastPlayedAt ?? .distantPast, addedAt) }
}

extension Game {
    static let supportedExtensions: Set<String> = ["exe", "msi", "bat", "lnk", "com"]

    static func formattedPlayTime(_ seconds: Double) -> String {
        guard seconds >= 60 else { return seconds > 0 ? "1분 미만" : "기록 없음" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)분" }
        let hours = Double(minutes) / 60
        return hours < 10 ? String(format: "%.1f시간", hours) : "\(Int(hours))시간"
    }

    static func relativeDate(_ date: Date?) -> String {
        guard let date else { return "플레이 안 함" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "오늘" }
        if calendar.isDateInYesterday(date) { return "어제" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = calendar.isDate(date, equalTo: .now, toGranularity: .year) ? "M월 d일" : "yyyy년 M월 d일"
        return formatter.string(from: date)
    }
}
