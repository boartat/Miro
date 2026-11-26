//
//  TroubleshootSheet.swift
//  Miro
//
//  Shown when a game fails to start: which files are missing, and in-app downloads (with loading bars).
//

import SwiftUI

struct TroubleshootSheet: View {
    let failure: LaunchFailure
    @EnvironmentObject private var library: GameLibrary
    @EnvironmentObject private var installs: InstallCenter
    @EnvironmentObject private var launcher: GameLauncher
    @EnvironmentObject private var engines: EngineManager
    @Environment(\.dismiss) private var dismiss
    @State private var relaunchWhenDone = false

    private var pendingIDs: [String] {
        failure.dependencyIDs.filter { !installs.isInstalled($0, on: failure.engine) }
    }

    /// The fix is another engine that isn't installed yet
    private var needsEngine: Bool {
        failure.suggestedEngine == .modern && !engines.isReady(.modern)
    }

    private var isInstalling: Bool {
        failure.dependencyIDs.contains(where: installs.isActive)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if needsEngine || failure.suggestedEngine == .modern {
                        section("필요한 엔진") {
                            EngineRow(kind: .modern) { switchToModernAndRelaunch() }
                        }
                    }

                    if !failure.missing.isEmpty {
                        section("필요한 파일") {
                            ForEach(failure.missing) { item in
                                if let id = item.dependencyID, let dependency = DependencyCatalog.dependency(id) {
                                    DependencyRow(dependency: dependency, reason: item.file, engine: failure.engine)
                                } else {
                                    manualFileRow(item.file)
                                }
                            }
                        }
                    }

                    let extra = failure.dependencyIDs.filter { id in
                        !failure.missing.contains { $0.dependencyID == id }
                    }
                    if !extra.isEmpty {
                        section("설치를 권장하는 라이브러리") {
                            ForEach(DependencyCatalog.dependencies(extra)) {
                                DependencyRow(dependency: $0, engine: failure.engine)
                            }
                        }
                    }

                    if !failure.hints.isEmpty {
                        section("도움말") {
                            ForEach(failure.hints, id: \.self) { hint in
                                Label(hint, systemImage: "lightbulb")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(24)
            }
            Divider()
            footer
                .padding(16)
        }
        .frame(width: 600, height: 560)
        .onChange(of: installs.isBusy) { _, busy in
            guard !busy, relaunchWhenDone else { return }
            relaunchWhenDone = false
            if let game = library.game(failure.gameID) {
                dismiss()
                launcher.launch(game)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: failure.missing.isEmpty && pendingIDs.isEmpty ? "stethoscope" : "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(failure.missing.isEmpty && pendingIDs.isEmpty ? Theme.accent : Theme.warning)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(failure.title)
                    .font(.system(size: 19, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var subtitle: String {
        var text = failure.gameName
        if let code = failure.exitCode { text += " · 종료 코드 \(code)" }
        if needsEngine {
            text += "\n이 게임은 최신 엔진이 있어야 실행돼요. 아래에서 설치하면 자동으로 다시 실행해요."
        } else if !failure.missing.isEmpty {
            text += "\n아래 파일이 없어서 실행되지 않았어요. 다운로드 버튼을 누르면 Miro가 바로 받아서 설치해요."
        } else if !pendingIDs.isEmpty {
            text += "\n아래 라이브러리를 설치하면 실행될 가능성이 높아요."
        }
        return text
    }

    private var footer: some View {
        HStack {
            if let log = failure.logURL {
                Button("로그 보기") { NSWorkspace.shared.open(log) }
            }
            Spacer()
            Button("닫기") { dismiss() }
                .keyboardShortcut(.cancelAction)
            if let point = failure.restorePoint {
                Button("라이브러리 설치 전으로 되돌리기") {
                    Task {
                        do {
                            try await RestorePoints.restore(point)
                            library.showToastMessage("C: 드라이브를 '\(point.reason)' 상태로 되돌렸어요")
                        } catch {
                            library.showToastMessage("되돌리지 못했어요: \(error.localizedDescription)")
                        }
                        installs.refreshInstalled()
                    }
                    dismiss()
                }
                .disabled(isInstalling)
            }
            if failure.engine == .modern, failure.graphics != .dxvk, engines.offers(.dxvk) {
                // Every automatic choice failed: offer the layer with the widest Direct3D coverage
                Button("DXVK로 다시 실행") { switchGraphicsAndRelaunch(.dxvk) }
                    .disabled(isInstalling)
            }
            if needsEngine {
                Button {
                    Task {
                        await engines.installModern()
                        if engines.isReady(.modern) { switchToModernAndRelaunch() }
                    }
                } label: {
                    if engines.modernState == .installing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("엔진 설치 중 · \(Int(engines.progress * 100))%")
                        }
                    } else {
                        Text("최신 엔진 설치하고 다시 실행")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(engines.modernState == .installing)
            } else if pendingIDs.isEmpty {
                Button("다시 실행") {
                    guard let game = library.game(failure.gameID) else { return }
                    dismiss()
                    launcher.launch(game)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isInstalling)
            } else {
                Button {
                    installs.enqueue(DependencyCatalog.dependencies(pendingIDs), engine: failure.engine)
                    relaunchWhenDone = true
                } label: {
                    if relaunchWhenDone || isInstalling {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("설치 중 · \(Int(installs.progress(of: pendingIDs) * 100))%")
                        }
                    } else {
                        Text("모두 설치하고 다시 실행")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(relaunchWhenDone || isInstalling)
            }
        }
    }

    /// The game now runs on the modern engine (자동 remembers it), then starts again
    private func switchToModernAndRelaunch() {
        library.update(failure.gameID) { entry in
            if entry.winePreference == .classic { entry.winePreference = .auto }
            entry.wineLearned = .modern
        }
        guard let game = library.game(failure.gameID) else { return }
        dismiss()
        launcher.launch(game)
    }

    /// Remembers the graphics choice for this game, then starts it again
    private func switchGraphicsAndRelaunch(_ preference: GraphicsPreference) {
        library.update(failure.gameID) { $0.graphicsPreference = preference }
        guard let game = library.game(failure.gameID) else { return }
        dismiss()
        launcher.launch(game)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            content()
        }
    }

    private func manualFileRow(_ file: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.badge.ellipsis")
                .foregroundStyle(Theme.warning)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(file)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                Text("직접 넣어야 하는 파일 — 게임 폴더에 이 파일이 있어야 해요")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            if let game = library.game(failure.gameID) {
                Button("게임 폴더 열기") { NSWorkspace.shared.open(game.folderURL) }
                    .controlSize(.small)
            }
        }
    }
}
