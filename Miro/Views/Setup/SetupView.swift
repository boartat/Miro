//
//  SetupView.swift
//  Miro
//
//  First-run: installs the Windows 11 compatibility layer and every common game library.
//

import SwiftUI

struct SetupView: View {
    var postpone: () -> Void
    @EnvironmentObject private var runtime: RuntimeManager
    @EnvironmentObject private var installs: InstallCenter

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 84, height: 84)
                Text("Miro에 오신 것을 환영해요")
                    .font(.system(size: 24, weight: .bold))
                Text("Windows 게임을 Mac에서 실행할 수 있도록 Windows 11 호환 레이어와\n게임에 자주 필요한 라이브러리를 한 번에 준비할게요.")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.top, 28)
            .padding(.bottom, 20)

            VStack(spacing: 0) {
                ForEach(RuntimeManager.Step.allCases) { step in
                    StepRow(step: step)
                    if step != RuntimeManager.Step.allCases.last { Divider().padding(.leading, 52) }
                }
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.separator, lineWidth: 0.5))
            .padding(.horizontal, 28)

            Toggle(isOn: $runtime.includeExtras) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(".NET Framework 4.8 · XNA · .NET 8 · 동영상 코덱도 설치")
                        .font(.system(size: 12.5, weight: .medium))
                    Text("일부 게임에만 필요하고 설치에 10분 이상 걸릴 수 있어요 (+약 200MB)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .toggleStyle(.checkbox)
            .disabled(runtime.isRunningSetup)
            .padding(.horizontal, 32)
            .padding(.top, 14)

            Spacer(minLength: 12)

            HStack {
                if runtime.isRunningSetup && runtime.isReady {
                    Text("호환 레이어는 준비됐어요. 나머지 라이브러리는 백그라운드에서 받을 수 있어요.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                if runtime.isReady {
                    Button(runtime.isRunningSetup ? "백그라운드에서 계속하기" : "나중에") { postpone() }
                } else if !runtime.isRunningSetup {
                    Button("나중에") { postpone() }
                }
                Button {
                    Task { await runtime.runSetup() }
                } label: {
                    if runtime.isRunningSetup {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("설치 중…")
                        }
                    } else {
                        Text(hasFailure ? "다시 시도" : "설치 시작")
                            .frame(minWidth: 90)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(runtime.isRunningSetup)
            }
            .padding(20)
        }
        .frame(width: 640, height: 640)
    }

    private var hasFailure: Bool {
        RuntimeManager.Step.allCases.contains { step in
            if case .failed = runtime.state(step) { return true }
            return false
        }
    }
}

private struct StepRow: View {
    let step: RuntimeManager.Step
    @EnvironmentObject private var runtime: RuntimeManager
    @EnvironmentObject private var installs: InstallCenter

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            icon
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .font(.system(size: 13.5, weight: .semibold))
                Text(step.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryText)

                if runtime.state(step) == .running {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(Theme.accent)
                        .padding(.top, 4)
                    Text(detail)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                if case .failed(let message) = runtime.state(step) {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.stop)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if runtime.state(step) == .running {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .animation(.easeInOut(duration: 0.2), value: runtime.state(step))
    }

    private var progress: Double {
        if step == .libraries {
            return installs.progress(of: runtime.libraryIDs)
        }
        return runtime.stepProgress[step] ?? 0
    }

    private var detail: String {
        if step == .libraries {
            let done = runtime.libraryIDs.filter(installs.isInstalled).count
            if let current = installs.currentID, let dependency = DependencyCatalog.dependency(current) {
                let phase = installs.job(current)?.phase ?? ""
                return "\(done)/\(runtime.libraryIDs.count) · \(dependency.name) — \(phase)"
            }
            return "\(done)/\(runtime.libraryIDs.count) 완료"
        }
        return runtime.stepDetail[step] ?? ""
    }

    @ViewBuilder
    private var icon: some View {
        switch runtime.state(step) {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Theme.success)
        case .running:
            ProgressView().controlSize(.small)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Theme.stop)
        case .pending:
            Image(systemName: "circle.dashed")
                .font(.system(size: 20))
                .foregroundStyle(Theme.tertiaryText)
        }
    }
}
