//
//  SettingsView.swift
//  Miro
//

import SwiftUI
import WhiskyKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("일반", systemImage: "gearshape") }
            RuntimeSettings()
                .tabItem { Label("호환 레이어", systemImage: "macwindow") }
            LibrariesSettings()
                .tabItem { Label("라이브러리", systemImage: "shippingbox") }
            AdvancedSettings()
                .tabItem { Label("고급", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 660, height: 560)
    }
}

private struct GeneralSettings: View {
    @AppStorage("autoArtworkLookup") private var autoArtwork = true
    @AppStorage("killOnTerminate") private var killOnTerminate = false

    var body: some View {
        Form {
            Section("라이브러리") {
                Toggle("게임을 추가하면 Steam에서 커버 아트워크 자동 찾기", isOn: $autoArtwork)
                Text("게임 이름만 Steam 상점 검색에 보내요. 이름이 정확히 일치할 때만 적용돼요.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                LabeledContent("데이터 폴더") {
                    Button("Finder에서 열기") {
                        MiroPaths.ensure(MiroPaths.libraryFolder)
                        NSWorkspace.shared.open(MiroPaths.libraryFolder)
                    }
                }
            }
            Section("앱") {
                Toggle("Miro를 종료하면 실행 중인 Windows 프로그램도 종료", isOn: $killOnTerminate)
                LabeledContent("로그") {
                    Button("로그 폴더 열기") {
                        MiroPaths.ensure(MiroPaths.logs)
                        NSWorkspace.shared.open(MiroPaths.logs)
                    }
                }
            }
            Section("정보") {
                LabeledContent("버전", value: MiroLinks.version)
                Text("Miro는 Whisky(GPL-3.0)를 포크해 만든 무료 자유 소프트웨어예요. GNU GPL 3.0 이상에 따라 누구나 나누고 고칠 수 있고, "
                     + "어떠한 보증도 없어요. Wine(LGPL-2.1), Apple Game Porting Toolkit(D3DMetal, Apple 라이선스), "
                     + "DXMT(MIT), DXVK-macOS(zlib), MoltenVK(Apache-2.0), winetricks(LGPL-2.1), cabextract(GPL-3.0)를 사용해요.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    Link("소스 코드", destination: MiroLinks.repository)
                    Link("라이선스 (GPL-3.0)", destination: MiroLinks.license)
                    Link("오픈소스 고지", destination: MiroLinks.notices)
                    Link("문제 신고", destination: MiroLinks.issues)
                    Link("문의 (\(MiroLinks.contactAddress))", destination: MiroLinks.contact)
                }
                .font(.system(size: 11.5))
            }
        }
        .formStyle(.grouped)
    }
}

private struct RuntimeSettings: View {
    @EnvironmentObject private var runtime: RuntimeManager
    @State private var windowsVersion: WinVersion = .win11
    @State private var changingVersion = false
    @State private var confirmReinstall = false

    var body: some View {
        Form {
            Section("상태") {
                LabeledContent("호환 레이어") {
                    Label(runtime.isReady ? "준비됨" : "설치 필요",
                          systemImage: runtime.isReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(runtime.isReady ? Theme.success : Theme.warning)
                }
                LabeledContent("기본 엔진", value: runtime.runtimeDescription)
                LabeledContent("Rosetta 2", value: Rosetta2.isRosettaInstalled ? "설치됨" : "없음")
                LabeledContent("가상 C: 드라이브") {
                    Text(MiroPaths.driveC.abbreviatedPath)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            Section {
                EngineRow(kind: .classic)
                EngineRow(kind: .modern)
                if MiroeEngine.isInstalled {
                    EngineRow(kind: .miroe)
                }
            } header: {
                Text("엔진")
            } footer: {
                Text("기본은 자동이에요. 최신 엔진에서 게임이 쓰는 DirectX 버전에 맞는 그래픽 방식부터 실행하고, 안 되면 다음 방식, "
                     + "그다음 클래식 엔진으로 넘어가요. 게임마다 '게임 설정'에서 엔진과 그래픽을 직접 고를 수도 있어요. "
                     + "두 엔진은 C: 드라이브를 따로 써서 서로 영향을 주지 않아요.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }

            Section {
                Picker("Windows 버전", selection: $windowsVersion) {
                    ForEach(WinVersion.allCases.reversed(), id: \.self) { version in
                        Text(version == .win11 ? "Windows 11 (기본)" : version.pretty()).tag(version)
                    }
                }
                .disabled(runtime.bottle == nil || changingVersion)
                .onChange(of: windowsVersion) { _, newValue in
                    guard newValue != runtime.bottle?.settings.windowsVersion else { return }
                    changingVersion = true
                    Task {
                        await runtime.setWindowsVersion(newValue)
                        changingVersion = false
                    }
                }
            } header: {
                Text("Windows 호환")
            } footer: {
                Text("모든 게임은 Windows 11로 인식되는 환경에서 실행돼요. 아주 오래된 게임이 안 되면 Windows 7/XP로 바꿔보세요.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }

            RestorePointsSection()

            Section("도구") {
                HStack {
                    Button("C: 드라이브 열기") { NSWorkspace.shared.open(MiroPaths.driveC) }
                    Button("winecfg") { run { try await Wine.cfg(bottle: $0) } }
                    Button("레지스트리 편집기") { run { try await Wine.regedit(bottle: $0) } }
                    Button("제어판") { run { try await Wine.control(bottle: $0) } }
                }
                .disabled(runtime.bottle == nil)
                HStack {
                    Button(runtime.isReady ? "설정 다시 실행" : "설치 시작") {
                        Task { await runtime.runSetup() }
                    }
                    .disabled(runtime.isRunningSetup)
                    Button("런타임 재설치…", role: .destructive) { confirmReinstall = true }
                        .disabled(runtime.isRunningSetup)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { windowsVersion = runtime.bottle?.settings.windowsVersion ?? .win11 }
        .confirmationDialog("Wine 런타임을 다시 받을까요?", isPresented: $confirmReinstall) {
            Button("재설치", role: .destructive) {
                WhiskyWineInstaller.uninstall()
                runtime.refresh()
                Task { await runtime.runSetup() }
            }
        } message: {
            Text("약 230MB를 다시 다운로드해요. 게임과 C: 드라이브는 그대로 유지돼요.")
        }
    }

    private func run(_ action: @escaping @MainActor (Bottle) async throws -> Void) {
        guard let bottle = runtime.bottle else { return }
        Task { try? await action(bottle) }
    }
}

private struct LibrariesSettings: View {
    @EnvironmentObject private var installs: InstallCenter
    @EnvironmentObject private var runtime: RuntimeManager

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("게임 라이브러리")
                        .font(.system(size: 15, weight: .semibold))
                    Text("설치됨 \(DependencyCatalog.all.filter { installs.isInstalled($0.id) }.count) / \(DependencyCatalog.all.count)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Button("필수 라이브러리 모두 설치") {
                    installs.enqueue(DependencyCatalog.dependencies(DependencyCatalog.essentialIDs))
                }
                .buttonStyle(.borderedProminent)
                .disabled(!runtime.isReady || installs.isBusy)
            }
            .padding(16)
            Divider()
            List {
                ForEach(Dependency.Category.allCases, id: \.self) { category in
                    Section(category.rawValue) {
                        ForEach(DependencyCatalog.all.filter { $0.category == category }) { dependency in
                            DependencyRow(dependency: dependency)
                                .padding(.vertical, 2)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .disabled(!runtime.isReady)
        }
    }
}

private struct AdvancedSettings: View {
    @EnvironmentObject private var runtime: RuntimeManager

    var body: some View {
        if let bottle = runtime.bottle {
            BottleConfigView(bottle: bottle)
        } else {
            Text("호환 레이어를 먼저 설치해 주세요")
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
