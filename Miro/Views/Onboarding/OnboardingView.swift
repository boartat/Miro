//
//  OnboardingView.swift
//  Miro
//
//  First-run guide: seven short pages (welcome, adding games, what runs, whole folders, hiding, folders, ready),
//  with previous / next, a progress indicator, page transitions and a small animated picture on each page.
//  Shown once; the Help menu can show it again.
//

import SwiftUI

struct OnboardingView: View {
    static let completedKey = "onboardingCompleted.v1"
    let finish: () -> Void

    @State private var page = OnboardingView.startPage
    @State private var forward = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pages = OnboardingPage.all

    /// Debug builds can open on a given page (MIRO_ONBOARDING_PAGE=3) to check its layout
    private static var startPage: Int {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["MIRO_ONBOARDING_PAGE"], let page = Int(value) {
            return min(max(page, 0), OnboardingPage.all.count - 1)
        }
        #endif
        return 0
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                OnboardingPageView(page: pages[page], reduceMotion: reduceMotion)
                    .id(page)
                    .transition(pageTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            footer
        }
        .frame(width: 780, height: 560)
        .background(OnboardingBackground(tint: pages[page].tint))
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let insertion: Edge = forward ? .trailing : .leading
        return .asymmetric(
            insertion: .move(edge: insertion).combined(with: .opacity).combined(with: .scale(scale: 0.98)),
            removal: .move(edge: insertion == .trailing ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private var header: some View {
        ZStack {
            Text("Miro 시작하기")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            HStack {
                if page < pages.count - 1 {
                    Button("건너뛰기", action: finish)
                        .buttonStyle(.plain)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.secondaryText)
                        .transition(.opacity)
                }
                Spacer()
                Text("\(page + 1) / \(pages.count)")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                    .contentTransition(.numericText(value: Double(page)))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 4)
    }

    private var footer: some View {
        HStack {
            Button { go(-1) } label: {
                Text("이전")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 110, height: 40)
                    .background(Capsule().fill(Theme.fill))
                    .foregroundStyle(page == 0 ? Theme.tertiaryText : .primary)
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(page == 0)
            .keyboardShortcut(.leftArrow, modifiers: [])

            Spacer()
            OnboardingProgress(count: pages.count, current: page)
            Spacer()

            Button { page == pages.count - 1 ? finish() : go(1) } label: {
                HStack(spacing: 6) {
                    Text(page == pages.count - 1 ? "시작하기" : "다음")
                    Image(systemName: page == pages.count - 1 ? "arrow.right.circle.fill" : "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 130, height: 40)
                .background(Capsule().fill(Theme.accent.gradient))
                .foregroundStyle(.white)
                .shadow(color: Theme.accent.opacity(0.35), radius: 8, y: 3)
            }
            .buttonStyle(PressableButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
        .background {
            // → also moves forward
            Button("") { if page < pages.count - 1 { go(1) } }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .opacity(0)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
        .padding(.top, 8)
    }

    private func go(_ delta: Int) {
        let next = min(max(page + delta, 0), pages.count - 1)
        guard next != page else { return }
        forward = delta > 0
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.55, bounce: 0.18)) {
            page = next
        }
    }
}

// MARK: - Pages

struct OnboardingPage {
    enum Art { case welcome, add, kinds, folderFirst, hide, organize, ready }

    let art: Art
    let title: String
    let highlight: String
    let body: String
    var chips: [(String, String)] = []
    var tint: Color

    static let all: [OnboardingPage] = [
        OnboardingPage(art: .welcome, title: "안녕하세요!", highlight: "Miro에 오신 것을 환영합니다!",
                       body: "Mac에서 Windows 게임과 프로그램을 실행하는 런처예요.\n쓰는 방법을 짧게 알려 드릴게요.",
                       tint: Color(nsColor: .systemBlue)),
        OnboardingPage(art: .add, title: "게임 추가하기", highlight: "끌어다 놓기만 하면 돼요.",
                       body: "게임 폴더나 실행 파일을 Miro 창에 끌어다 놓거나, 사이드바의 + 버튼(⌘O)을 누르세요.\n폴더를 넣으면 실행할 파일을 알아서 찾아요.",
                       tint: Color(nsColor: .systemTeal)),
        OnboardingPage(art: .kinds, title: "이런 걸 실행해요", highlight: "Windows 게임과 프로그램",
                       body: "실행 파일 종류: .exe · .msi · .bat · .lnk\n안티치트로 보호되는 온라인 게임은 실행되지 않을 수 있어요.",
                       chips: [("gamecontroller.fill", "Unity · Unreal · Godot"), ("book.fill", "RPG Maker · 울프 RPG"),
                               ("text.bubble.fill", "Ren'Py · KiriKiri"), ("cube.transparent.fill", "DirectX 9~12"),
                               ("cpu.fill", "32비트 · 64비트"), ("macwindow", "일반 Windows 프로그램")],
                       tint: Color(nsColor: .systemIndigo)),
        OnboardingPage(art: .folderFirst, title: "폴더째 추가하세요", highlight: "exe 하나만으로는 안 되는 프로그램도 있어요.",
                       body: "대부분의 게임은 exe 옆의 데이터 파일과 DLL이 함께 있어야 실행돼요.\n이런 게임은 exe만 넣지 말고, 관련 파일이 들어 있는 폴더 전체를 추가하세요.",
                       tint: Color(nsColor: .systemOrange)),
        OnboardingPage(art: .hide, title: "숨기기", highlight: "보이고 싶지 않은 게임은 숨겨요.",
                       body: "게임을 사이드바 아래의 '숨기기'(눈에 빗금 아이콘)로 끌어다 놓거나,\n게임을 우클릭해서 '숨기기'를 고르세요. 숨긴 게임은 비밀번호로 열고, 위의 '나가기'로 나와요.",
                       tint: Color(nsColor: .systemPurple)),
        OnboardingPage(art: .organize, title: "폴더로 정리하기", highlight: "게임과 프로그램을 나눠 담아요.",
                       body: "게임을 다른 게임 위로 끌어다 놓으면 새 폴더가 생겨요.\n우클릭 → '폴더로 이동'으로 옮기고, 폴더는 사이드바에서 관리해요.",
                       tint: Color(nsColor: .systemGreen)),
        OnboardingPage(art: .ready, title: "준비됐어요", highlight: "이제 시작해 볼까요?",
                       body: "사이드바의 'Steam 열기'로 Steam을 열고 로그인하면, Steam에서 받은 게임이 저절로 라이브러리에 들어와요.\n이 안내는 사이드바 아래의 ? 버튼으로 언제든 다시 볼 수 있어요.",
                       tint: Color(nsColor: .systemBlue)),
    ]
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 0) {
            OnboardingArt(art: page.art, tint: page.tint, animate: !reduceMotion)
                .frame(height: 190)
                .padding(.top, 8)

            VStack(spacing: 8) {
                Text(page.title)
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.5)
                Text(page.highlight)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(page.tint.gradient)
            }
            .multilineTextAlignment(.center)
            .padding(.top, 14)

            Text(page.body)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 560)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            if !page.chips.isEmpty {
                ChipFlow(chips: page.chips, tint: page.tint)
                    .padding(.top, 14)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
    }
}

/// Kinds of programs, popping in one after another
private struct ChipFlow: View {
    let chips: [(String, String)]
    let tint: Color

    var body: some View {
        let rows = [Array(chips.prefix(3)), Array(chips.dropFirst(3))]
        VStack(spacing: 8) {
            ForEach(0..<rows.count, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(Array(rows[row].enumerated()), id: \.offset) { index, chip in
                        Label(chip.1, systemImage: chip.0)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(tint.opacity(0.12)))
                            .foregroundStyle(tint)
                    }
                }
            }
        }
    }
}

/// Active page as a stretched capsule, others as dots
private struct OnboardingProgress: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Theme.accent : index < current ? Theme.accent.opacity(0.35) : Theme.separator)
                    .frame(width: index == current ? 22 : 7, height: 7)
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.3), value: current)
        .accessibilityElement()
        .accessibilityLabel("\(count)쪽 중 \(current + 1)쪽")
    }
}

private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Soft colour fields that drift slowly; their colour follows the page
private struct OnboardingBackground: View {
    let tint: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                Theme.window
                Circle()
                    .fill(tint.opacity(0.16))
                    .frame(width: 420, height: 420)
                    .blur(radius: 90)
                    .offset(x: -260 + sin(t * 0.25) * 40, y: -150 + cos(t * 0.2) * 30)
                Circle()
                    .fill(Color(nsColor: .systemBlue).opacity(0.12))
                    .frame(width: 380, height: 380)
                    .blur(radius: 100)
                    .offset(x: 280 + cos(t * 0.22) * 40, y: 170 + sin(t * 0.18) * 30)
            }
            .animation(.easeInOut(duration: 0.8), value: tint)
        }
    }
}
