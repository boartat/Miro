//
//  GameLauncher.swift
//  Miro
//
//  Starts games with their Wine engine, tracks play time, diagnoses failed launches and — for games on
//  자동 — moves a game to the modern engine by itself when the classic one is missing a Windows function.
//

import AppKit
import Foundation
import WhiskyKit

struct MissingItem: Identifiable, Hashable, Sendable {
    var id: String { file }
    let file: String
    let dependencyID: String?
}

struct LaunchFailure: Identifiable, Sendable {
    let id = UUID()
    let gameID: UUID
    let gameName: String
    let title: String
    let exitCode: Int32?
    let missing: [MissingItem]
    /// Packages to install (from the log + static analysis), in install order
    let dependencyIDs: [String]
    let hints: [String]
    let logURL: URL?
    /// Engine the failed run used (libraries are installed into its prefix)
    var engine: WineEngineKind = .classic
    /// Engine that should fix this failure, when it isn't installed yet
    var suggestedEngine: WineEngineKind?
    /// How the failed run drew Direct3D (modern engine only)
    var graphics: GraphicsBackend?
    /// Saved C: drive from before Miro installed libraries for this game, to undo that install
    var restorePoint: RestorePoint?
}

@MainActor
final class GameLauncher: ObservableObject {
    static let shared = GameLauncher()

    @Published private(set) var running: [UUID: RunningProcess] = [:]
    @Published private(set) var startedAt: [UUID: Date] = [:]
    /// Games whose launch is being prepared (Retina registry switch …)
    @Published private(set) var preparing: Set<UUID> = []
    /// Engine each running game uses
    @Published private(set) var runningEngine: [UUID: WineEngineKind] = [:]
    /// Games the user stopped with 중지 — their exit is not a failed launch
    private var stoppedByUser: Set<UUID> = []
    /// Games whose Wine was stopped by the process-storm guard
    private var stormStopped: Set<UUID> = []
    /// Libraries already installed automatically for each game this session (never tried twice, so no loops)
    private var autoInstalled: [UUID: Set<String>] = [:]
    /// Plans tried since the player pressed 플레이 (automatic retries walk down LaunchPlanner's list)
    private var tried: [UUID: [LaunchPlan]] = [:]
    /// Restore point from before an automatic install for a game, offered if the game still fails
    private var installRestorePoint: [UUID: RestorePoint] = [:]
    @Published var failure: LaunchFailure?
    /// Steam games started through Steam: the game's own process, found after Steam starts it
    @Published private(set) var steamRunning: [UUID: pid_t] = [:]

    private init() {}

    func isRunning(_ id: UUID) -> Bool { running[id] != nil || steamRunning[id] != nil }

    /// The player pressed 플레이: start with the first plan
    func launch(_ game: Game) {
        tried[game.id] = []
        launch(game, plan: nil)
    }

    private func launch(_ game: Game, plan wanted: LaunchPlan?) {
        guard running[game.id] == nil, steamRunning[game.id] == nil, !preparing.contains(game.id) else { return }
        // A Steam game starts the way Steam starts it (its launch options, working folder, environment, DRM),
        // in the prefix where the Steam client lives; the play button looks the same
        if let appID = game.steamAppID, SteamClient.shared.isInstalled {
            launchThroughSteam(game, appID: appID)
            return
        }
        let engines = EngineManager.shared
        guard let plan = wanted ?? LaunchPlanner.plans(for: game).first,
              let bottle = engines.bottle(for: plan.engine) else {
            failure = LaunchFailure(
                gameID: game.id, gameName: game.name, title: "miroe 엔진이 준비되지 않았어요",
                exitCode: nil, missing: [], dependencyIDs: [],
                hints: [MiroeEngine.isInstalled
                        ? "설정 → 호환 레이어에서 miroe의 'Windows 환경 준비'를 눌러 주세요."
                        : "miroe 엔진 파일이 없어요. Scripts/install_miroe_engine.sh로 넣어 주세요."],
                logURL: nil, engine: .miroe)
            return
        }
        guard game.exists else {
            failure = LaunchFailure(
                gameID: game.id, gameName: game.name, title: "실행 파일을 찾을 수 없어요",
                exitCode: nil, missing: [MissingItem(file: game.fileName, dependencyID: nil)], dependencyIDs: [],
                hints: ["파일이 이동되었거나 삭제된 것 같아요: \(game.executableURL.abbreviatedPath)",
                        "게임 설정에서 '위치 다시 지정'으로 새 위치를 알려주세요."],
                logURL: nil, engine: plan.engine)
            return
        }

        if plan.engine == .miroe, game.architecture == PEInfo.Arch.x86.rawValue, !MiroeEngine.runs32Bit {
            failure = LaunchFailure(
                gameID: game.id, gameName: game.name, title: "설치된 miroe 엔진은 32비트 게임을 못 돌려요",
                exitCode: nil, missing: [], dependencyIDs: [],
                hints: ["이 게임은 32비트예요. 지금 들어 있는 miroe는 예전의 64비트 전용 판이에요. Scripts/install_miroe_engine.sh로 서명된 새 판을 넣어 주세요.",
                        "게임 설정에서 엔진을 '자동'으로 바꾸면 기존 엔진으로 실행해요."],
                logURL: nil, engine: .miroe)
            return
        }
        let engine = WineEngine.of(plan.engine)
        if !(tried[game.id] ?? []).contains(plan) { tried[game.id, default: []].append(plan) }
        preparing.insert(game.id)
        Task {
            if plan.engine == .miroe {
                // miroe: Retina at 200 % for the prefix (Steam shares it), this game's DPI flag, the Mac Driver keys
                await EngineManager.shared.updateMiroePrefixIfNeeded()
                await MiroeMigration.prepareDisplay(games: GameLibrary.shared.games, commandAsCtrl: game.commandAsCtrl)
                await CJKFonts.applyIfNeeded(engine: engine, bottle: bottle)
                preparing.remove(game.id)
                start(game, plan: plan, engine: engine, bottle: bottle)
                return
            }
            // Retina is a prefix-wide registry value: switch it to this game's choice before starting
            if RetinaSetting.current(in: engine.bottleURL) != game.retina {
                await engine.setRetina(game.retina, bottle: bottle)
            }
            // display scale is prefix-wide too: this game's choice (only meaningful with Retina)
            let dpi = game.retina ? max(96, 96 * game.uiScale / 100) : 96
            if RetinaSetting.dpi(in: engine.bottleURL) != dpi {
                await engine.setDisplayDPI(dpi, bottle: bottle)
            }
            let keys = RetinaSetting.keyboard(in: engine.bottleURL)
            if keys?.commandIsCtrl != game.commandAsCtrl || keys?.optionIsAlt != true {
                await engine.setKeyboard(commandAsCtrl: game.commandAsCtrl, bottle: bottle)
            }
            await CJKFonts.applyIfNeeded(engine: engine, bottle: bottle)
            if plan.graphics == .dxvk {
                try? await Task.detached(priority: .userInitiated) {
                    try EngineManager.installDXVK(into: engine.bottleURL)
                }.value
            }
            preparing.remove(game.id)
            start(game, plan: plan, engine: engine, bottle: bottle)
        }
    }

    private func start(_ game: Game, plan: LaunchPlan, engine: WineEngine, bottle: Bottle) {
        let graphics = plan.graphics
        var environment = ProcessRunner.baseEnvironment
        environment.merge(engine.environment(for: bottle, graphics: graphics)) { $1 }
        if !game.locale.isEmpty {
            environment["LC_ALL"] = game.locale
            environment["LANG"] = game.locale
        }
        if engine.kind == .classic, bottle.settings.dxvk { try? Wine.enableDXVK(bottle: bottle) }
        MiroPaths.ensure(MiroPaths.shaderCache)

        let path = game.executableURL.path(percentEncoded: false)
        // FPS / GPU time overlay (Metal HUD) per game — overrides the prefix-wide setting
        environment["MTL_HUD_ENABLED"] = game.showFPS ? "1" : "0"
        if let appID = game.steamAppID {
            // tells the game's Steam API which app it is, so it does not restart itself through Steam
            environment["SteamAppId"] = String(appID)
            environment["SteamGameId"] = String(appID)
        }

        // Engine launch arguments for 전체 화면 (노치까지) / 꽉 채우기; the user's own arguments come last and win
        let native = FullscreenMode.nativeSize(retina: game.retina)
        var fill: FullscreenMode.Size?
        if game.fullscreen, game.displayFit == .fill, let native {
            fill = FullscreenMode.fillSize(native: native,
                                           aspect: FullscreenMode.contentAspect(of: game, bottle: bottle.url))
        }
        let displayArguments = FullscreenMode.arguments(
            engine: game.engine, fullscreen: game.fullscreen, fill: fill, native: native,
            windowed: FullscreenMode.windowedSize(retina: game.retina)
        )
        let userArguments = engine.launchArguments(for: game.engine, graphics: graphics) + displayArguments
            + game.arguments.split(whereSeparator: \.isWhitespace).map(String.init)
        let arguments: [String]
        switch game.executableURL.pathExtension.lowercased() {
        case "msi":
            arguments = ["msiexec", "/i", game.executableURL.windowsPath] + userArguments
        case "bat":
            arguments = ["cmd", "/c", game.executableURL.windowsPath] + userArguments
        default:
            arguments = ["start", "/wait", "/d", game.folderURL.windowsPath, "/unix", path] + userArguments
        }

        let safeName = game.name.replacingOccurrences(of: "/", with: "-").prefix(40)
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "-")
        let logURL = MiroPaths.logs.appending(path: "\(safeName) \(stamp).log")

        do {
            let (executable, prefix) = game.profile.wrap(engine.wineBinary)
            let (process, stream) = try ProcessRunner.start(
                executable: executable, arguments: prefix + arguments, environment: environment,
                directory: game.folderURL, logURL: logURL, qualityOfService: game.profile.qualityOfService
            )
            if game.profile == .efficiency {
                // Before start.exe spawns the game, so every child inherits E-core-only scheduling
                ProcessTree.setBackground(true, root: process.process.processIdentifier)
            }
            running[game.id] = process
            runningEngine[game.id] = engine.kind
            if let fill, let native, fill != native, game.engine == .unity {
                centerFillWindow(game, root: process.process.processIdentifier, fill: fill, native: native)
            }
            let start = Date.now
            startedAt[game.id] = start
            GameLibrary.shared.update(game.id) { entry in
                entry.launchCount += 1
                entry.lastPlayedAt = start
                entry.lastLogPath = logURL.path(percentEncoded: false)
            }

            let gameID = game.id
            watchForProcessStorm(gameID, engine: engine)
            Task.detached(priority: .utility) {
                var tail = ""
                var exitCode: Int32 = 0
                for await event in stream {
                    switch event {
                    case .output(let text):
                        tail += text
                        if tail.utf8.count > 400_000 { tail = String(tail.suffix(200_000)) }
                    case .exited(let code):
                        exitCode = code
                    }
                }
                let analysis = LogAnalyzer.analyze(tail)
                await GameLauncher.shared.finished(
                    gameID: gameID, plan: plan, exitCode: exitCode, startedAt: start, analysis: analysis, logURL: logURL
                )
            }
        } catch {
            failure = LaunchFailure(
                gameID: game.id, gameName: game.name, title: "Wine을 시작하지 못했어요",
                exitCode: nil, missing: [], dependencyIDs: [],
                hints: [error.localizedDescription, "설정 → 호환 레이어에서 엔진을 다시 설치해 보세요."],
                logURL: nil, engine: engine.kind)
        }
    }

    /// Stops Wine if it keeps spawning processes (protects the Mac's process table)
    private func watchForProcessStorm(_ gameID: UUID, engine: WineEngine) {
        Task.detached(priority: .utility) {
            while await GameLauncher.shared.isRunning(gameID) {
                try? await Task.sleep(for: .seconds(3))
                if engine.processCount() > ProcessGuard.stormLimit {
                    engine.killAll()
                    await GameLauncher.shared.markStorm(gameID)
                    return
                }
            }
        }
    }

    private func markStorm(_ gameID: UUID) {
        stormStopped.insert(gameID)
        running[gameID]?.terminate()
    }

    /// 꽉 채우기: Unity can't be told where to put its window, so centre it once it appears
    private func centerFillWindow(_ game: Game, root: pid_t, fill: FullscreenMode.Size, native: FullscreenMode.Size) {
        guard let screen = NSScreen.screens.first else { return }
        guard WindowPlacer.isTrusted else {
            WindowPlacer.requestTrust()
            GameLibrary.shared.showToastMessage("꽉 채우기 화면을 가운데에 맞추려면 Miro에 손쉬운 사용 권한을 허용해 주세요")
            return
        }
        let minWidth = screen.frame.width + 1
        let screenRect = CGRect(origin: .zero, size: screen.frame.size)
        let gameID = game.id
        Task {
            for _ in 0..<30 {
                try? await Task.sleep(for: .seconds(1))
                guard isRunning(gameID) else { return }
                let moved = await Task.detached(priority: .userInitiated) {
                    WindowPlacer.centerWideWindow(root: root, minWidth: minWidth, screen: screenRect)
                }.value
                if moved { return }
            }
        }
    }

    /// Applies a changed profile to a running game right away (효율 ↔ 기본/성능)
    func applyProfile(_ game: Game) {
        guard let process = running[game.id], process.isRunning else { return }
        let root = process.process.processIdentifier
        Task.detached(priority: .userInitiated) {
            ProcessTree.setBackground(game.profile == .efficiency, root: root)
        }
    }

    func stop(_ game: Game) {
        stoppedByUser.insert(game.id)
        if let pid = steamRunning[game.id] {
            kill(pid, SIGTERM)
            return
        }
        running[game.id]?.terminate()
        WineEngine.of(runningEngine[game.id] ?? EngineManager.shared.engine(for: game)).killAll()
    }

    // MARK: Steam games

    /// `steam.exe -applaunch <appid>`, then follows the game's own process for 실행 중, 중지 and play time
    private func launchThroughSteam(_ game: Game, appID: Int) {
        preparing.insert(game.id)
        let gameID = game.id
        let exeName = game.executableURL.lastPathComponent.lowercased()
        Task {
            let client = SteamClient.shared
            let steamWasRunning = client.isRunning
            // the game's DPI flag is read when the game starts; Steam must be up before it can start a game
            await MiroeMigration.prepareDisplay(games: GameLibrary.shared.games)
            guard await client.ensureRunning() else {
                preparing.remove(gameID)
                failure = LaunchFailure(
                    gameID: gameID, gameName: game.name, title: "Steam이 켜지지 않았어요",
                    exitCode: nil, missing: [], dependencyIDs: [],
                    hints: ["Steam 게임은 Steam이 켜져 있어야 실행돼요. 'Steam 열기'로 Steam을 먼저 열고 로그인해 주세요."],
                    logURL: nil, engine: .miroe)
                return
            }
            client.start(["-applaunch", String(appID)])
            // Steam may update the game or show a dialog first: wait up to 3 minutes (5 if Steam was just started)
            let deadline = Date.now.addingTimeInterval(steamWasRunning ? 180 : 300)
            var pid: pid_t?
            while pid == nil, Date.now < deadline, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                pid = await Task.detached { ProcessTree.findWindowsProcess(named: exeName) }.value
            }
            preparing.remove(gameID)
            guard let pid else {
                failure = LaunchFailure(
                    gameID: gameID, gameName: game.name, title: "Steam이 게임을 시작하지 않았어요",
                    exitCode: nil, missing: [], dependencyIDs: [],
                    hints: ["Steam 창에 업데이트나 확인 창이 떠 있는지 봐 주세요. Steam 창에서 직접 실행해도 돼요.",
                            "Steam에 로그인돼 있어야 게임을 시작할 수 있어요."],
                    logURL: nil, engine: .miroe)
                return
            }
            let start = Date.now
            steamRunning[gameID] = pid
            startedAt[gameID] = start
            GameLibrary.shared.update(gameID) { entry in
                entry.launchCount += 1
                entry.lastPlayedAt = start
            }
            while kill(pid, 0) == 0 { try? await Task.sleep(for: .seconds(2)) }
            steamRunning[gameID] = nil
            startedAt[gameID] = nil
            stoppedByUser.remove(gameID)
            GameLibrary.shared.update(gameID) { entry in
                entry.playSeconds += Date.now.timeIntervalSince(start)
                entry.lastRunSucceeded = true
                entry.lastExitCode = nil
            }
        }
    }

    private func finished(
        gameID: UUID, plan: LaunchPlan, exitCode: Int32, startedAt start: Date,
        analysis: LogAnalyzer.Result, logURL: URL
    ) async {
        running[gameID] = nil
        startedAt[gameID] = nil
        runningEngine[gameID] = nil
        var analysis = analysis
        if stormStopped.remove(gameID) != nil {
            analysis.processStorm = true
            analysis.hints.append("Wine이 프로그램을 끝없이 다시 띄워서 Miro가 멈췄어요. Mac이 느려지는 걸 막기 위한 안전장치예요.")
        }
        let duration = Date.now.timeIntervalSince(start)
        let quickExit = duration < 12
        let userStopped = stoppedByUser.remove(gameID) != nil
        let failed = !analysis.missingDLLs.isEmpty || analysis.processStorm || analysis.needsNewerEngine
            || (!userStopped && exitCode != 0 && quickExit)
            || (!userStopped && quickExit && analysis.sawErrors)

        GameLibrary.shared.update(gameID) { entry in
            entry.playSeconds += duration
            entry.lastExitCode = exitCode
            entry.lastRunSucceeded = !failed
            // 자동 starts with what worked next time
            if !failed, entry.winePreference == .auto { entry.wineLearned = plan.engine }
            if !failed, entry.graphicsPreference == .auto, let graphics = plan.graphics { entry.graphicsLearned = graphics }
        }
        guard failed, let game = GameLibrary.shared.game(gameID) else {
            tried[gameID] = nil
            installRestorePoint[gameID] = nil
            return
        }

        // Missing DLLs Miro knows a package for: install them into this engine's C: drive and start again
        if await installMissingAndRelaunch(game, plan: plan, analysis: analysis) { return }

        // Another engine or graphics layer next, without asking
        if !userStopped, !analysis.processStorm,
           let next = LaunchPlanner.plans(for: game).first(where: { !(tried[gameID] ?? []).contains($0) }) {
            GameLibrary.shared.update(gameID) { entry in
                if entry.graphicsLearned == plan.graphics { entry.graphicsLearned = nil }
                if entry.wineLearned == plan.engine, plan.engine == .classic { entry.wineLearned = nil }
            }
            GameLibrary.shared.showToastMessage("\(game.name): \(next.title)로 다시 실행할게요")
            if let updated = GameLibrary.shared.game(gameID) { launch(updated, plan: next) }
            return
        }
        tried[gameID] = nil

        var result = await buildFailure(game: game, title: "게임을 실행하지 못했어요", exitCode: exitCode,
                                        analysis: analysis, logURL: logURL, engine: plan.engine, graphics: plan.graphics)
        if analysis.needsNewerEngine, plan.engine == .classic, !EngineManager.shared.isReady(.modern) {
            result.suggestedEngine = .modern
        }
        result.restorePoint = installRestorePoint.removeValue(forKey: gameID)
        failure = result
        NSApp.requestUserAttention(.informationalRequest)
    }

    /// Installs the packages that provide the DLLs a failed run was missing, then relaunches the game.
    /// Returns false when there is nothing new to install or an install failed (the caller shows the sheet).
    private func installMissingAndRelaunch(_ game: Game, plan: LaunchPlan,
                                           analysis: LogAnalyzer.Result) async -> Bool {
        let kind = plan.engine
        // winetricks and the vendor installers are not tried on the experimental ARM64 prefix yet
        guard kind != .miroe else { return false }
        let installs = InstallCenter.shared
        let tried = autoInstalled[game.id] ?? []
        var packages: [Dependency] = []
        for dll in analysis.missingDLLs {
            // Only vetted vendor redistributables install on their own; the rest wait for the player
            guard let package = DependencyCatalog.provider(of: dll), DependencyCatalog.autoInstallIDs.contains(package.id),
                  !tried.contains(package.id),
                  !installs.isInstalled(package.id, on: kind), !packages.contains(where: { $0.id == package.id })
            else { continue }
            packages.append(package)
        }
        guard !packages.isEmpty else { return false }
        autoInstalled[game.id, default: []].formUnion(packages.map(\.id))

        let names = packages.map(\.name).joined(separator: ", ")
        GameLibrary.shared.showToastMessage("\(game.name): 필요한 라이브러리(\(names))를 설치하고 다시 실행할게요")
        let before = installs.lastRestorePoint[kind]
        await installs.installAndWait(packages, engine: kind)
        let point = installs.lastRestorePoint[kind] == before ? nil : installs.lastRestorePoint[kind]
        guard packages.allSatisfy({ installs.isInstalled($0.id, on: kind) }) else {
            // A half-finished install is undone right away
            if let point {
                do {
                    try await RestorePoints.restore(point)
                    GameLibrary.shared.showToastMessage("설치가 끝나지 않아서 C: 드라이브를 설치 전으로 되돌렸어요")
                } catch {
                    GameLibrary.shared.showToastMessage("설치가 끝나지 않았어요. '설정 → 호환 레이어 → 복구 지점'에서 되돌릴 수 있어요")
                }
                installs.refreshInstalled()
            }
            return false
        }
        if let point { installRestorePoint[game.id] = point }
        guard let updated = GameLibrary.shared.game(game.id) else { return false }
        launch(updated, plan: plan)
        return true
    }

    /// "문제 해결 도우미": re-reads the last log and the static analysis for a game
    func diagnose(_ game: Game) {
        Task {
            let logURL = game.lastLogPath.map { URL(fileURLWithPath: $0) }
            let analysis = await Task.detached(priority: .userInitiated) {
                let text = logURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
                return LogAnalyzer.analyze(String(text.suffix(400_000)))
            }.value
            let plan = LaunchPlanner.plans(for: game).first
            let kind = plan?.engine ?? .classic
            let graphics = plan?.graphics
            var result = await buildFailure(game: game, title: "문제 해결 도우미", exitCode: game.lastExitCode,
                                            analysis: analysis, logURL: logURL, engine: kind, graphics: graphics)
            if (analysis.needsNewerEngine || kind == .modern) && !EngineManager.shared.isReady(.modern) {
                result.suggestedEngine = .modern
            }
            failure = result
        }
    }

    private func buildFailure(
        game: Game, title: String, exitCode: Int32?, analysis: LogAnalyzer.Result, logURL: URL?,
        engine: WineEngineKind, graphics: GraphicsBackend? = nil
    ) async -> LaunchFailure {
        // Combine what the log says with what static analysis recommends
        let installed = InstallCenter.shared.installedSet(on: engine)
        let report = await Task.detached(priority: .userInitiated) {
            CompatibilityChecker.check(game: game, installed: installed)
        }.value
        var ids = analysis.dependencyIDs.filter { !installed.contains($0) }
        for id in report.recommendedIDs where !ids.contains(id) { ids.append(id) }

        var missing = analysis.missingDLLs.map {
            MissingItem(file: $0, dependencyID: DependencyCatalog.provider(of: $0)?.id)
        }
        for dll in report.missing where !missing.contains(where: { $0.file.lowercased() == dll.name }) {
            missing.append(MissingItem(file: dll.name, dependencyID: dll.dependencyID))
        }

        var hints = analysis.hints
        hints.append(contentsOf: report.engine.notes)
        if engine == .modern {
            let drawn = graphics ?? .dxvk
            hints.append("이 게임은 최신 엔진(Wine \(ModernEngine.wineVersion) + \(drawn.title))으로 실행했어요. "
                         + "게임 설정에서 엔진을 '클래식'으로 바꿔서 비교해 볼 수 있어요.")
            if drawn == .dxmt {
                hints.append("DXMT는 DirectX 10/11만 그려요. 화면이 안 나오거나 바로 꺼지면 아래 'DXVK로 다시 실행'을 눌러 보세요.")
            }
        }
        if engine == .miroe {
            hints.append("이 게임은 miroe 실험 엔진(ARM64 + FEX + Mullion)으로 실행했어요. 실험 엔진이라 안 되는 게임이 많을 수 있어요. "
                         + "게임 설정에서 엔진을 '자동'으로 바꾸면 기존 엔진으로 돌아가요.")
            hints.append("miroe에서는 필요한 라이브러리를 아직 자동으로 설치하지 않아요.")
        }
        if missing.contains(where: { $0.dependencyID == nil }) {
            hints.append("'직접 넣어야 하는 파일'은 Miro가 받을 수 없는 게임 전용 파일이에요. 게임을 받은 원본 폴더에 있는지 확인해 주세요.")
        }
        if missing.isEmpty && ids.isEmpty && !analysis.needsNewerEngine {
            hints.append("필요한 라이브러리는 모두 준비되어 있어요. 게임 설정에서 언어를 바꾸거나 로그를 확인해 보세요.")
        }
        return LaunchFailure(
            gameID: game.id, gameName: game.name, title: title, exitCode: exitCode,
            missing: missing, dependencyIDs: ids, hints: hints, logURL: logURL, engine: engine, graphics: graphics
        )
    }
}
