//
//  MiroApp.swift
//  Miro
//
//  Miro — a Windows game & app launcher for macOS, forked from Whisky (GPL-3.0).
//

import SwiftUI
import UniformTypeIdentifiers
import WhiskyKit

@main
struct MiroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var library = GameLibrary.shared
    @StateObject private var runtime = RuntimeManager.shared
    @StateObject private var installs = InstallCenter.shared
    @StateObject private var launcher = GameLauncher.shared
    @StateObject private var secret = SecretBox.shared
    @StateObject private var engines = EngineManager.shared

    var body: some Scene {
        Window("Miro", id: "main") {
            RootView()
                .environmentObject(library)
                .environmentObject(runtime)
                .environmentObject(installs)
                .environmentObject(launcher)
                .environmentObject(secret)
                .environmentObject(engines)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1320, height: 840)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("게임 추가…") { AddGamePanel.present() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .importExport) {
                Button("로그 폴더 열기") {
                    MiroPaths.ensure(MiroPaths.logs)
                    NSWorkspace.shared.open(MiroPaths.logs)
                }
                .keyboardShortcut("l", modifiers: .command)
                Button("가상 C: 드라이브 열기") {
                    NSWorkspace.shared.open(MiroPaths.driveC)
                }
                Button("실행 중인 Windows 프로그램 모두 종료") {
                    AppDelegate.killWine()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Link("Miro 소스 코드", destination: MiroLinks.repository)
                Link("문제 신고하기", destination: MiroLinks.issues)
                Link("오픈소스 고지", destination: MiroLinks.notices)
                Divider()
                Link("Whisky 원본 프로젝트 (GPL-3.0)", destination: URL(string: "https://github.com/Whisky-App/Whisky")!)
                Link("Game Porting Toolkit 빌드 (Gcenx)", destination: URL(string: "https://github.com/Gcenx/game-porting-toolkit")!)
                Link("WineHQ macOS 빌드 (Gcenx, LGPL-2.1)", destination: URL(string: "https://github.com/Gcenx/macOS_Wine_builds")!)
                Link("DXVK-macOS (zlib)", destination: URL(string: "https://github.com/Gcenx/DXVK-macOS")!)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(library)
                .environmentObject(runtime)
                .environmentObject(installs)
                .environmentObject(engines)
        }
    }
}

/// The + button / ⌘O file picker
@MainActor
enum AddGamePanel {
    static func present() {
        let panel = NSOpenPanel()
        panel.title = "게임 추가"
        panel.message = "게임 폴더(폴더째 Miro로 복사) 또는 실행 파일(.exe)을 선택하세요"
        panel.prompt = "추가"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [UTType.windowsExecutable, UTType.windowsInstaller, UTType.windowsBatch].compactMap { $0 }
        panel.allowsOtherFileTypes = true
        panel.begin { response in
            guard response == .OK else { return }
            let urls = panel.urls
            Task { @MainActor in GameLibrary.shared.handle(urls: urls) }
        }
    }
}

extension UTType {
    static let windowsExecutable = UTType(filenameExtension: "exe")
    static let windowsInstaller = UTType(filenameExtension: "msi")
    static let windowsBatch = UTType(filenameExtension: "bat")
}
