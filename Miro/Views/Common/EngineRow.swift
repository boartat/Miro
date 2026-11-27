//
//  EngineRow.swift
//  Miro
//
//  One Wine engine with its state; the modern engine can be installed from here (loading bar included).
//

import SwiftUI

struct EngineRow: View {
    let kind: WineEngineKind
    /// Called once the engine finished installing (e.g. relaunch the game that needed it)
    var onInstalled: (() -> Void)?
    @EnvironmentObject private var engines: EngineManager
    @EnvironmentObject private var runtime: RuntimeManager
    @State private var confirmRemove = false
    @State private var showLicense = false

    private var engine: WineEngine { WineEngine.of(kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: kind == .classic ? "cube.fill" : kind == .miroe ? "flask.fill" : "sparkles")
                    .foregroundStyle(Theme.accent)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(engine.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                trailing
            }
            if kind == .modern, engines.modernState == .installing {
                VStack(alignment: .leading, spacing: 3) {
                    ProgressView(value: engines.progress)
                        .progressViewStyle(.linear)
                        .tint(Theme.accent)
                    Text(engines.detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                .padding(.leading, 28)
            }
            if kind == .modern, case .failed(let message) = engines.modernState {
                Text(message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.stop)
                    .lineLimit(3)
                    .padding(.leading, 28)
            }
            if kind == .modern, engines.modernState == .installed {
                graphicsRow
                    .padding(.leading, 28)
            }
            if kind == .miroe {
                miroeDetail
                    .padding(.leading, 28)
            }
        }
        .confirmationDialog("최신 엔진을 삭제할까요?", isPresented: $confirmRemove) {
            Button("삭제", role: .destructive) { engines.uninstallModern() }
        } message: {
            Text("엔진 파일은 지우고, 최신 엔진의 C: 드라이브(세이브 포함)는 휴지통으로 옮겨요. 게임 파일은 그대로예요.")
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if kind == .classic {
            status(runtime.isReady ? "사용 중" : "설치 필요", ok: runtime.isReady)
        } else if kind == .miroe {
            switch engines.miroeState {
            case .installed:
                status("준비됨 · 64비트 전용", ok: true)
            case .installing:
                ProgressView().controlSize(.small)
            case .notInstalled, .failed:
                if MiroeEngine.isInstalled {
                    Button {
                        Task {
                            await engines.prepareMiroe()
                            if engines.isReady(.miroe) { onInstalled?() }
                        }
                    } label: {
                        Text(engines.miroeState == .notInstalled ? "Windows 환경 준비" : "다시 시도")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(Theme.accent)
                } else {
                    status("설치 스크립트 필요", ok: false)
                }
            }
        } else {
            switch engines.modernState {
            case .installed:
                HStack(spacing: 8) {
                    status("설치됨", ok: true)
                    Button("삭제…", role: .destructive) { confirmRemove = true }
                        .controlSize(.small)
                }
            case .installing:
                Text("\(Int(engines.progress * 100))%")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.accent)
            case .notInstalled, .failed:
                Button {
                    Task {
                        await engines.installModern()
                        if engines.isReady(.modern) { onInstalled?() }
                    }
                } label: {
                    Text(engines.modernState == .notInstalled ? "설치 · \(ModernEngine.downloadSize)" : "다시 시도")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Theme.accent)
                .disabled(!runtime.isReady)
            }
        }
    }

    /// What the modern engine can draw with, and the licence D3DMetal needs
    private var graphicsRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("그래픽: DXMT · DXVK · Wine 기본" + (engines.d3dmetalAccepted ? " · D3DMetal" : ""),
                  systemImage: "bolt.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
            if !engines.d3dmetalAccepted {
                HStack(spacing: 8) {
                    Text("DirectX 12 게임에는 Apple D3DMetal이 필요해요. Apple Game Porting Toolkit 라이선스에 동의하면 켜져요.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button {
                        showLicense = true
                    } label: {
                        Text("D3DMetal 켜기…")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(Theme.accent)
                }
            }
        }
        .sheet(isPresented: $showLicense) { D3DMetalLicenseSheet().environmentObject(engines) }
    }

    /// What the experimental engine is and isn't, and its progress
    @ViewBuilder
    private var miroeDetail: some View {
        if engines.miroeState == .installing {
            Text(engines.detail)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
        } else if case .failed(let message) = engines.miroeState {
            Text(message)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.stop)
                .lineLimit(3)
        } else {
            Label("게임 설정 → 호환 엔진에서 게임마다 고를 수 있어요. 자동으로는 쓰지 않아요.", systemImage: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private func status(_ text: String, ok: Bool) -> some View {
        Label(text, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(ok ? Theme.success : Theme.warning)
    }
}
