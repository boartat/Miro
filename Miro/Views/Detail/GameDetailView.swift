//
//  GameDetailView.swift
//  Miro
//
//  Steam-style game page: hero artwork, title, Play button, stats, file location and compatibility.
//

import SwiftUI
import UniformTypeIdentifiers
import WhiskyKit

struct GameDetailView: View {
    let game: Game
    @EnvironmentObject private var library: GameLibrary
    @EnvironmentObject private var installs: InstallCenter
    @State private var report: CompatibilityReport?
    @State private var showSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HeroHeader(game: game)
                ActionBar(game: game, showSettings: $showSettings)
                    .padding(.horizontal, 28)
                    .padding(.top, 4)
                    .padding(.bottom, 20)

                VStack(spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        FileLocationCard(game: game)
                            .frame(maxWidth: .infinity)
                        GameInfoCard(game: game, report: report)
                            .frame(maxWidth: .infinity)
                    }
                    CompatibilityCard(game: game, report: report)
                    if game.lastLogPath != nil {
                        LastRunCard(game: game)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 32)
            }
        }
        .scrollIndicators(.automatic)
        .ignoresSafeArea(edges: .top)
        .task(id: "\(installs.installed.count)-\(game.executablePath)") {
            let snapshot = game
            let installed = installs.installed
            report = await Task.detached(priority: .userInitiated) {
                CompatibilityChecker.check(game: snapshot, installed: installed)
            }.value
        }
        .sheet(isPresented: $showSettings) {
            GameSettingsSheet(game: game)
                .environmentObject(library)
        }
    }
}

// MARK: - Hero

struct HeroHeader: View {
    let game: Game
    @EnvironmentObject private var library: GameLibrary
    @EnvironmentObject private var runtime: RuntimeManager
    @State private var lookingUp = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            artwork
                .frame(height: 360)
                .frame(maxWidth: .infinity)
                .clipped()

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.35),
                    .init(color: Theme.window.opacity(0.75), location: 0.78),
                    .init(color: Theme.window, location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )

            HStack(alignment: .bottom, spacing: 18) {
                GameIconView(game: game, size: 72)
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Badge(text: game.engine.displayName, symbol: game.engine.symbol, tint: .primary)
                        if let arch = game.architecture {
                            Badge(text: arch, symbol: "cpu", tint: .primary)
                        }
                        Badge(text: "Windows 11", symbol: "macwindow", tint: .primary)
                    }
                    Text(game.name)
                        .font(.system(size: 38, weight: .bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 18)
        }
        .frame(height: 360)
        .overlay(alignment: .topTrailing) {
            Menu {
                Button("이미지 선택…") { pickImage() }
                Button("Steam에서 아트워크 찾기") {
                    lookingUp = true
                    Task {
                        await library.fetchArtwork(game.id, force: true)
                        lookingUp = false
                    }
                }
                if game.coverFile != nil {
                    Divider()
                    Button("기본 이미지로 되돌리기") { library.removeCover(game.id) }
                }
            } label: {
                HStack(spacing: 5) {
                    if lookingUp {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "photo")
                    }
                    Text("커버 변경")
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.top, 14)
            .padding(.trailing, 18)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let cover = library.cover(for: game) {
            Image(nsImage: cover)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            GeneratedArtwork(game: game)
        }
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "커버로 쓸 이미지를 선택하세요 (가로로 긴 이미지 권장)"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in GameLibrary.shared.setCover(game.id, imageURL: url) }
        }
    }
}

/// Fallback hero when there is no cover: blurred icon over a tinted gradient
struct GeneratedArtwork: View {
    let game: Game
    @EnvironmentObject private var library: GameLibrary

    var body: some View {
        let tint = GameIconView.tint(for: game.name)
        ZStack {
            LinearGradient(colors: [tint, tint.opacity(0.55), Color(nsColor: .systemIndigo).opacity(0.6)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if let icon = library.icon(for: game) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 70)
                    .opacity(0.8)
                GeometryReader { proxy in
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 220, height: 220)
                        .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
                        .position(x: proxy.size.width - 190, y: proxy.size.height * 0.42)
                }
            } else {
                SparkleField()
                    .foregroundStyle(.white.opacity(0.22))
            }
        }
    }
}

/// Decorative sparkles (same motif as the app icon)
struct SparkleField: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Image(systemName: "sparkle").font(.system(size: 160)).position(x: size.width * 0.78, y: size.height * 0.38)
                Image(systemName: "sparkle").font(.system(size: 54)).position(x: size.width * 0.9, y: size.height * 0.16)
                Image(systemName: "sparkle").font(.system(size: 70)).position(x: size.width * 0.66, y: size.height * 0.62)
            }
        }
    }
}

// MARK: - Play bar

struct ActionBar: View {
    let game: Game
    @Binding var showSettings: Bool
    @EnvironmentObject private var launcher: GameLauncher
    @EnvironmentObject private var runtime: RuntimeManager
    @EnvironmentObject private var library: GameLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                PlayButton(game: game)
                ProfilePicker(game: game)
                Spacer(minLength: 8)
                actions
            }
            HStack(alignment: .center, spacing: 26) {
                VStack(alignment: .leading, spacing: 6) {
                    RetinaToggle(game: game)
                    FullscreenToggle(game: game)
                }
                .frame(width: 168, alignment: .leading)
                DisplayOptions(game: game)
                StatView(label: "마지막 실행", value: Game.relativeDate(game.lastPlayedAt), symbol: "clock")
                StatView(label: "플레이 시간", value: Game.formattedPlayTime(game.playSeconds), symbol: "hourglass")
                Spacer(minLength: 0)
            }
        }
    }

    private var actions: some View {
            HStack(spacing: 8) {
                CircleButton(symbol: "folder", help: "Finder에서 보기") {
                    NSWorkspace.shared.activateFileViewerSelecting([game.executableURL])
                }
                CircleButton(symbol: "gearshape", help: "게임 설정") { showSettings = true }
                Menu {
                    if let path = game.lastLogPath {
                        Button("마지막 실행 로그 보기") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                    }
                    Button("문제 해결 도우미") { launcher.diagnose(game) }
                    Divider()
                    Button("라이브러리에서 제거…", role: .destructive) { library.requestRemove(game.id) }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 32, height: 32)
                        .background(Theme.fill, in: Circle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
    }
}

/// 효율 / 기본 / 성능 boxes next to the Play button
struct ProfilePicker: View {
    let game: Game
    @EnvironmentObject private var library: GameLibrary
    @EnvironmentObject private var launcher: GameLauncher

    var body: some View {
        HStack(spacing: 6) {
            ForEach(PerformanceProfile.allCases) { profile in
                ProfileBox(profile: profile, isSelected: game.profile == profile) {
                    select(profile)
                }
            }
        }
    }

    private func select(_ profile: PerformanceProfile) {
        guard profile != game.profile else { return }
        library.update(game.id) { $0.profile = profile }
        guard launcher.isRunning(game.id), let updated = library.game(game.id) else { return }
        launcher.applyProfile(updated)
        switch profile {
        case .efficiency:
            library.showToastMessage("효율 모드 — 실행 중인 게임에 바로 적용했어요")
        case .balanced:
            library.showToastMessage("기본 모드 — 실행 중인 게임에 바로 적용했어요")
        case .performance:
            library.showToastMessage("성능 모드 — 고성능 코어 설정은 다음 실행부터 완전히 적용돼요")
        }
    }
}

struct ProfileBox: View {
    let profile: PerformanceProfile
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    private var tint: Color {
        switch profile {
        case .efficiency: return Color(nsColor: .systemGreen)
        case .balanced: return Theme.accent
        case .performance: return Color(nsColor: .systemOrange)
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: profile.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(tint)
                    Text(profile.title + " 모드")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                Text(profile.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, 11)
            .frame(width: 108, height: 46, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.14) : (hovering ? Theme.fill : Theme.fill.opacity(0.6)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(isSelected ? tint : Theme.separator.opacity(0.7), lineWidth: isSelected ? 1.5 : 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(profile.detail)
    }
}

/// Retina on/off under the Play button
struct RetinaToggle: View {
    let game: Game
    @EnvironmentObject private var library: GameLibrary
    @EnvironmentObject private var launcher: GameLauncher

    var body: some View {
        Toggle(isOn: Binding(
            get: { game.retina },
            set: { newValue in
                library.update(game.id) { $0.retina = newValue }
                if launcher.isRunning(game.id) {
                    library.showToastMessage("Retina 설정은 다음 실행부터 적용돼요")
                }
            }
        )) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles.tv")
                    .font(.system(size: 11))
                    .foregroundStyle(game.retina ? Theme.accent : Theme.secondaryText)
                Text("Retina 고해상도")
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .help("켜면 화면 원래 해상도로 선명하게, 끄면 해상도가 낮아져 발열·팬 소음이 줄어요")
    }
}

/// 기본 / 꽉 채우기 / FPS next to the Play button
struct DisplayOptions: View {
    let game: Game
    @EnvironmentObject private var library: GameLibrary
    @EnvironmentObject private var launcher: GameLauncher

    var body: some View {
        let canFit = game.fullscreen && FullscreenMode.isSupported(game.engine)
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(DisplayFit.allCases) { fit in
                    OptionPill(title: fit.title,
                               symbol: fit == .fit ? "rectangle.inset.filled" : "arrow.left.and.right.square.fill",
                               isOn: canFit && game.displayFit == fit) {
                        change { $0.displayFit = fit }
                    }
                    .disabled(!canFit)
                    .help(fit == .fit
                          ? "게임 원래 비율 그대로 화면 전체에 띄워요. 비율이 다르면 게임이 위아래(또는 좌우)에 검은 띠를 그려요."
                          : "게임 비율 그대로 화면 높이에 꽉 맞춰 확대해요. 검은 띠가 사라지는 대신 좌우 가장자리가 조금 잘려요. (실험 기능)")
                }
            }
            .padding(2)
            .background(Theme.fill.opacity(0.6), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .opacity(canFit ? 1 : 0.45)

            OptionPill(title: "FPS", symbol: "speedometer", isOn: game.showFPS) {
                change { $0.showFPS.toggle() }
            }
            .padding(2)
            .background(Theme.fill.opacity(0.6), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .help("게임 화면 오른쪽 위에 FPS·GPU 시간(Metal HUD)을 표시해요")
        }
    }

    private func change(_ update: (inout Game) -> Void) {
        library.update(game.id, update)
        if launcher.isRunning(game.id) {
            library.showToastMessage("화면 설정은 다음 실행부터 적용돼요")
        }
    }
}

struct OptionPill: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 11.5, weight: .semibold))
            }
            .padding(.horizontal, 9)
            .frame(height: 26)
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isOn ? Theme.accent : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}

/// 전체 화면 (노치까지) on/off under the Play button
struct FullscreenToggle: View {
    let game: Game
    @EnvironmentObject private var library: GameLibrary
    @EnvironmentObject private var launcher: GameLauncher

    var body: some View {
        let supported = FullscreenMode.isSupported(game.engine)
        let size = FullscreenMode.nativeSize(retina: game.retina)?.text ?? ""
        Toggle(isOn: Binding(
            get: { supported && game.fullscreen },
            set: { newValue in
                library.update(game.id) { $0.fullscreen = newValue }
                if launcher.isRunning(game.id) {
                    library.showToastMessage("전체 화면 설정은 다음 실행부터 적용돼요")
                }
            }
        )) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(supported && game.fullscreen ? Theme.accent : Theme.secondaryText)
                Text("전체 화면 (노치까지)")
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .disabled(!supported)
        .help(supported
              ? "켜면 노치와 Dock 영역까지 꽉 채운 \(size) 해상도로 게임을 실행해요 (테두리 없는 전체 화면). 끄면 창 모드로 실행해요."
              : "\(game.engine.displayName) 게임은 Miro가 화면 모드를 정할 수 없어요. 게임 안 설정에서 전체 화면을 켜면 \(size) 해상도로 채워져요.")
    }
}

struct PlayButton: View {
    let game: Game
    @EnvironmentObject private var launcher: GameLauncher
    @EnvironmentObject private var runtime: RuntimeManager

    var body: some View {
        let running = launcher.isRunning(game.id)
        Button {
            if running { launcher.stop(game) } else { launcher.launch(game) }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: running ? "stop.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                Text(running ? "중지" : launcher.preparing.contains(game.id) ? "준비 중…" : label)
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 26)
            .frame(minWidth: 168, minHeight: 46)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill((running ? Theme.stop : Theme.play).gradient)
            )
            .shadow(color: (running ? Theme.stop : Theme.play).opacity(0.35), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(!running && (!runtime.isReady || !game.exists))
        .opacity(!running && (!runtime.isReady || !game.exists) ? 0.5 : 1)
        .keyboardShortcut(.return, modifiers: .command)
        .help(running ? "게임 중지" : "플레이 (⌘↩)")
    }

    private var label: String {
        if !game.exists { return "파일 없음" }
        if !runtime.isReady { return "설정 필요" }
        return "플레이"
    }
}

struct CircleButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 32, height: 32)
                .background(Theme.fill, in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Cards

struct FileLocationCard: View {
    let game: Game
    @EnvironmentObject private var library: GameLibrary
    @State private var copied = false
    @State private var folderSize: String?

    var body: some View {
        Card("파일 위치", symbol: "folder.fill") {
            fileLocationContent
        }
        .task(id: game.rootFolderURL) {
            guard game.isImported else { return }
            folderSize = nil
            let root = game.rootFolderURL
            let total = await Task.detached(priority: .utility) { FileLocationCard.size(of: root) }.value
            folderSize = total.byteString
        }
    }

    nonisolated static func size(of folder: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(atPath: folder.path(percentEncoded: false)) else { return 0 }
        var total: Int64 = 0
        while enumerator.nextObject() != nil {
            if enumerator.fileAttributes?[.type] as? FileAttributeType == .typeRegular {
                total += (enumerator.fileAttributes?[.size] as? NSNumber)?.int64Value ?? 0
            }
        }
        return total
    }

    private var fileLocationContent: some View {
        Group {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: game.executablePath))
                        .resizable()
                        .frame(width: 22, height: 22)
                    Text(game.fileName)
                        .font(.system(size: 13, weight: .semibold))
                        .textSelection(.enabled)
                    if game.isImported {
                        Label("Miro에 보관됨", systemImage: "tray.full.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                    if !game.exists {
                        Label("찾을 수 없음", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.warning)
                    }
                }
                Text(game.rootFolderURL.abbreviatedPath)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.secondaryText)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                InfoRow(label: "Windows 경로", value: game.executableURL.windowsPath, lineLimit: 2)
                if let source = game.sourcePath {
                    InfoRow(label: "원래 위치", value: URL(fileURLWithPath: source).abbreviatedPath, lineLimit: 2)
                }
                if let size = fileSize {
                    InfoRow(label: "실행 파일 크기", value: size)
                }
                if game.isImported {
                    InfoRow(label: "전체 폴더 크기", value: folderSize ?? "계산 중…")
                }

                HStack(spacing: 8) {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([game.executableURL])
                    } label: {
                        Label("Finder에서 보기", systemImage: "magnifyingglass")
                    }
                    .disabled(!game.exists)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(game.executablePath, forType: .string)
                        copied = true
                    } label: {
                        Label(copied ? "복사됨" : "경로 복사", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    if !game.exists {
                        Button("위치 다시 지정…") { relocate() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .controlSize(.small)
            }
        }
    }

    private var fileSize: String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: game.executablePath),
              let size = attributes[.size] as? Int64 else { return nil }
        return size.byteString
    }

    private func relocate() {
        let panel = NSOpenPanel()
        panel.message = "'\(game.name)'의 실행 파일을 선택하세요"
        panel.allowedContentTypes = [UTType.windowsExecutable].compactMap { $0 }
        panel.allowsOtherFileTypes = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in GameLibrary.shared.relocate(game.id, to: url) }
        }
    }
}

struct GameInfoCard: View {
    let game: Game
    let report: CompatibilityReport?
    @EnvironmentObject private var runtime: RuntimeManager

    var body: some View {
        Card("게임 정보", symbol: "info.circle.fill") {
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "엔진", value: game.engine.displayName)
                InfoRow(label: "아키텍처", value: game.architecture ?? "분석 중…")
                if let info = report?.info, info.isDotNet {
                    InfoRow(label: ".NET", value: info.clrVersion ?? "관리 코드")
                }
                InfoRow(label: "호환 레이어", value: compatibilityLayer)
                InfoRow(label: "언어", value: localeName)
                if !game.arguments.isEmpty {
                    InfoRow(label: "실행 인수", value: game.arguments)
                }
                InfoRow(label: "추가한 날짜", value: game.addedAt.formatted(date: .long, time: .omitted))
            }
        }
    }

    private var compatibilityLayer: String {
        let version = runtime.bottle?.settings.windowsVersion.pretty() ?? "Windows 11"
        let engine = WineEngine.of(EngineManager.shared.engine(for: game))
        let mode = game.winePreference == .auto ? " (자동)" : ""
        return "\(version) · \(engine.title)\(mode)"
    }

    private var localeName: String {
        guard let locale = Locales(rawValue: game.locale), locale != .auto else { return "자동 (시스템 언어)" }
        return locale.pretty()
    }
}

struct LastRunCard: View {
    let game: Game
    @EnvironmentObject private var launcher: GameLauncher

    var body: some View {
        Card("최근 실행", symbol: "clock.arrow.circlepath") {
            HStack(spacing: 12) {
                Image(systemName: game.lastRunSucceeded == false ? "xmark.octagon.fill" : "checkmark.seal.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(game.lastRunSucceeded == false ? Theme.stop : Theme.success)
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.lastRunSucceeded == false ? "마지막 실행이 실패했어요" : "정상적으로 실행되었어요")
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(Game.relativeDate(game.lastPlayedAt)) · 종료 코드 \(game.lastExitCode.map(String.init) ?? "—")")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                if game.lastRunSucceeded == false {
                    Button("문제 해결") { launcher.diagnose(game) }
                        .buttonStyle(.borderedProminent)
                }
                if let path = game.lastLogPath {
                    Button("로그 보기") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                }
            }
            .controlSize(.small)
        }
    }
}
