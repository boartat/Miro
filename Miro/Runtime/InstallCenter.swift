//
//  InstallCenter.swift
//  Miro
//
//  Queues library installs (winetricks verbs or direct installers) into the Windows 11 prefix of a
//  Wine engine and publishes per-package progress for the loading bars.
//

import Foundation
import WhiskyKit

@MainActor
final class InstallCenter: ObservableObject {
    static let shared = InstallCenter()

    enum JobState: Equatable {
        case queued, running, done, failed(String)
    }

    struct Job: Equatable {
        var state: JobState = .queued
        var progress: Double = 0
        var phase: String = "대기 중"
    }

    @Published private(set) var jobs: [String: Job] = [:]
    /// Installed in the classic engine's prefix (the one the library list shows)
    @Published private(set) var installed: Set<String> = []
    /// Installed in the modern engine's prefix
    @Published private(set) var installedModern: Set<String> = []
    @Published private(set) var currentID: String?
    /// Restore point taken before the latest batch of installs, per engine
    @Published private(set) var lastRestorePoint: [WineEngineKind: RestorePoint] = [:]

    private var queue: [(dependency: Dependency, force: Bool, engine: WineEngineKind, restorePoint: Bool)] = []
    private var worker: Task<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private init() {
        refreshInstalled()
    }

    var isBusy: Bool { currentID != nil || !queue.isEmpty }
    var pendingCount: Int { queue.count + (currentID == nil ? 0 : 1) }

    func refreshInstalled() {
        installed = Self.readInstalled(in: WineEngine.classic.bottleURL)
        installedModern = Self.readInstalled(in: WineEngine.modern.bottleURL)
    }

    func isInstalled(_ id: String) -> Bool { installed.contains(id) }

    func isInstalled(_ id: String, on engine: WineEngineKind) -> Bool { installedSet(on: engine).contains(id) }

    func installedSet(on engine: WineEngineKind) -> Set<String> {
        switch engine {
        case .classic: return installed
        case .modern: return installedModern
        case .miroe: return []  // no library installs on the experimental engine yet
        }
    }

    func job(_ id: String) -> Job? { jobs[id] }

    func isActive(_ id: String) -> Bool {
        guard let job = jobs[id] else { return false }
        return job.state == .queued || job.state == .running
    }

    /// Combined progress (0…1) of a set of packages; installed ones count as complete.
    func progress(of ids: [String]) -> Double {
        guard !ids.isEmpty else { return 1 }
        let total = ids.reduce(0.0) { sum, id in
            if let job = jobs[id] {
                switch job.state {
                case .done, .failed: return sum + 1
                case .running: return sum + job.progress
                case .queued: return sum
                }
            }
            return sum + (installed.contains(id) ? 1 : 0)
        }
        return total / Double(ids.count)
    }

    /// Queues installs. With `restorePoint`, the engine's C: drive is saved first (once per batch) so the
    /// change can be undone.
    func enqueue(_ dependencies: [Dependency], force: Bool = false, engine: WineEngineKind = .classic,
                 restorePoint: Bool = true) {
        for dependency in dependencies {
            if isActive(dependency.id) { continue }
            if !force && isInstalled(dependency.id, on: engine) { continue }
            jobs[dependency.id] = Job()
            queue.append((dependency, force, engine, restorePoint))
        }
        startWorkerIfNeeded()
    }

    /// Install and wait until the queue is empty (first-run setup, automatic installs after a failed launch)
    func installAndWait(_ dependencies: [Dependency], engine: WineEngineKind = .classic,
                        restorePoint: Bool = true) async {
        enqueue(dependencies, engine: engine, restorePoint: restorePoint)
        guard isBusy else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func clearFinishedJobs() {
        jobs = jobs.filter { $0.value.state == .queued || $0.value.state == .running }
    }

    private func startWorkerIfNeeded() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            await self?.drain()
        }
    }

    private func drain() async {
        var ranWinetricks: Set<WineEngineKind> = []
        var saved: Set<WineEngineKind> = []
        while !queue.isEmpty {
            let (dependency, force, kind, wantsRestorePoint) = queue.removeFirst()
            if dependency.isWinetricks { ranWinetricks.insert(kind) }
            currentID = dependency.id
            jobs[dependency.id] = Job(state: .running, progress: 0, phase: "준비 중…")

            guard let bottle = EngineManager.shared.bottle(for: kind), WineEngine.of(kind).wineBinary.fileExists else {
                jobs[dependency.id]?.state = .failed(kind == .classic
                    ? "Windows 호환 레이어가 아직 설치되지 않았어요" : "최신 엔진이 아직 설치되지 않았어요")
                continue
            }

            // Save the C: drive once per batch, unless a game is running on it (saving stops Wine)
            if wantsRestorePoint, !saved.contains(kind), WineEngine.of(kind).hasPrefix,
               !GameLauncher.shared.runningEngine.values.contains(kind) {
                saved.insert(kind)
                jobs[dependency.id]?.phase = "설치 전 상태 저장 중…"
                if let point = try? await RestorePoints.create(for: WineEngine.of(kind), reason: "\(dependency.name) 설치 전") {
                    lastRestorePoint[kind] = point
                }
            }

            let id = dependency.id
            let report: @Sendable (Double, String) -> Void = { progress, phase in
                Task { @MainActor in
                    InstallCenter.shared.update(id, progress: progress, phase: phase)
                }
            }
            let result = await Self.perform(
                dependency, engine: WineEngine.of(kind), bottle: bottle, force: force, report: report
            )
            switch result {
            case .success:
                jobs[id] = Job(state: .done, progress: 1, phase: "설치 완료")
            case .failure(let error):
                jobs[id] = Job(state: .failed(error.message), progress: 1, phase: error.message)
            }
            refreshInstalled()
        }
        currentID = nil
        worker = nil
        // .NET installers leave the prefix on Windows 7/XP — restore Windows 11
        if ranWinetricks.contains(.classic) {
            await RuntimeManager.shared.reapplyWindowsVersionIfNeeded()
        }
        if ranWinetricks.contains(.modern), let bottle = EngineManager.shared.bottle(for: .modern) {
            _ = try? await WineEngine.modern.run(["winecfg", "-v", "win11"], bottle: bottle)
        }
        let waiting = waiters
        waiters.removeAll()
        waiting.forEach { $0.resume() }
    }

    private func update(_ id: String, progress: Double, phase: String) {
        guard var job = jobs[id], job.state == .running else { return }
        job.progress = max(job.progress, min(progress, 0.99))
        job.phase = phase
        jobs[id] = job
    }
}

// MARK: - Work (runs off the main actor)

struct InstallError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension InstallCenter {
    nonisolated static func installedListURL(in prefix: URL) -> URL { prefix.appending(path: "miro-installed.txt") }

    nonisolated static func readInstalled(in prefix: URL) -> Set<String> {
        var result = Set<String>()
        for file in [prefix.appending(path: "winetricks.log"), installedListURL(in: prefix)] {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in text.split(whereSeparator: \.isNewline) {
                let verb = line.trimmingCharacters(in: .whitespaces)
                if !verb.isEmpty && !verb.hasPrefix("-") { result.insert(verb) }
            }
        }
        // `d3dx11_43` is recorded under its own name; the catalog ids match winetricks verbs
        return result
    }

    nonisolated static func winetricksEnvironment(engine: WineEngine, bottle: Bottle) -> [String: String] {
        var env = ProcessRunner.baseEnvironment
        env.merge(engine.environment(for: bottle)) { $1 }
        let resources = Bundle.main.resourceURL?.path(percentEncoded: false) ?? ""
        env["PATH"] = "\(engine.binFolder.path(percentEncoded: false)):\(resources):/usr/bin:/bin:/usr/sbin:/sbin"
        env["WINE"] = engine.wineName
        env["WINESERVER"] = "wineserver"
        env["WINEDEBUG"] = "-all"
        env["WINETRICKS_DOWNLOADER"] = "curl"
        env["WINETRICKS_LATEST_VERSION_CHECK"] = "disabled"
        env["W_OPT_UNATTENDED"] = "1"
        return env
    }

    nonisolated static func perform(
        _ dependency: Dependency, engine: WineEngine, bottle: Bottle, force: Bool,
        report: @escaping @Sendable (Double, String) -> Void
    ) async -> Result<Void, InstallError> {
        switch dependency.kind {
        case .winetricks(let verb):
            // Only the pinned, hash-checked winetricks script ever runs
            do {
                try await RuntimeManager.ensureTrustedWinetricks()
            } catch {
                return .failure(InstallError(message: error.localizedDescription))
            }
            return await runWinetricks(verb: verb, name: dependency.name, engine: engine, bottle: bottle,
                                       force: force, report: report)
        case .installer(let url, let isZip):
            return await runInstaller(dependency, url: url, isZip: isZip, engine: engine, bottle: bottle,
                                      report: report)
        case .shim(let fileName, let exports):
            return installShim(dependency, fileName: fileName, exports: exports, engine: engine, report: report)
        }
    }

    /// Writes 64-bit (system32) and 32-bit (syswow64) forwarder DLLs into the prefix
    private nonisolated static func installShim(
        _ dependency: Dependency, fileName: String, exports: [ShimExport], engine: WineEngine,
        report: @escaping @Sendable (Double, String) -> Void
    ) -> Result<Void, InstallError> {
        report(0.3, "\(fileName) 만드는 중…")
        let windows = engine.driveC.appending(path: "windows")
        do {
            for (folder, is64Bit) in [("system32", true), ("syswow64", false)] {
                let directory = windows.appending(path: folder)
                guard directory.fileExists else { continue }
                let data = ShimDLL.forwarder(dllName: fileName, exports: exports, is64Bit: is64Bit)
                try data.write(to: directory.appending(path: fileName), options: .atomic)
            }
            try recordInstalled(dependency.id, in: engine.bottleURL)
            return .success(())
        } catch {
            return .failure(InstallError(message: "호환 파일을 쓰지 못했어요: \(error.localizedDescription)"))
        }
    }

    private nonisolated static func recordInstalled(_ id: String, in prefix: URL) throws {
        let file = installedListURL(in: prefix)
        var list = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        guard !list.split(whereSeparator: \.isNewline).contains(Substring(id)) else { return }
        list += "\(id)\n"
        try list.write(to: file, atomically: true, encoding: .utf8)
    }

    private nonisolated static func runWinetricks(
        verb: String, name: String, engine: WineEngine, bottle: Bottle, force: Bool,
        report: @escaping @Sendable (Double, String) -> Void
    ) async -> Result<Void, InstallError> {
        guard MiroPaths.winetricks.fileExists else {
            return .failure(InstallError(message: "winetricks가 없어요. 설정에서 런타임을 복구해 주세요."))
        }
        var arguments = [MiroPaths.winetricks.path(percentEncoded: false), "-q"]
        if force { arguments.append("--force") }
        arguments.append(verb)

        let logURL = MiroPaths.logs.appending(path: "install-\(verb)-\(Int(Date.now.timeIntervalSince1970)).log")
        report(0.02, "\(name) 준비 중…")
        do {
            let (_, stream) = try ProcessRunner.start(
                executable: URL(fileURLWithPath: "/bin/sh"), arguments: arguments,
                environment: winetricksEnvironment(engine: engine, bottle: bottle), directory: MiroPaths.support,
                logURL: logURL
            )
            var parser = WinetricksProgressParser()
            var exitCode: Int32 = -1
            for await event in stream {
                switch event {
                case .output(let text):
                    for update in parser.consume(text) {
                        report(update.progress, update.phase(name))
                    }
                case .exited(let code):
                    exitCode = code
                }
            }
            if exitCode == 0 {
                return .success(())
            }
            let reason = parser.lastError ?? "winetricks 종료 코드 \(exitCode)"
            return .failure(InstallError(message: "설치 실패: \(reason)"))
        } catch {
            return .failure(InstallError(message: error.localizedDescription))
        }
    }

    private nonisolated static func runInstaller(
        _ dependency: Dependency, url: URL, isZip: Bool, engine: WineEngine, bottle: Bottle,
        report: @escaping @Sendable (Double, String) -> Void
    ) async -> Result<Void, InstallError> {
        let fileManager = FileManager.default
        let archive = MiroPaths.downloads.appending(path: url.lastPathComponent)
        do {
            report(0.01, "\(dependency.name) 다운로드 중…")
            _ = try await Downloader.download(url, to: archive) { fraction, received, total in
                let detail = total > 0 ? " \(received.byteString) / \(total.byteString)" : ""
                report(max(0, fraction) * 0.7, "다운로드 중…\(detail)")
            }

            var installer = archive
            if isZip {
                report(0.72, "압축 해제 중…")
                let folder = MiroPaths.downloads.appending(path: dependency.id)
                try? fileManager.removeItem(at: folder)
                MiroPaths.ensure(folder)
                let (code, output) = try await ProcessRunner.run(
                    executable: URL(fileURLWithPath: "/usr/bin/ditto"),
                    arguments: ["-x", "-k", archive.path(percentEncoded: false), folder.path(percentEncoded: false)],
                    environment: ProcessRunner.baseEnvironment
                )
                guard code == 0 else { return .failure(InstallError(message: "압축 해제 실패: \(output)")) }
                guard let exe = findInstaller(in: folder) else {
                    return .failure(InstallError(message: "설치 프로그램(.exe)을 찾지 못했어요"))
                }
                installer = exe
            }

            report(0.8, "설치 창이 열려요 — 안내에 따라 설치를 완료해 주세요")
            var env = ProcessRunner.baseEnvironment
            env.merge(engine.environment(for: bottle)) { $1 }
            let (code, _) = try await ProcessRunner.run(
                executable: engine.wineBinary,
                arguments: ["start", "/wait", "/unix", installer.path(percentEncoded: false)],
                environment: env, directory: installer.deletingLastPathComponent()
            )
            guard code == 0 else {
                return .failure(InstallError(message: "설치 프로그램이 취소되었거나 실패했어요 (코드 \(code))"))
            }
            try recordInstalled(dependency.id, in: engine.bottleURL)
            return .success(())
        } catch {
            return .failure(InstallError(message: error.localizedDescription))
        }
    }

    private nonisolated static func findInstaller(in folder: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else {
            return nil
        }
        var exes: [URL] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "exe" {
            exes.append(url)
        }
        let preferred = exes.first { url in
            let name = url.lastPathComponent.lowercased()
            return name.contains("setup") || name.contains("install") || name.contains("rtp")
        }
        return preferred ?? exes.first
    }
}

/// Turns winetricks/curl console output into progress updates.
struct WinetricksProgressParser {
    struct Update {
        enum Phase { case preparing, downloading(String), installing, skipped }
        let progress: Double
        let stage: Phase

        func phase(_ name: String) -> String {
            switch stage {
            case .preparing: return "\(name) 준비 중…"
            case .downloading(let file): return "다운로드 중… \(file)"
            case .installing: return "\(name) 설치 중…"
            case .skipped: return "이미 설치되어 있어요"
            }
        }
    }

    private var buffer = ""
    private var currentFile = ""
    private var installSteps = 0
    private(set) var lastError: String?
    private var progress = 0.02

    // "  45 95.6M   45 43.2M    0     0  10.1M      0  0:00:09 ..."
    private static let curlLine = try! NSRegularExpression( // swiftlint:disable:this force_try
        pattern: #"^\s*(\d{1,3})\s+[\d.]+[kMGTP]?\s+\d{1,3}\s+[\d.]+[kMGTP]?\s"#
    )

    mutating func consume(_ chunk: String) -> [Update] {
        buffer += chunk
        var lines = buffer.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
        buffer = lines.removeLast()
        var updates: [Update] = []
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("Downloading ") {
                let parts = line.split(separator: " ")
                if parts.count >= 2 {
                    currentFile = URL(string: String(parts[1]))?.lastPathComponent ?? ""
                }
                progress = max(progress, 0.05)
                updates.append(Update(progress: progress, stage: .downloading(currentFile)))
            } else if let percent = Self.percent(in: line) {
                progress = max(progress, 0.05 + Double(percent) / 100 * 0.65)
                updates.append(Update(progress: progress, stage: .downloading("\(currentFile) \(percent)%")))
            } else if line.hasPrefix("Executing") && !line.hasPrefix("Executing w_do_call")
                        && !line.hasPrefix("Executing load_") {
                installSteps += 1
                progress = max(progress, min(0.95, 0.72 + Double(installSteps) * 0.04))
                updates.append(Update(progress: progress, stage: .installing))
            } else if line.contains("already installed") {
                progress = 0.99
                updates.append(Update(progress: progress, stage: .skipped))
            } else if line.lowercased().contains("error") || line.hasPrefix("warning:") || line.contains("failed") {
                lastError = String(line.prefix(200))
            }
        }
        return updates
    }

    private static func percent(in line: String) -> Int? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = curlLine.firstMatch(in: line, range: range),
              let numberRange = Range(match.range(at: 1), in: line) else { return nil }
        return Int(line[numberRange])
    }
}
