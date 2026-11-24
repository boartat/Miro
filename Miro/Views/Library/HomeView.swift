//
//  HomeView.swift
//  Miro
//
//  "홈": recently played shelf, one section per folder, then every other game as cards.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var library: GameLibrary

    var body: some View {
        let games = library.sorted(filter: "")
        if games.isEmpty && library.imports.isEmpty {
            EmptyLibraryView()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    HStack(alignment: .lastTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("홈")
                                .font(.system(size: 34, weight: .bold))
                            Text(summary(games))
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        Button {
                            AddGamePanel.present()
                        } label: {
                            Label("게임 추가", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                    }

                    let recent = games
                        .filter { $0.lastPlayedAt != nil }
                        .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
                        .prefix(8)
                    if !recent.isEmpty {
                        HomeSection(title: "최근 플레이", symbol: "clock.fill") {
                            ScrollView(.horizontal) {
                                LazyHStack(spacing: 18) {
                                    ForEach(Array(recent)) { game in
                                        HomeCard(game: game, width: 340)
                                    }
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 2)
                            }
                            .scrollIndicators(.never)
                        }
                    }

                    ForEach(library.sortedFolders) { folder in
                        let folderGames = library.games(in: folder, filter: "")
                        if !folderGames.isEmpty {
                            HomeSection(title: folder.name, symbol: "folder.fill", count: folderGames.count) {
                                HomeGrid(games: folderGames)
                            }
                        }
                    }

                    let ungrouped = library.ungroupedGames(filter: "")
                    if !ungrouped.isEmpty {
                        HomeSection(title: library.folders.isEmpty ? "모든 게임" : "그 밖의 게임",
                                    symbol: "square.grid.2x2.fill", count: ungrouped.count) {
                            HomeGrid(games: ungrouped)
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 44)
                .padding(.bottom, 36)
            }
        }
    }

    private func summary(_ games: [Game]) -> String {
        var parts = ["게임 \(games.count)개"]
        if !library.folders.isEmpty { parts.append("폴더 \(library.folders.count)개") }
        let total = games.reduce(0) { $0 + $1.playSeconds }
        if total >= 60 { parts.append("총 플레이 \(Game.formattedPlayTime(total))") }
        return parts.joined(separator: " · ")
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
                    SecretBoxIcon(open: true)
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("시크릿 박스")
                            .font(.system(size: 30, weight: .bold))
                        Text("숨긴 게임 \(hidden.count)개 · 목록·홈·검색에는 나타나지 않아요")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    Button {
                        secret.lock()
                    } label: {
                        Label("잠그기", systemImage: "lock.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                if hidden.isEmpty {
                    Text("숨긴 게임이 없어요. 게임을 우클릭해서 '숨기기'를 누르면 여기로 옮겨져요.")
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    HomeGrid(games: hidden)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 44)
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
