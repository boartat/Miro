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
            let current = WineEngine.of(game.wineLearned ?? .classic)
            return "지금은 \(current.title)로 실행해요. 클래식 엔진에 없는 Windows 기능을 게임이 부르면 "
                + "Miro가 알아서 최신 엔진으로 바꿔서 다시 실행하고 기억해요."
        case .classic:
            return WineEngine.classic.summary
        case .modern:
            return WineEngine.modern.summary
                + (engines.isReady(.modern) ? "" : " 아직 설치되지 않았어요 — 실행하면 설치 안내가 나와요.")
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
