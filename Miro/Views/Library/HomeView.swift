//
//  HomeView.swift
//  Miro
//
//  "홈": the miroe banner, every game and program, then the recently run ones.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var library: GameLibrary

    var body: some View {
        let games = library.sorted(filter: "")
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                MeetMiroeBanner()

                if games.isEmpty && library.imports.isEmpty {
                    EmptyLibraryView()
                        .frame(minHeight: 360)
                } else {
                    HomeSection(title: "전체 게임 · 프로그램", symbol: "square.grid.2x2.fill", count: games.count) {
                        HomeGrid(games: games)
                    }

                    let recent = games
                        .filter { $0.lastPlayedAt != nil }
                        .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
                        .prefix(6)
                    if !recent.isEmpty {
                        HomeSection(title: "최근 실행", symbol: "clock.fill") {
                            VStack(spacing: 0) {
                                ForEach(Array(recent.enumerated()), id: \.element.id) { index, game in
                                    if index > 0 { Divider().padding(.leading, 152) }
                                    RecentRow(game: game)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 40)
            .padding(.bottom, 36)
        }
    }
}

/// The home banner: the name, a link to the project (miroe's updates and progress), and whether this Miro is current
struct MeetMiroeBanner: View {
    @StateObject private var updates = UpdateChecker.shared
    @State private var hovering = false
    @State private var appeared = false

    var body: some View {
        HStack(alignment: .center) {
            Link(destination: MiroLinks.repository) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Meet miroe.")
                        .font(.system(size: 44, weight: .bold))
                        .tracking(-0.8)
                        .foregroundStyle(.white)
                    HStack(spacing: 6) {
                        Text("GitHub 바로가기")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .bold))
                            .offset(x: hovering ? 2 : 0, y: hovering ? -2 : 0)
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(hovering ? 0.95 : 0.72))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("Miro와 miroe의 최신 업데이트와 개발 현황 (GitHub)")
            Spacer(minLength: 16)
            versionBadge
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .background(MiroeBannerBackground())
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(hovering ? 0.28 : 0.16), radius: hovering ? 18 : 10, y: hovering ? 8 : 4)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .animation(.spring(duration: 0.35), value: hovering)
        .animation(.easeInOut(duration: 0.25), value: updates.status)
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { appeared = true } }
        .task { await updates.check() }
    }

    /// "v1.2.0 · 최신 버전" or a link to the newer release
    @ViewBuilder
    private var versionBadge: some View {
        switch updates.status {
        case .checking:
            badge(icon: nil, text: "버전 확인 중…", tint: .white.opacity(0.7), spinning: true)
        case .latest:
            badge(icon: "checkmark.seal.fill", text: "v\(updates.currentVersion) · 최신 버전", tint: Color(nsColor: .systemGreen))
        case .available(let version, let url):
            Link(destination: url) {
                badge(icon: "arrow.down.circle.fill", text: "새 버전 v\(version) 받기", tint: Color(nsColor: .systemBlue), filled: true)
            }
            .buttonStyle(.plain)
            .help("지금 v\(updates.currentVersion) · GitHub에서 v\(version) 받기")
        case .unknown:
            Button { Task { await updates.check(force: true) } } label: {
                badge(icon: "arrow.clockwise", text: "v\(updates.currentVersion) · 확인 실패, 다시", tint: .white.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
    }

    private func badge(icon: String?, text: String, tint: Color, spinning: Bool = false, filled: Bool = false) -> some View {
        HStack(spacing: 6) {
            if spinning { ProgressView().controlSize(.mini).tint(.white) }
            if let icon { Image(systemName: icon).foregroundStyle(filled ? .white : tint) }
            Text(text).foregroundStyle(.white)
        }
        .font(.system(size: 12.5, weight: .semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(filled ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(.white.opacity(0.12))))
        .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
    }
}

/// Deep blue-black with two slow light bands, drawn here (no image)
struct MiroeBannerBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                canvas.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                    Gradient(colors: [Color(red: 0.07, green: 0.09, blue: 0.14), Color(red: 0.12, green: 0.15, blue: 0.24)]),
                    startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
                for band in 0..<2 {
                    let phase = t * (0.18 + Double(band) * 0.07) + Double(band) * 1.7
                    var path = Path()
                    let baseY = size.height * (0.95 - Double(band) * 0.18)
                    path.move(to: CGPoint(x: size.width * 0.35, y: size.height + 20))
                    for step in 0...40 {
                        let x = size.width * (0.35 + 0.65 * Double(step) / 40)
                        let progress = Double(step) / 40
                        let y = baseY - progress * size.height * 0.9 + sin(progress * 3.2 + phase) * 14
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    canvas.stroke(path, with: .linearGradient(
                        Gradient(colors: [.white.opacity(0), .white.opacity(band == 0 ? 0.16 : 0.10), .white.opacity(0)]),
                        startPoint: CGPoint(x: size.width * 0.35, y: 0), endPoint: CGPoint(x: size.width, y: 0)),
                        lineWidth: band == 0 ? 26 : 14)
                }
            }
            .blur(radius: 10)
        }
    }
}

/// One line of "최근 실행": artwork, name, when, Play
struct RecentRow: View {
    let game: Game
    @EnvironmentObject private var library: GameLibrary
    @EnvironmentObject private var launcher: GameLauncher
    @EnvironmentObject private var runtime: RuntimeManager
    @State private var hovering = false

    var body: some View {
        let running = launcher.isRunning(game.id)
        HStack(spacing: 16) {
            Color.clear
                .frame(width: 136, height: 76)
                .overlay(CardArtwork(game: game))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Theme.separator.opacity(0.6), lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 3) {
                Text(game.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(running ? "실행 중" : "\(Game.relativeDate(game.lastPlayedAt)) 실행함 · \(game.engine.shortName)")
                    .font(.system(size: 12))
                    .foregroundStyle(running ? Theme.play : Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                if running { launcher.stop(game) } else { launcher.launch(game) }
            } label: {
                Image(systemName: running ? "stop.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(running ? .white : .primary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(running ? AnyShapeStyle(Theme.stop.gradient) : AnyShapeStyle(Theme.fill)))
            }
            .buttonStyle(.plain)
            .disabled(!running && (!runtime.isReady || !game.exists))
            .help(running ? "중지" : "플레이")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hovering ? Theme.fill : .clear))
        .contentShape(Rectangle())
        .onTapGesture { library.selectedID = game.id }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .contextMenu { GameContextMenu(game: game) }
    }
}

/// Landing page while the secret box is open and no hidden game is selected
struct SecretBoxHomeView: View {
    @EnvironmentObject private var library: GameLibrary
    @EnvironmentObject private var secret: SecretBox

    var body: some View {
        let hidden = library.sorted(filter: "", hidden: true)
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 16) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.75)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("시크릿 박스")
                            .font(.system(size: 30, weight: .bold))
                        Text("숨긴 게임 \(hidden.count)개 · 목록·홈·검색에는 나타나지 않아요")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                }
                if hidden.isEmpty {
                    Text("숨긴 게임이 없어요. 게임을 사이드바 아래 '숨기기'로 끌어다 놓거나, 우클릭해서 '숨기기'를 누르면 여기로 와요.")
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    HomeGrid(games: hidden)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 84)
            .padding(.bottom, 36)
        }
    }
}

struct HomeSection<Content: View>: View {
    let title: String
    let symbol: String
    var count: Int?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .foregroundStyle(Theme.accent)
                Text(title)
                    .font(.system(size: 19, weight: .bold))
                if let count {
                    Text("\(count)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            content()
        }
    }
}

struct HomeGrid: View {
    let games: [Game]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 340), spacing: 18, alignment: .top)],
                  alignment: .leading, spacing: 22) {
            ForEach(games) { HomeCard(game: $0) }
        }
    }
}

/// 16:9 game card; hover shows a Play button
struct HomeCard: View {
    let game: Game
    var width: CGFloat?
    @EnvironmentObject private var library: GameLibrary
    @EnvironmentObject private var launcher: GameLauncher
    @EnvironmentObject private var runtime: RuntimeManager
    @State private var hovering = false

    var body: some View {
        let running = launcher.isRunning(game.id)
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay(CardArtwork(game: game))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.separator.opacity(0.6), lineWidth: 0.5)
                )
                .overlay(alignment: .topLeading) {
                    if running {
                        Label("실행 중", systemImage: "play.fill")
                            .font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.play, in: Capsule())
                            .foregroundStyle(.white)
                            .padding(10)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if hovering || running {
                        Button {
                            if running { launcher.stop(game) } else { launcher.launch(game) }
                        } label: {
                            Image(systemName: running ? "stop.fill" : "play.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(Circle().fill((running ? Theme.stop : Theme.play).gradient))
                                .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                        }
                        .buttonStyle(.plain)
                        .disabled(!running && (!runtime.isReady || !game.exists))
                        .padding(10)
                        .transition(.scale.combined(with: .opacity))
                        .help(running ? "중지" : "플레이")
                    }
                }
                .shadow(color: .black.opacity(hovering ? 0.22 : 0.08), radius: hovering ? 12 : 4, y: hovering ? 6 : 2)
                .scaleEffect(hovering ? 1.015 : 1)

            HStack(spacing: 7) {
                GameIconView(game: game, size: 20)
                Text(game.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            Text("\(game.engine.shortName) · \(Game.relativeDate(game.lastPlayedAt))")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .onTapGesture { library.selectedID = game.id }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .contextMenu { GameContextMenu(game: game) }
    }
}

/// Cover image, or a tinted tile with the game's icon
struct CardArtwork: View {
    let game: Game
    @EnvironmentObject private var library: GameLibrary

    var body: some View {
        if let cover = library.cover(for: game) {
            Image(nsImage: cover)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            let tint = GameIconView.tint(for: game.name)
            ZStack {
                LinearGradient(colors: [tint, tint.opacity(0.55), Color(nsColor: .systemIndigo).opacity(0.55)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                if let icon = library.icon(for: game) {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 30)
                        .opacity(0.6)
                }
                GameIconView(game: game, size: 64)
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            }
        }
    }
}

struct EmptyLibraryView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("아직 게임이 없어요")
                .font(.system(size: 22, weight: .bold))
            Text("게임 폴더나 exe 파일을 이 창에 끌어다 놓거나 + 버튼을 눌러 추가하세요")
                .foregroundStyle(Theme.secondaryText)
            Button {
                AddGamePanel.present()
            } label: {
                Label("게임 추가", systemImage: "plus")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
