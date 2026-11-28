//
//  RootView.swift
//  Miro
//

import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var library: GameLibrary
    @EnvironmentObject private var runtime: RuntimeManager
    @EnvironmentObject private var launcher: GameLauncher
    @EnvironmentObject private var secret: SecretBox
    @EnvironmentObject private var steam: SteamAccount
    @AppStorage(OnboardingView.completedKey) private var onboardingCompleted = false
    @State private var isDropTargeted = false
    @State private var setupPostponed = false
    @ObservedObject private var engines = EngineManager.shared

    var body: some View {
        LibraryView()
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        Task { @MainActor in GameLibrary.shared.handle(urls: [url]) }
                    }
                }
                return true
            }
            .overlay {
                if isDropTargeted {
                    DropOverlay()
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .bottom) {
                if let toast = library.toast {
                    ToastView(message: toast)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.15), value: isDropTargeted)
            .animation(.spring(duration: 0.3), value: library.toast)
            .sheet(isPresented: onboardingBinding) {
                OnboardingView { onboardingCompleted = true }
                    .interactiveDismissDisabled()
            }
            .sheet(isPresented: setupBinding) {
                MiroeSetupView(postpone: { setupPostponed = true })
                    .interactiveDismissDisabled()
            }
            .task {
                // Fix prefixes left on Windows 7/XP by earlier library installs
                await runtime.reapplyWindowsVersionIfNeeded()
                // Miro-generated compatibility files need no download — keep them installed
                let installs = InstallCenter.shared
                let missingShims = DependencyCatalog.shims.filter { !installs.isInstalled($0.id) }
                if runtime.isReady && !missingShims.isEmpty { installs.enqueue(missingShims) }
            }
            .sheet(item: $secret.request) { request in
                SecretPasswordSheet(request: request)
                    .environmentObject(secret)
                    .environmentObject(library)
            }
            .onChange(of: secret.isUnlocked) { _, unlocked in
                // Entering or leaving the secret box starts from its own landing page / 홈
                library.selectedID = nil
                if unlocked { library.endFolderSelection() }
            }
            .sheet(item: $library.folderChoice) { choice in
                ExecutablePickerSheet(choice: choice)
                    .environmentObject(library)
            }
            .alert(
                "'\(library.pendingRemoval?.name ?? "")'을(를) 라이브러리에서 제거할까요?",
                isPresented: removalBinding,
                presenting: library.pendingRemoval
            ) { game in
                if game.isImported {
                    Button("게임 파일도 휴지통으로 이동", role: .destructive) {
                        library.remove(game.id, deleteFiles: true)
                    }
                }
                Button(game.isImported ? "목록에서만 제거" : "제거", role: game.isImported ? nil : .destructive) {
                    library.remove(game.id)
                }
                Button("취소", role: .cancel) {}
            } message: { game in
                Text(game.isImported
                     ? "Miro에 복사해 둔 게임 폴더(\(game.rootFolderURL.windowsPath))를 함께 지울 수 있어요. 휴지통에서 되살릴 수 있어요."
                     : "게임 파일은 삭제되지 않아요.")
            }
            .sheet(item: $launcher.failure) { failure in
                TroubleshootSheet(failure: failure)
                    .environmentObject(secret)
                    .environmentObject(library)
                    .environmentObject(InstallCenter.shared)
                    .environmentObject(launcher)
            }
    }

    private var removalBinding: Binding<Bool> {
        Binding(
            get: { library.pendingRemoval != nil },
            set: { if !$0 { library.pendingRemoval = nil } }
        )
    }

    private var onboardingBinding: Binding<Bool> {
        Binding(get: { !onboardingCompleted }, set: { if !$0 { onboardingCompleted = true } })
    }


    /// The engine setup waits until the first-run guide is closed
    private var setupBinding: Binding<Bool> {
        Binding(
            // the first-run setup downloads the miroe engine and makes its prefix; it stays up while that runs (or
            // failed), and does not come for an engine whose prefix is ready
            get: {
                guard onboardingCompleted, !setupPostponed, !engines.isReady(.miroe) else { return false }
                if case .failed = engines.miroeState { return true }
                return !MiroeEngine.isInstalled || engines.miroeState == .installing
            },
            set: { if !$0 { setupPostponed = true } }
        )
    }
}
