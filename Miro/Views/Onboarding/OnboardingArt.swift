//
//  OnboardingArt.swift
//  Miro
//
//  The small looping picture at the top of each onboarding page, drawn from SF Symbols and shapes.
//  With Reduce Motion on, each picture holds one still frame.
//

import SwiftUI

struct OnboardingArt: View {
    let art: OnboardingPage.Art
    let tint: Color
    let animate: Bool

    var body: some View {
        if animate {
            TimelineView(.animation) { context in
                frame(context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            frame(2.2)
        }
    }

    @ViewBuilder
    private func frame(_ t: Double) -> some View {
        switch art {
        case .welcome: WelcomeArt(t: t)
        case .add: AddArt(t: t, tint: tint)
        case .kinds: KindsArt(t: t, tint: tint)
        case .folderFirst: FolderFirstArt(t: t, tint: tint)
        case .hide: HideArt(t: t)
        case .organize: OrganizeArt(t: t, tint: tint)
        case .ready: ReadyArt(t: t, tint: tint)
        }
    }
}

// MARK: - Helpers

/// 0…1 position inside a repeating cycle
private func cycle(_ t: Double, _ period: Double, offset: Double = 0) -> Double {
    let x = (t + offset).truncatingRemainder(dividingBy: period) / period
    return x < 0 ? x + 1 : x
}

/// Progress of a segment [start, end] inside a cycle, eased
private func segment(_ x: Double, _ start: Double, _ end: Double) -> Double {
    let p = min(max((x - start) / (end - start), 0), 1)
    return p * p * (3 - 2 * p)
}

/// A rounded, softly lit tile holding one symbol
struct OnboardingTile: View {
    let symbol: String
    let colors: [Color]
    var size: CGFloat = 96

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                    .blendMode(.overlay)
            )
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            )
            .frame(width: size, height: size)
            .shadow(color: (colors.first ?? .black).opacity(0.35), radius: size * 0.16, y: size * 0.08)
    }
}

private extension Color {
    func lighter(_ amount: Double = 0.25) -> Color { Color(nsColor: NSColor(self).blended(withFraction: amount, of: .white) ?? NSColor(self)) }
}

// MARK: - Pictures

private struct WelcomeArt: View {
    let t: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(nsColor: .systemBlue).opacity(0.18))
                .frame(width: 190, height: 190)
                .blur(radius: 30)
                .scaleEffect(1 + sin(t * 1.4) * 0.05)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 140, height: 140)
                .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
                .offset(y: sin(t * 1.6) * 5)
            ForEach(0..<3, id: \.self) { index in
                let x = cycle(t, 2.4, offset: Double(index) * 0.8)
                let positions: [CGSize] = [CGSize(width: 92, height: -58), CGSize(width: -96, height: 40), CGSize(width: 78, height: 62)]
                Image(systemName: "sparkle")
                    .font(.system(size: index == 0 ? 22 : 15, weight: .bold))
                    .foregroundStyle(Color(nsColor: .systemBlue).gradient)
                    .scaleEffect(0.4 + sin(x * .pi) * 0.8)
                    .opacity(sin(x * .pi))
                    .rotationEffect(.degrees(x * 90))
                    .offset(positions[index])
            }
        }
    }
}

private struct AddArt: View {
    let t: Double
    let tint: Color

    var body: some View {
        let x = cycle(t, 3.2)
        let travel = segment(x, 0.08, 0.5)
        let landed = segment(x, 0.5, 0.62)
        let fade = segment(x, 0.86, 1.0)
        ZStack {
            // the Miro window
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.card)
                .frame(width: 250, height: 156)
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 5) {
                        ForEach([Color.red, Color.yellow, Color.green], id: \.self) {
                            Circle().fill($0.opacity(0.8)).frame(width: 8, height: 8)
                        }
                    }
                    .padding(12)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(tint.opacity(0.25 + landed * 0.6 - fade * 0.6), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .padding(18)
                        .padding(.top, 12)
                )
                .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
                .offset(x: 30)

            // the file that is dropped in
            VStack(spacing: 4) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(tint.gradient)
                Text("Game")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            .scaleEffect(1.1 - travel * 0.15 - landed * 0.1)
            .rotationEffect(.degrees(-12 * (1 - travel)))
            .offset(x: -130 + travel * 160, y: -50 + travel * 58)
            .opacity(1 - fade)

            // the cursor carrying it
            Image(systemName: "cursorarrow")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.primary)
                .offset(x: -110 + travel * 160, y: -26 + travel * 58)
                .opacity(1 - landed)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white, Theme.success)
                .scaleEffect(landed * (1 - fade * 0.3))
                .opacity(landed - fade)
                .offset(x: 140, y: -62)
        }
    }
}

private struct KindsArt: View {
    let t: Double
    let tint: Color

    var body: some View {
        let orbit = ["gamecontroller.fill", "book.fill", "text.bubble.fill", "cube.transparent.fill", "macwindow"]
        let palette: [Color] = [Color(nsColor: .systemPink), Color(nsColor: .systemOrange), Color(nsColor: .systemTeal),
                                Color(nsColor: .systemGreen), Color(nsColor: .systemBlue)]
        ZStack {
            Ellipse()
                .strokeBorder(tint.opacity(0.18), lineWidth: 1.5)
                .frame(width: 330, height: 150)
            OnboardingTile(symbol: "app.dashed", colors: [tint.lighter(), tint], size: 96)
                .overlay(Text("EXE").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white.opacity(0.9)).offset(y: 28))
                .zIndex(1)
            ForEach(0..<orbit.count, id: \.self) { index in
                let angle = t * 0.5 + Double(index) / Double(orbit.count) * 2 * .pi
                let depth = sin(angle)
                OnboardingTile(symbol: orbit[index], colors: [palette[index].lighter(), palette[index]], size: 46)
                    .scaleEffect(0.8 + depth * 0.2)
                    .offset(x: cos(angle) * 165, y: depth * 75)
                    .opacity(0.65 + depth * 0.35)
                    .zIndex(depth)
            }
        }
    }
}

private struct FolderFirstArt: View {
    let t: Double
    let tint: Color

    var body: some View {
        let x = cycle(t, 3.6)
        let pop = segment(x, 0.12, 0.3)
        let gather = segment(x, 0.35, 0.7)
        let check = segment(x, 0.7, 0.82)
        HStack(spacing: 60) {
            // an exe alone
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 6) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(Theme.tertiaryText)
                    Text("game.exe")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.secondaryText)
                }
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white, Theme.stop)
                    .scaleEffect(pop)
                    .offset(x: 14, y: -10)
            }

            Image(systemName: "arrow.right")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.tertiaryText)

            // the whole folder
            ZStack(alignment: .topTrailing) {
                ZStack {
                    ForEach(0..<3, id: \.self) { index in
                        let symbols = ["doc.fill", "gearshape.fill", "photo.fill"]
                        let start = CGSize(width: Double(index - 1) * 46, height: -64)
                        Image(systemName: symbols[index])
                            .font(.system(size: 18))
                            .foregroundStyle(tint)
                            .offset(x: start.width * (1 - gather), y: start.height * (1 - gather) - 6)
                            .scaleEffect(1 - gather * 0.5)
                            .opacity(1 - gather * 0.9)
                    }
                    Image(systemName: "folder.fill")
                        .font(.system(size: 76))
                        .foregroundStyle(tint.gradient)
                        .scaleEffect(1 + sin(gather * .pi) * 0.06)
                    VStack(spacing: 0) {
                        Spacer()
                        Text("data · dll · exe")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .offset(y: 22)
                    }
                    .frame(height: 76)
                }
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white, Theme.success)
                    .scaleEffect(check)
                    .offset(x: 10, y: -6)
            }
        }
    }
}

private struct HideArt: View {
    let t: Double

    var body: some View {
        let x = cycle(t, 3.4)
        let lift = segment(x, 0.05, 0.2)
        let fall = segment(x, 0.2, 0.55)
        let gulp = segment(x, 0.55, 0.65)
        let reset = segment(x, 0.9, 1.0)
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(nsColor: .systemPurple).opacity(0.55 + gulp * 0.4), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .frame(width: 150, height: 74)
                .overlay(
                    Image(systemName: fall > 0.4 && gulp < 1 ? "eye.slash.fill" : "eye.slash")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(Color(nsColor: .systemPurple))
                )
                .scaleEffect(1 + sin(gulp * .pi) * 0.08)
                .offset(y: 46)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Color(nsColor: .systemPink), Color(nsColor: .systemOrange)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 104, height: 60)
                .overlay(Image(systemName: "gamecontroller.fill").font(.system(size: 24)).foregroundStyle(.white))
                .shadow(color: .black.opacity(0.2), radius: 8 + lift * 6, y: 4 + lift * 4)
                .scaleEffect((1 + lift * 0.08) * (1 - fall * 0.65))
                .rotationEffect(.degrees(lift * -6 + fall * 10))
                .offset(x: -120 * (1 - fall), y: -50 - lift * 8 + fall * 84)
                .opacity((1 - gulp) + reset)

            Label("우클릭 → 숨기기", systemImage: "cursorarrow.click")
                .font(.system(size: 11.5, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Theme.card).shadow(color: .black.opacity(0.1), radius: 4, y: 2))
                .offset(x: 140, y: -40)
        }
    }
}

private struct OrganizeArt: View {
    let t: Double
    let tint: Color

    var body: some View {
        let x = cycle(t, 3.6)
        let colors: [Color] = [Color(nsColor: .systemBlue), Color(nsColor: .systemPink), Color(nsColor: .systemYellow)]
        let starts: [CGSize] = [CGSize(width: -170, height: -40), CGSize(width: 0, height: -90), CGSize(width: 170, height: -40)]
        ZStack {
            Image(systemName: "folder.fill")
                .font(.system(size: 104))
                .foregroundStyle(tint.gradient)
                .shadow(color: tint.opacity(0.35), radius: 14, y: 6)
                .scaleEffect(1 + sin(segment(x, 0.55, 0.75) * .pi) * 0.06)
                .offset(y: 34)
            ForEach(0..<3, id: \.self) { index in
                let move = segment(x, 0.1 + Double(index) * 0.12, 0.45 + Double(index) * 0.12)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(colors[index].gradient)
                    .frame(width: 58, height: 36)
                    .overlay(Image(systemName: ["gamecontroller.fill", "paintpalette.fill", "music.note"][index])
                        .font(.system(size: 14)).foregroundStyle(.white))
                    .shadow(color: .black.opacity(0.15), radius: 5, y: 3)
                    .scaleEffect(1 - move * 0.55)
                    .rotationEffect(.degrees(Double(index - 1) * 14 * (1 - move)))
                    .offset(x: starts[index].width * (1 - move), y: starts[index].height * (1 - move) + move * 30)
                    .opacity(1 - move)
            }
        }
    }
}

private struct ReadyArt: View {
    let t: Double
    let tint: Color

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                let x = cycle(t, 2.7, offset: Double(index) * 0.9)
                Circle()
                    .strokeBorder(tint.opacity(0.45 * (1 - x)), lineWidth: 2)
                    .frame(width: 120, height: 120)
                    .scaleEffect(1 + x * 0.9)
            }
            OnboardingTile(symbol: "checkmark", colors: [tint.lighter(), tint], size: 112)
                .scaleEffect(1 + sin(t * 1.8) * 0.025)
        }
    }
}
