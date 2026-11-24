//
//  DependencyRow.swift
//  Miro
//
//  One library with its status and a download button that turns into a loading bar.
//

import SwiftUI

struct DependencyRow: View {
    let dependency: Dependency
    /// Extra text in front of the name, e.g. the missing DLL that triggered it
    var reason: String?
    var compact = false
    /// Prefix the library goes into (a game on the modern engine has its own C: drive)
    var engine: WineEngineKind = .classic
    @EnvironmentObject private var installs: InstallCenter

    private var job: InstallCenter.Job? { installs.job(dependency.id) }
    private var isInstalled: Bool { installs.isInstalled(dependency.id, on: engine) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                statusIcon
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        if let reason {
                            Text(reason)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.tertiaryText)
                        }
                        Text(dependency.name)
                            .font(.system(size: 13, weight: .medium))
                    }
                    if !compact {
                        Text(dependency.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                trailing
            }
            if let job, job.state == .running || job.state == .queued {
                VStack(alignment: .leading, spacing: 3) {
                    ProgressView(value: job.state == .queued ? 0 : job.progress)
                        .progressViewStyle(.linear)
                        .tint(Theme.accent)
                    Text(job.state == .queued ? "대기 중…" : job.phase)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                .padding(.leading, 28)
                .transition(.opacity)
            }
            if let job, case .failed(let message) = job.state {
                Text(message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.stop)
                    .lineLimit(2)
                    .padding(.leading, 28)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: job)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isInstalled || job?.state == .done {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
        } else if let job, case .failed = job.state {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
        } else if job?.state == .running {
            ProgressView().controlSize(.small)
        } else {
            Image(systemName: "arrow.down.circle").foregroundStyle(Theme.accent)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if isInstalled || job?.state == .done {
            Text("설치됨")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
        } else if job?.state == .running || job?.state == .queued {
            Text(job?.state == .queued ? "대기" : "\(Int((job?.progress ?? 0) * 100))%")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.accent)
        } else {
            Button {
                installs.enqueue([dependency], force: job != nil, engine: engine)
            } label: {
                Text(job != nil ? "다시 시도" : dependency.sizeMB > 0 ? "다운로드 · \(dependency.sizeMB)MB" : "설치")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(Theme.accent)
        }
    }
}
