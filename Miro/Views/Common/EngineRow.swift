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

    private var engine: WineEngine { WineEngine.of(kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: kind == .classic ? "cube.fill" : "sparkles")
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

    private func status(_ text: String, ok: Bool) -> some View {
        Label(text, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(ok ? Theme.success : Theme.warning)
    }
}
