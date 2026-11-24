//
//  DropOverlay.swift
//  Miro
//
//  Shown over the whole window while an .exe is dragged onto it.
//

import SwiftUI

struct DropOverlay: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            // White at ~70 % opacity over the entire window
            Color.white.opacity(0.7)

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [12, 9]))
                .foregroundStyle(Color.accentColor.opacity(0.85))
                .padding(28)

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 112, height: 112)
                        .scaleEffect(pulse ? 1.08 : 0.94)
                    Image(systemName: "arrow.down.app.fill")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                Text("파일을 넣어주세요")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.85))
                Text("게임 폴더를 놓으면 폴더째 Miro에 복사하고, exe만 놓으면 그 파일만 추가해요")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.5))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// Small rounded message at the bottom of the window
struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
}
