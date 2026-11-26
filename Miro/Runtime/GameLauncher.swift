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
    /// How the failed run drew Direct3D 10/11 (modern engine only)
    var graphics: GraphicsBackend?
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
    @Published var failure: LaunchFailure?

    private init() {}

    func isRunning(_ id: UUID) -> Bool { running[id] != nil }

    /// The player pressed 플레이: start with the first plan
    func launch(_ game: Game) {
        tried[game.id] = []
        launch(game, plan: nil)
    }

    private func launch(_ game: Game, plan wanted: LaunchPlan?) {
        guard running[game.id] == nil, !preparing.contains(game.id) else { return }
        let engines = EngineManager.shared
        guard let plan = wanted ?? LaunchPlanner.plans(for: game).first,
              let bottle = engines.bottle(for: plan.engine) else {
            let needsModern = game.winePreference == .modern || game.wineLearned == .modern
                || !engines.isReady(.classic)
            failure = needsModern && !engines.isReady(.modern)
                ? LaunchFailure(
                    gameID: game.id, gameName: game.name, title: "최신 엔진이 필요해요",
                    exitCode: nil, missing: [], dependencyIDs: [],
                    hints: ["이 게임은 최신 엔진(Wine \(ModernEngine.wineVersion))이 필요해요. "
                            + "아래에서 설치하면 바로 실행돼요 (\(ModernEngine.downloadSize))."],
                    logURL: nil, engine: .modern, suggestedEngine: .modern)
                : LaunchFailure(
                    gameID: game.id, gameName: game.name, title: "Windows 호환 레이어가 아직 준비되지 않았어요",
                    exitCode: nil, missing: [], dependencyIDs: [],
                    hints: ["처음 설정을 완료하면 게임을 실행할 수 있어요."], logURL: nil)
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

        let engine = WineEngine.of(plan.engine)
        if !(tried[game.id] ?? []).contains(plan) { tried[game.id, default: []].append(plan) }
        preparing.insert(game.id)
        Task {
            // Retina is a prefix-wide registry value: switch it to this game's choice before starting
            if RetinaSetting.current(in: engine.bottleURL) != game.retina {
                await engine.setRetina(game.retina, bottle: bottle)
            }
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
        running[game.id]?.terminate()
        WineEngine.of(runningEngine[game.id] ?? EngineManager.shared.engine(for: game)).killAll()
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
        failure = result
        NSApp.requestUserAttention(.informationalRequest)
    }

    /// Installs the packages that provide the DLLs a failed run was missing, then relaunches the game.
    /// Returns false when there is nothing new to install or an install failed (the caller shows the sheet).
    private func installMissingAndRelaunch(_ game: Game, plan: LaunchPlan,
                                           analysis: LogAnalyzer.Result) async -> Bool {
        let kind = plan.engine
        let installs = InstallCenter.shared
        let tried = autoInstalled[game.id] ?? []
        var packages: [Dependency] = []
        for dll in analysis.missingDLLs {
            guard let package = DependencyCatalog.provider(of: dll), !tried.contains(package.id),
                  !installs.isInstalled(package.id, on: kind), !packages.contains(where: { $0.id == package.id })
            else { continue }
            packages.append(package)
        }
        guard !packages.isEmpty else { return false }
        autoInstalled[game.id, default: []].formUnion(packages.map(\.id))

        let names = packages.map(\.name).joined(separator: ", ")
        GameLibrary.shared.showToastMessage("\(game.name): 필요한 라이브러리(\(names))를 설치하고 다시 실행할게요")
        await installs.installAndWait(packages, engine: kind)
        guard packages.allSatisfy({ installs.isInstalled($0.id, on: kind) }),
              let updated = GameLibrary.shared.game(game.id) else { return false }
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
