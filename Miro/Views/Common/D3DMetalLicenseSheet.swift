//
//  D3DMetalLicenseSheet.swift
//  Miro
//
//  Shows Apple's Game Porting Toolkit licence that ships with D3DMetal and asks before using it.
//

import AppKit
import SwiftUI

struct D3DMetalLicenseSheet: View {
    @EnvironmentObject private var engines: EngineManager
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apple D3DMetal 라이선스")
                .font(.system(size: 17, weight: .bold))
            Text("D3DMetal은 Apple Game Porting Toolkit의 일부예요. 아래 라이선스에 따라 개발·테스트·평가 용도로, 비상업적으로만 쓸 수 있고 수정할 수 없어요. "
                 + "동의하면 최신 엔진에서 DirectX 11/12 게임을 D3DMetal로 그릴 수 있어요.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                Text(text.isEmpty ? "라이선스 파일을 찾지 못했어요. 최신 엔진을 다시 설치해 주세요." : text)
                    .font(.system(size: 11))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(Theme.secondaryText.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Spacer()
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("동의하고 켜기") {
                    engines.acceptD3DMetalLicense()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(text.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560, height: 520)
        .task {
            let url = ModernEngine.d3dmetalLicenseFile
            text = (try? NSAttributedString(url: url, options: [:], documentAttributes: nil))?.string ?? ""
        }
    }
}
