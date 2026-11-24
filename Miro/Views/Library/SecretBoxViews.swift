//
//  SecretBoxViews.swift
//  Miro
//

import SwiftUI

/// The secret-box icon at the bottom of the sidebar
struct SecretBoxButton: View {
    @EnvironmentObject private var secret: SecretBox
    @State private var hovering = false

    var body: some View {
        Button {
            if secret.isUnlocked {
                secret.lock()
            } else {
                secret.request = secret.hasPassword ? .unlock : .create(hideAfter: nil)
            }
        } label: {
            HStack(spacing: 7) {
                SecretBoxIcon(open: secret.isUnlocked)
                    .frame(width: 26, height: 26)
                if secret.isUnlocked || hovering {
                    Text(secret.isUnlocked ? "잠그기" : "시크릿 박스")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(secret.isUnlocked ? "시크릿 박스 잠그기" : "시크릿 박스 — 숨긴 게임 보기")
    }
}

/// A little box with a lock badge
struct SecretBoxIcon: View {
    var open = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(LinearGradient(colors: [Color(nsColor: .systemIndigo), Color(nsColor: .systemPurple)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    Image(systemName: open ? "shippingbox" : "shippingbox.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                )
            Image(systemName: open ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(Color(nsColor: .systemIndigo))
                .frame(width: 13, height: 13)
                .background(Circle().fill(.white))
                .overlay(Circle().strokeBorder(Color(nsColor: .systemIndigo).opacity(0.3), lineWidth: 0.5))
                .offset(x: 4, y: 4)
        }
    }
}

/// Create / unlock / change-password sheet
struct SecretPasswordSheet: View {
    let request: SecretBoxRequest
    @EnvironmentObject private var secret: SecretBox
    @EnvironmentObject private var library: GameLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var error: String?
    @State private var shake: CGFloat = 0
    private enum Field { case current, password }
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(spacing: 16) {
            SecretBoxIcon(open: false)
                .frame(width: 54, height: 54)
                .scaleEffect(1.0)
                .padding(.top, 6)
            VStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                if case .change = request {
                    SecureField("현재 비밀번호", text: $current)
                        .focused($focusedField, equals: .current)
                }
                SecureField(isUnlock ? "비밀번호" : "새 비밀번호", text: $password)
                    .focused($focusedField, equals: .password)
                if !isUnlock {
                    SecureField("비밀번호 확인", text: $confirm)
                }
            }
            .textFieldStyle(.roundedBorder)
            .frame(width: 260)
            .offset(x: shake)
            .onSubmit(submit)

            Text(error ?? " ")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.stop)

            HStack {
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isUnlock ? "열기" : isChange ? "변경" : "만들기", action: submit)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty)
            }
            .frame(width: 260)
        }
        .padding(24)
        .frame(width: 340)
        .onAppear { focusedField = isChange ? .current : .password }
    }

    private var isUnlock: Bool { request == .unlock }
    private var isChange: Bool { request == .change }

    private var title: String {
        switch request {
        case .create: return "시크릿 박스 비밀번호 만들기"
        case .unlock: return "시크릿 박스 열기"
        case .change: return "비밀번호 변경"
        }
    }

    private var subtitle: String {
        switch request {
        case .create(let hide):
            return hide == nil
                ? "숨긴 게임은 이 비밀번호로만 볼 수 있어요.\n처음 한 번만 정하면 돼요."
                : "게임을 숨기기 전에 시크릿 박스 비밀번호를 정해 주세요.\n숨긴 게임은 이 비밀번호로만 볼 수 있어요."
        case .unlock: return "숨긴 게임을 보려면 비밀번호를 입력하세요"
        case .change: return "현재 비밀번호와 새 비밀번호를 입력하세요"
        }
    }

    private func submit() {
        guard !password.isEmpty else { return }
        do {
            switch request {
            case .unlock:
                guard secret.unlock(password) else { throw SecretBoxError.wrongPassword }
            case .create(let hideAfter):
                guard password == confirm else { throw SecretBoxError.mismatch }
                try secret.setPassword(password)
                if let hideAfter {
                    // Stay in the normal list; just move the game into the box
                    secret.lock()
                    library.setHidden(hideAfter, true)
                } else {
                    library.selectedID = nil
                }
            case .change:
                guard password == confirm else { throw SecretBoxError.mismatch }
                try secret.changePassword(current: current, new: password)
                library.showToastMessage("비밀번호를 바꿨어요")
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
            password = ""
            confirm = ""
            withAnimation(.spring(response: 0.15, dampingFraction: 0.2)) { shake = 10 }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.4).delay(0.1)) { shake = 0 }
        }
    }
}
