//
//  CompatibilityCard.swift
//  Miro
//
//  "호환성 · 필요한 라이브러리" — what the game imports and one-click installs with loading bars.
//

import SwiftUI

struct CompatibilityCard: View {
    let game: Game
    let report: CompatibilityReport?
    @EnvironmentObject private var installs: InstallCenter
    @State private var showAllDLLs = false

    var body: some View {
        Card("호환성 · 필요한 라이브러리", symbol: "checkmark.shield.fill", trailing: trailingButton) {
            if let report {
                content(report)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("실행 파일을 분석하는 중…")
                        .foregroundStyle(Theme.secondaryText)
                }
                .font(.system(size: 12))
            }
        }
    }

    private var pendingIDs: [String] {
        (report?.recommendedIDs ?? []).filter { !installs.isInstalled($0) }
    }

    private var trailingButton: AnyView? {
        guard pendingIDs.count > 1 else { return nil }
        let active = pendingIDs.contains(where: installs.isActive)
        return AnyView(
            Button(active ? "설치 중…" : "모두 설치") {
                installs.enqueue(DependencyCatalog.dependencies(pendingIDs))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(active)
        )
    }

    @ViewBuilder
    private func content(_ report: CompatibilityReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            summary(report)

            let unknownMissing = report.missing.filter { $0.dependencyID == nil }
            if !unknownMissing.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(unknownMissing) { dll in
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Theme.warning)
                                .frame(width: 18)
                            Text(dll.name)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            Text("게임 폴더에 직접 넣어야 하는 파일")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
            }

            if !pendingIDs.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(DependencyCatalog.dependencies(pendingIDs)) { dependency in
                        DependencyRow(dependency: dependency, reason: triggeringDLL(for: dependency, in: report))
                    }
                }
            }

            let ready = report.recommendedIDs.filter(installs.isInstalled)
            if !ready.isEmpty {
                FlowChips(items: DependencyCatalog.dependencies(ready).map(\.name))
            }

            let rtp = report.rtpIDs.filter { !installs.isInstalled($0) }
            if !rtp.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("선택 사항")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                    ForEach(DependencyCatalog.dependencies(rtp)) { DependencyRow(dependency: $0) }
                }
            }

            ForEach(report.engine.notes, id: \.self) { note in
                Label(note, systemImage: "lightbulb")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryText)
            }

            if !report.dlls.isEmpty {
                DisclosureGroup(isExpanded: $showAllDLLs) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(report.dlls) { dll in
                            HStack {
                                Text(dll.name)
                                    .font(.system(size: 11.5, design: .monospaced))
                                Spacer()
                                Text(dll.state.label)
                                    .font(.system(size: 11))
                                    .foregroundStyle(color(for: dll.state))
                            }
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Text("이 게임이 불러오는 DLL \(report.dlls.count)개")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private func summary(_ report: CompatibilityReport) -> some View {
        let missingCount = report.missing.count
        HStack(spacing: 10) {
            Image(systemName: missingCount > 0 ? "exclamationmark.triangle.fill"
                  : pendingIDs.isEmpty ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(missingCount > 0 ? Theme.warning : pendingIDs.isEmpty ? Theme.success : Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(missingCount > 0 ? "필요한 파일 \(missingCount)개가 없어요"
                     : pendingIDs.isEmpty ? "필요한 라이브러리가 모두 준비되었어요"
                     : "추천 라이브러리 \(pendingIDs.count)개")
                    .font(.system(size: 13, weight: .semibold))
                Text(report.info == nil
                     ? "Windows 실행 파일 정보를 읽지 못했어요"
                     : "\(game.engine.displayName) · DLL \(report.info?.imports.count ?? 0)개 분석")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func triggeringDLL(for dependency: Dependency, in report: CompatibilityReport) -> String? {
        report.dlls.first { $0.dependencyID == dependency.id && $0.state != .installed }?.name
    }

    private func color(for state: DLLCheck.State) -> Color {
        switch state {
        case .missing: return Theme.warning
        case .builtin: return Theme.secondaryText
        case .installed, .bundled: return Theme.success
        }
    }
}

/// Wrapping row of "✓ name" chips
struct FlowChips: View {
    let items: [String]

    var body: some View {
        ChipLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Label(item, systemImage: "checkmark")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.success.opacity(0.12), in: Capsule())
                    .foregroundStyle(Theme.success)
            }
        }
    }
}

struct ChipLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
