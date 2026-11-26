//
//  GameSettingsSheet.swift
//  Miro
//

import SwiftUI
import UniformTypeIdentifiers
import WhiskyKit

struct GameSettingsSheet: View {
    let game: Game
    @EnvironmentObject private var library: GameLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var arguments = ""
    @State private var locale: Locales = .auto
    @State private var winePreference: WinePreference = .auto
    @State private var graphicsPreference: GraphicsPreference = .auto
    @State private var executable = ""
    @EnvironmentObject private var engines: EngineManager
    @State private var candidates: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                GameIconView(game: game, size: 40)
                VStack(alignment: .leading) {
                    Text("게임 설정").font(.system(size: 17, weight: .bold))
                    Text(game.fileName).font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
            }
            .padding(20)

            Form {
                Section {
                    TextField("이름", text: $name)
                    TextField("실행 인수", text: $arguments, prompt: Text("예: -windowed -nosplash"))
                    Picker("언어 (로케일)", selection: $locale) {
                        ForEach(Locales.allCases, id: \.self) { locale in
                            Text(locale == .auto ? "자동 (시스템 언어)" : locale.pretty()).tag(locale)
                        }
                    }
                } footer: {
                    Text("일본 게임에서 글자가 깨지면 언어를 日本語로 바꿔보세요.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }

                Section {
                    Picker("엔진", selection: $winePreference) {
                        ForEach(WinePreference.allCases) { preference in
                            Text(preference.title).tag(preference)
                        }
                    }
                    if winePreference != .classic {
                        Picker("그래픽 (최신 엔진)", selection: $graphicsPreference) {
                            ForEach(GraphicsPreference.allCases) { preference in
                                Text(preference.title).tag(preference)
                            }
                        }
                    }
                } header: {
                    Text("호환 엔진")
                } footer: {
                    Text(engineFooter)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("커버 이미지") {
                    HStack {
                        Button("이미지 선택…") { pickCover() }
                        Button("Steam에서 찾기") {
                            Task { await library.fetchArtwork(game.id, force: true) }
                        }
                        if game.coverFile != nil {
                            Button("기본으로", role: .destructive) { library.removeCover(game.id) }
                        }
                    }
                }

                Section("파일") {
                    if candidates.count > 1 {
                        Picker("실행 파일", selection: $executable) {
                            ForEach(candidates, id: \.self) { path in
                                Text(path).tag(path)
                            }
                        }
                    }
                    LabeledContent("위치") {
                        Text(game.rootFolderURL.abbreviatedPath)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                    HStack {
                        Button("위치 다시 지정…") { relocate() }
                        Button("아이콘·엔진 다시 분석") { library.analyze(game.id) }
                        Spacer()
                        Button("라이브러리에서 제거…", role: .destructive) {
                            dismiss()
                            library.requestRemove(game.id)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("저장") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 540, height: 640)
        .onAppear {
            name = game.name
            arguments = game.arguments
            locale = Locales(rawValue: game.locale) ?? .auto
            winePreference = game.winePreference
            graphicsPreference = game.graphicsPreference
            executable = relativeExecutable
            let root = game.rootFolderURL
            Task.detached(priority: .userInitiated) {
                let found = GameImporter.candidates(in: root)
                await MainActor.run {
                    var list = found
                    if !list.contains(executable) { list.insert(executable, at: 0) }
                    candidates = list
                }
            }
        }
    }

    private var engineFooter: String {
        switch winePreference {
        case .auto:
            let current = LaunchPlanner.plans(for: game).first?.title ?? "엔진 설치 필요"
            return "지금은 \(current)로 시작해요. 실행이 안 되면 Miro가 다른 그래픽 방식이나 엔진으로 "
                + "알아서 바꿔 다시 실행하고, 잘 된 방식을 기억해요." + graphicsFooter
        case .classic:
            return WineEngine.classic.summary
        case .modern:
            return WineEngine.modern.summary
                + (engines.isReady(.modern) ? "" : " 아직 설치되지 않았어요. 실행하면 설치 안내가 나와요.")
                + graphicsFooter
        }
    }

    /// What the graphics choice means on this Mac right now
    private var graphicsFooter: String {
        switch graphicsPreference {
        case .auto:
            return " 그래픽(최신 엔진): 게임이 쓰는 DirectX 버전에 맞춰 효율이 좋은 순서로 고르고, 안 되면 다음 방식으로 넘어가요."
        case .dxmt:
            return " 그래픽: DXMT로 DirectX 10/11을 Metal에 바로 그려요. 가장 가볍고 빨라요."
        case .d3dmetal:
            return engines.d3dmetalAccepted
                ? " 그래픽: Apple D3DMetal로 그려요. DirectX 12 게임에 써요."
                : " 그래픽: D3DMetal은 설정 → 호환 레이어에서 Apple 라이선스에 동의해야 쓸 수 있어요."
        case .dxvk:
            return " 그래픽: DXVK(Vulkan 경유)로 그려요. 다른 방식에서 화면이 깨지는 게임에 써요."
        case .wined3d:
            return " 그래픽: Wine 기본 그래픽으로 그려요. DirectX 9 게임에 잘 맞아요."
        }
    }

    /// The exe path relative to the game's root folder
    private var relativeExecutable: String {
        var root = game.rootFolderURL.standardizedFileURL.path(percentEncoded: false)
        while root.hasSuffix("/") { root.removeLast() }
        let path = game.executableURL.standardizedFileURL.path(percentEncoded: false)
        return path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : game.fileName
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        library.update(game.id) { entry in
            if !trimmed.isEmpty { entry.name = trimmed }
            entry.arguments = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
            entry.locale = locale.rawValue
            entry.graphicsPreference = graphicsPreference
            if entry.winePreference != winePreference {
                entry.winePreference = winePreference
                // A manual choice starts 자동 over from what it learns next
                if winePreference == .auto { entry.wineLearned = nil }
            }
        }
        if !executable.isEmpty && executable != relativeExecutable {
            library.setExecutable(game.id, relativePath: executable)
        }
        dismiss()
    }

    private func pickCover() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in GameLibrary.shared.setCover(game.id, imageURL: url) }
        }
    }

    private func relocate() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.windowsExecutable].compactMap { $0 }
        panel.allowsOtherFileTypes = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in GameLibrary.shared.relocate(game.id, to: url) }
        }
    }
}
