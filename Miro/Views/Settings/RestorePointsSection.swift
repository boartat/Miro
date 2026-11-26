//
//  RestorePointsSection.swift
//  Miro
//
//  Settings → 호환 레이어: the C: drive copies Miro saved before installing libraries, with a way back.
//

import SwiftUI

struct RestorePointsSection: View {
    @EnvironmentObject private var installs: InstallCenter
    @State private var points: [RestorePoint] = []
    @State private var pending: RestorePoint?
    @State private var restoring = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.stop)
            }
            if points.isEmpty {
                Text("아직 없어요. 라이브러리를 설치하기 전에 자동으로 만들어져요.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(points) { point in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(point.reason)
                            .font(.system(size: 12.5, weight: .medium))
                        Text("\(WineEngine.of(point.engine).shortName) 엔진 · \(point.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    Button("되돌리기…") { pending = point }
                        .controlSize(.small)
                        .disabled(restoring || installs.isBusy)
                }
            }
        } header: {
            Text("복구 지점")
        } footer: {
            Text("라이브러리를 설치하기 전에 그 엔진의 C: 드라이브를 저장해 둬요(엔진마다 최근 3개, 게임 파일 제외). "
                 + "설치 뒤에 문제가 생기면 여기서 되돌릴 수 있어요. 되돌리기 직전 상태도 따로 저장돼서 다시 되돌릴 수 있어요.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
        }
        .onAppear { points = RestorePoints.list() }
        .onChange(of: installs.isBusy) { _, _ in points = RestorePoints.list() }
        .confirmationDialog("C: 드라이브를 이 시점으로 되돌릴까요?", isPresented: Binding(
            get: { pending != nil }, set: { if !$0 { pending = nil } }
        ), presenting: pending) { point in
            Button("되돌리기") {
                restoring = true
                Task {
                    do {
                        try await RestorePoints.restore(point)
                        errorMessage = nil
                    } catch {
                        errorMessage = "되돌리지 못했어요: \(error.localizedDescription)"
                    }
                    installs.refreshInstalled()
                    points = RestorePoints.list()
                    restoring = false
                }
            }
        } message: { point in
            Text("'\(point.reason)' 상태로 돌아가요. 그 뒤에 설치한 라이브러리와 바뀐 설정, 그 엔진에서 실행한 게임의 세이브(C: 드라이브 안에 있는 경우)도 그 시점으로 돌아가요. 지금 상태는 먼저 저장해 둬요.")
        }
    }
}
