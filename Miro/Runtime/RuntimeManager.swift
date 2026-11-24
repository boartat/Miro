//
//  RuntimeManager.swift
//  Miro
//
//  First-run setup: Rosetta → Wine runtime (GPTK) → winetricks → Windows 11 prefix → libraries.
//

import Foundation
import SemanticVersion
import WhiskyKit

@MainActor
final class RuntimeManager: ObservableObject {
    static let shared = RuntimeManager()

    static let winetricksURL = URL(
        string: "https://raw.githubusercontent.com/Winetricks/winetricks/20260125/src/winetricks"
    )!

    enum Step: Int, CaseIterable, Identifiable {
        case rosetta, runtime, prefix, libraries
        var id: Int { rawValue }

        var title: String {
            switch self {
            case .rosetta: return "Rosetta 2"
            case .runtime: return "Windows 호환 레이어"
            case .prefix: return "Windows 11 환경 만들기"
            case .libraries: return "게임 라이브러리 설치"
            }
        }

        var subtitle: String {
            switch self {
            case .rosetta: return "Intel용 Windows 코드를 Apple 실리콘에서 실행해요"
            case .runtime: return "Wine 7.7 + D3DMetal (Game Porting Toolkit 3.0) · 약 230MB"
            case .prefix: return "게임이 설치될 가상 C: 드라이브를 Windows 11로 설정해요"
            case .libraries: return "Visual C++, DirectX, XAudio, PhysX, 한국어·일본어 글꼴 …"
            }
        }
    }

    enum StepState: Equatable {
        case pending, running, done, failed(String)
    }

    @Published private(set) var bottle: Bottle?
    @Published private(set) var isReady = false
    @Published private(set) var isRunningSetup = false
    @Published private(set) var states: [Step: StepState] = [:]
    @Published private(set) var stepProgress: [Step: Double] = [:]
    @Published private(set) var stepDetail: [Step: String] = [:]
    @Published var includeExtras = false

    private init() {
        refresh()
    }

    var runtimeDescription: String {
        let version = WhiskyWineInstaller.whiskyWineVersion().map { "\($0.major).\($0.minor).\($0.patch)" } ?? "—"
        return "Game Porting Toolkit \(version) · Wine 7.7 + D3DMetal"
    }

    var libraryIDs: [String] {
        DependencyCatalog.essentialIDs + (includeExtras ? DependencyCatalog.extraIDs : [])
    }

    func refresh() {
        let runtime = WhiskyWineInstaller.isWhiskyWineInstalled()
        let prefixReady = MiroPaths.bottle.appending(path: "system.reg").fileExists
        if prefixReady, bottle == nil {
            bottle = Bottle(bottleUrl: MiroPaths.bottle, isAvailable: true)
        }
        isReady = runtime && prefixReady && MiroPaths.winetricks.fileExists

        states[.rosetta] = Rosetta2.isRosettaInstalled ? .done : .pending
        states[.runtime] = runtime ? .done : .pending
        states[.prefix] = prefixReady ? .done : .pending
        let libraries = DependencyCatalog.essentialIDs
        states[.libraries] = libraries.allSatisfy(InstallCenter.shared.isInstalled) ? .done : .pending
    }

    func state(_ step: Step) -> StepState { states[step] ?? .pending }

    /// Runs every missing step. Safe to call again after a failure.
    func runSetup() async {
        guard !isRunningSetup else { return }
        isRunningSetup = true
        defer {
            isRunningSetup = false
            refresh()
        }

        do {
            try await ensureRosetta()
            try await ensureRuntime()
            try await ensureWinetricks()
            try await ensurePrefix()
            isReady = true
            await installLibraries()
        } catch {
            for step in Step.allCases where states[step] == .running {
                states[step] = .failed(error.localizedDescription)
            }
        }
    }

    private func ensureRosetta() async throws {
        guard !Rosetta2.isRosettaInstalled else {
            states[.rosetta] = .done
            return
        }
        states[.rosetta] = .running
        stepDetail[.rosetta] = "Rosetta 2 설치 중… (관리자 암호를 물어볼 수 있어요)"
        let installed = try await Rosetta2.installRosetta()
        guard installed else { throw InstallError(message: "Rosetta 2를 설치하지 못했어요") }
        states[.rosetta] = .done
    }

    private func ensureRuntime() async throws {
        guard !WhiskyWineInstaller.isWhiskyWineInstalled() else {
            states[.runtime] = .done
            return
        }
        states[.runtime] = .running
        stepProgress[.runtime] = 0
        stepDetail[.runtime] = "다운로드 준비 중…"
        let archive = MiroPaths.downloads.appending(path: WhiskyWineInstaller.runtimeDownloadURL.lastPathComponent)
        _ = try await Downloader.download(WhiskyWineInstaller.runtimeDownloadURL, to: archive) { fraction, received, total in
            Task { @MainActor in
                let manager = RuntimeManager.shared
                manager.stepProgress[.runtime] = max(0, fraction) * 0.85
                manager.stepDetail[.runtime] = total > 0
                    ? "다운로드 중… \(received.byteString) / \(total.byteString)"
                    : "다운로드 중… \(received.byteString)"
            }
        }
        stepProgress[.runtime] = 0.86
        stepDetail[.runtime] = "압축 해제 및 설치 중… (1분 정도 걸려요)"
        try await Task.detached(priority: .userInitiated) {
            try WhiskyWineInstaller.install(from: archive)
        }.value
        stepProgress[.runtime] = 1
        states[.runtime] = .done
    }

    private func ensureWinetricks() async throws {
        guard !MiroPaths.winetricks.fileExists else { return }
        stepDetail[.prefix] = "winetricks 받는 중…"
        _ = try await Downloader.download(Self.winetricksURL, to: MiroPaths.winetricks) { _, _, _ in }
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: MiroPaths.winetricks.path(percentEncoded: false))
    }

    private func ensurePrefix() async throws {
        if MiroPaths.bottle.appending(path: "system.reg").fileExists {
            if bottle == nil { bottle = Bottle(bottleUrl: MiroPaths.bottle, isAvailable: true) }
            states[.prefix] = .done
            return
        }
        states[.prefix] = .running
        stepProgress[.prefix] = 0.1
        stepDetail[.prefix] = "가상 C: 드라이브 만드는 중… (처음 한 번은 1~2분 걸려요)"
        MiroPaths.ensure(MiroPaths.bottle)
        let newBottle = Bottle(bottleUrl: MiroPaths.bottle, isAvailable: true)
        newBottle.settings.name = "Miro"
        newBottle.settings.windowsVersion = .win11

        try await Wine.changeWinVersion(bottle: newBottle, win: .win11)
        stepProgress[.prefix] = 0.8
        stepDetail[.prefix] = "Windows 11로 설정하는 중…"
        if let version = try? await Wine.wineVersion() {
            newBottle.settings.wineVersion = SemanticVersion(version) ?? newBottle.settings.wineVersion
        }
        guard MiroPaths.bottle.appending(path: "system.reg").fileExists else {
            throw InstallError(message: "Windows 환경을 만들지 못했어요. 로그를 확인해 주세요.")
        }
        bottle = newBottle
        stepProgress[.prefix] = 1
        states[.prefix] = .done
    }

    private func installLibraries() async {
        let center = InstallCenter.shared
        let wanted = DependencyCatalog.dependencies(libraryIDs).filter { !center.isInstalled($0.id) }
        guard !wanted.isEmpty else {
            states[.libraries] = .done
            return
        }
        states[.libraries] = .running
        await center.installAndWait(wanted)
        let failed = wanted.filter { !center.isInstalled($0.id) }
        states[.libraries] = failed.isEmpty
            ? .done
            : .failed("\(failed.count)개 설치 실패: \(failed.map(\.name).joined(separator: ", "))")
    }

    /// Some winetricks verbs (dotnet40/dotnet48 …) switch the prefix to Windows 7/XP and leave it there.
    /// Reads the build number from the prefix registry and puts the chosen version (Windows 11) back.
    func reapplyWindowsVersionIfNeeded() async {
        guard isReady, let bottle, !InstallCenter.shared.isBusy else { return }
        let wanted = bottle.settings.windowsVersion
        let registry = MiroPaths.bottle.appending(path: "system.reg")
        let build = await Task.detached(priority: .utility) { Self.currentBuild(in: registry) }.value
        guard let build, !Self.build(build, matches: wanted) else { return }
        do {
            try await Wine.changeWinVersion(bottle: bottle, win: wanted)
        } catch {
            print("Failed to restore Windows version: \(error)")
        }
    }

    /// `CurrentBuild` under HKLM\Software\Microsoft\Windows NT\CurrentVersion
    nonisolated static func currentBuild(in registry: URL) -> Int? {
        guard let data = try? Data(contentsOf: registry) else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        guard let section = text.range(of: "[Software\\\\Microsoft\\\\Windows NT\\\\CurrentVersion]"),
              let key = text.range(of: "\"CurrentBuild\"=\"", range: section.upperBound..<text.endIndex) else {
            return nil
        }
        let digits = text[key.upperBound...].prefix { $0.isNumber }
        return Int(digits)
    }

    nonisolated static func build(_ build: Int, matches version: WinVersion) -> Bool {
        switch version {
        case .win11: return build >= 22000
        case .win10: return (10240..<22000).contains(build)
        case .win81: return build == 9600
        case .win8: return build == 9200
        case .win7: return (7600...7601).contains(build)
        case .winXP: return (2600...3790).contains(build)
        }
    }

    /// Changes the Windows version of the shared prefix (default: Windows 11)
    func setWindowsVersion(_ version: WinVersion) async {
        guard let bottle else { return }
        do {
            try await Wine.changeWinVersion(bottle: bottle, win: version)
            bottle.settings.windowsVersion = version
            objectWillChange.send()
        } catch {
            print("Failed to change Windows version: \(error)")
        }
    }
}
