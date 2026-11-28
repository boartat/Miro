//
//  MiroeSetupView.swift
//  Miro
//
//  First run: downloads the miroe engine (ARM64 Wine + FEX, Mullion) and makes its Windows environment.
//

import SwiftUI

struct MiroeSetupView: View {
    var postpone: () -> Void
    @ObservedObject private var engines = EngineManager.shared

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 84, height: 84)
                Text("Miro에 오신 것을 환영해요")
                    .font(.system(size: 24, weight: .bold))
                Text("Windows 게임을 돌리는 miroe 엔진을 받아서 Windows 환경을 만들게요.\n한 번만 하면 돼요.")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.top, 28)
            .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 14) {
                    icon.frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("miroe 엔진")
                            .font(.system(size: 13.5, weight: .semibold))
                        Text("Apple 실리콘에서 바로 도는 Wine · DirectX 10–12는 Metal로 · x86 프로그램은 FEX로 (\(MiroeEngine.downloadSize))")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        if engines.miroeState == .installing {
                            ProgressView(value: engines.progress)
                                .progressViewStyle(.linear)
                                .tint(Theme.accent)
                                .padding(.top, 4)
                            Text(engines.detail)
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                        }
                        if case .failed(let message) = engines.miroeState {
                            Text(message)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.stop)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !MiroeEngine.supportedHere {
                            Text(MiroeEngine.unsupportedReason)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.stop)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                    if engines.miroeState == .installing {
                        Text("\(Int(engines.progress * 100))%")
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.separator, lineWidth: 0.5))
            .padding(.horizontal, 28)

            Spacer(minLength: 12)

            HStack {
                Spacer()
                if engines.miroeState != .installing {
                    Button("나중에") { postpone() }
                }
                Button {
                    Task { await engines.installMiroe() }
                } label: {
                    if engines.miroeState == .installing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("설치 중…")
                        }
                    } else {
                        Text(failed ? "다시 시도" : "엔진 받기").frame(minWidth: 90)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(engines.miroeState == .installing || !MiroeEngine.supportedHere)
            }
            .padding(20)
        }
        .frame(width: 560, height: 420)
    }

    private var failed: Bool {
        if case .failed = engines.miroeState { return true }
        return false
    }

    @ViewBuilder
    private var icon: some View {
        switch engines.miroeState {
        case .installed:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(Theme.success)
        case .installing:
            ProgressView().controlSize(.small)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").font(.system(size: 20)).foregroundStyle(Theme.stop)
        case .notInstalled:
            Image(systemName: "circle.dashed").font(.system(size: 20)).foregroundStyle(Theme.tertiaryText)
        }
    }
}
