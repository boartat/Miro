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
    @State private var executable = ""
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
                    LabeledContent("엔진", value: "miroe")
                    LabeledContent("그래픽", value: "자동 · \(graphicsSummary)")
                    if game.steamAppID != nil {
                        Label("Steam 게임이라 Steam이 직접 실행해요. 실행 옵션은 Steam의 게임 속성에서 바꿔요.", systemImage: "gamecontroller")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondaryText)
                    }
                } header: {
                    Text("호환 엔진")
                } footer: {
                    Text("모든 게임은 miroe 엔진에서 돌고, 그래픽은 게임이 쓰는 DirectX 버전에 맞춰 자동으로 골라요."
                         + (game.architecture == PEInfo.Arch.x86.rawValue && !MiroeEngine.runs32Bit
                            ? " 지금 들어 있는 miroe는 64비트 전용이라 이 32비트 게임은 실행되지 않아요." : ""))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section {
                    Toggle("Mac 원래 해상도로 실행 (Retina)", isOn: Binding(
                        get: { library.game(game.id)?.nativeResolution ?? false },
                        set: { value in library.update(game.id) { $0.nativeResolution = value } }
                    ))
                    if game.steamAppID == nil {
                        Toggle("⌘ 키를 Ctrl처럼 쓰기 (⌘C, ⌘V …)", isOn: Binding(
                            get: { library.game(game.id)?.commandAsCtrl ?? false },
                            set: { value in library.update(game.id) { $0.commandAsCtrl = value } }
                        ))
                    }
                } header: {
                    Text("화면 · 키보드")
                } footer: {
                    Text("기본은 꺼져 있어요: 게임이 예전처럼 Mac 화면 크기에 맞춰 보이고 Wine이 키워서 그려요. 켜면 게임이 Mac의 실제 픽셀로 "
                         + "더 선명하게 그리지만, 게임에 따라 글자나 UI 크기가 달라질 수 있어요. 다음 실행부터 적용돼요. "
                         + "⌘를 Ctrl로 쓰면 일반 프로그램에서 Mac처럼 복사·붙여넣기를 할 수 있어요. Option은 항상 Alt로 동작해요.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
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

    /// What the engine draws this game with, from the DirectX version it uses
    private var graphicsSummary: String {
        switch LaunchPlanner.api(of: game) {
        case .direct3D12, .direct3D11: return "Mullion (DirectX 10~12)"
        case .direct3D9: return "WineD3D (DirectX 9 이하)"
        case .openGL: return "OpenGL"
        case .unknown: return "Mullion · WineD3D"
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
            entry.winePreference = .miroe
            entry.graphicsPreference = .auto
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
