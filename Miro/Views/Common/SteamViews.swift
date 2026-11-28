//
//  SteamViews.swift
//  Miro
//
//  Steam in the sidebar: "Steam 열기" (always there; installs Steam first when it is missing), the account signed in
//  to the Steam app, and the library preview read from Steam's own files. Games are downloaded and run in Steam;
//  Miro shows them and opens their page in Steam ("Steam에서 보기").
//

import SwiftUI

/// What the Steam client is doing, in one short line
@MainActor
func steamStatusLine(_ client: SteamClient, account: SteamAccount) -> String {
    switch client.state {
    case .notInstalled:
        return EngineManager.shared.isReady(.miroe) ? "눌러서 Steam 설치 (\(SteamClient.installerSize))" : "miroe 엔진을 먼저 준비해 주세요"
    case .installing(let step):
        return step
    case .failed(let message):
        return message
    case .installed:
        if let profile = account.profile { return client.isRunning ? "\(profile.name) · 실행 중" : profile.name }
        return client.isRunning ? "Steam 창에서 로그인해 주세요" : "눌러서 Steam 열기 · 로그인은 Steam 창에서"
    }
}

/// Installs Steam when it is missing, otherwise opens it
@MainActor
func openSteam() {
    let client = SteamClient.shared
    switch client.state {
    case .installing:
        return
    case .notInstalled, .failed:
        Task {
            await client.installClient()
            if client.isInstalled { client.start() }
        }
    case .installed:
        client.start()
    }
}

/// Bottom of the sidebar: Steam, the account's round avatar, and its state. Click: the account menu when signed in
/// to the Steam app, otherwise open (or install) Steam
struct SteamSidebarRow: View {
    @EnvironmentObject private var steam: SteamAccount
    @ObservedObject private var client = SteamClient.shared
    @State private var hovering = false
    @State private var showingMenu = false

    var body: some View {
        Button {
            if steam.isLoggedIn { showingMenu.toggle() } else { openSteam() }
        } label: {
            HStack(spacing: 10) {
                SteamBadge(avatar: steam.avatar, size: 34)
                    .overlay(alignment: .bottomTrailing) {
                        if steam.isLoggedIn {
                            Circle().fill(client.isRunning ? Theme.success : Theme.tertiaryText)
                                .frame(width: 10, height: 10)
                                .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                                .offset(x: 1, y: 1)
                        }
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Steam")
                        .font(.system(size: 13, weight: .semibold))
                    Text(steamStatusLine(client, account: steam))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 2)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering ? Theme.fill : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(steam.isLoggedIn ? "Steam 계정" : "Steam 열기")
        .popover(isPresented: $showingMenu, arrowEdge: .top) {
            SteamAccountPopover(close: { showingMenu = false })
                .environmentObject(steam)
        }
    }
}

private struct SteamAccountPopover: View {
    @EnvironmentObject private var steam: SteamAccount
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                SteamBadge(avatar: steam.avatar, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(steam.profile?.name ?? "Steam")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Steam 앱에 로그인됨 · 게임 \(steam.ownedGames.count)개")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Divider()
            Button { SteamClient.shared.start(); close() } label: {
                Label("Steam 열기", systemImage: "arrow.up.forward.app")
            }
            Button { steam.pageOpen = true; GameLibrary.shared.selectedID = nil; close() } label: {
                Label("라이브러리 미리보기", systemImage: "square.grid.2x2")
            }
            if let url = steam.profileURL {
                Link(destination: url) { Label("Steam 프로필 (브라우저)", systemImage: "person.crop.circle") }
            }
            Button { steam.refresh() } label: {
                Label("새로고침", systemImage: "arrow.clockwise")
            }
            Text("로그인과 로그아웃은 Steam 창에서 해요.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
        }
        .buttonStyle(.plain)
        .font(.system(size: 13))
        .padding(16)
        .frame(width: 250)
    }
}

/// The account's avatar in a circle, or a plain round controller badge before signing in
struct SteamBadge: View {
    var avatar: NSImage?
    var size: CGFloat

    var body: some View {
        ZStack {
            if let avatar {
                Image(nsImage: avatar)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [Color(red: 0.11, green: 0.16, blue: 0.27), Color(red: 0.16, green: 0.31, blue: 0.52)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
    }
}

// MARK: - Sidebar section

/// "Steam 열기" at the top of the Steam part of the sidebar: always there, installs Steam first when it is missing
struct SteamOpenRow: View {
    @EnvironmentObject private var steam: SteamAccount
    @ObservedObject private var client = SteamClient.shared

    var body: some View {
        SidebarItemRow(isSelected: false, isDropTarget: false, action: openSteam) {
            SteamBadge(avatar: steam.avatar, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Steam 열기")
                    .font(.system(size: 13, weight: .semibold))
                Text(steamStatusLine(client, account: steam))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if case .installing = client.state { ProgressView().controlSize(.mini) }
        }
        .help(client.isInstalled ? "Steam 창을 열어요" : "Steam을 설치하고 열어요")
    }
}

/// The library preview in the sidebar while the Steam app is signed in: click opens the preview page, the arrow
/// drops the games down
struct SteamSidebarSection: View {
    let filter: String
    @EnvironmentObject private var steam: SteamAccount
    @AppStorage("steamSectionExpanded") private var expanded = false

    var body: some View {
        let games = steam.ownedGames.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }
        VStack(alignment: .leading, spacing: 1) {
            SidebarItemRow(isSelected: steam.pageOpen && GameLibrary.shared.selectedID == nil, isDropTarget: false,
                           action: { steam.pageOpen = true; GameLibrary.shared.selectedID = nil }) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(expanded || !filter.isEmpty ? 90 : 0))
                        .frame(width: 14, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondaryText)
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 22)
                Text("라이브러리 미리보기")
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 4)
                Text("\(games.count)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
            }
            if expanded || !filter.isEmpty {
                ForEach(games) { game in
                    SteamOwnedRow(game: game)
                }
            }
        }
    }
}

/// One game of the library preview in the sidebar: selects it when it is in Miro's library, and opens it in Steam
struct SteamOwnedRow: View {
    let game: SteamAccount.OwnedGame
    @ObservedObject private var client = SteamClient.shared
    @EnvironmentObject private var library: GameLibrary

    var body: some View {
        let installed = client.libraryGame(game.appid)
        SidebarItemRow(isSelected: installed != nil && library.selectedID == installed?.id, isDropTarget: false,
                       action: { if let installed { library.selectedID = installed.id } else { client.openInSteam(game.appid) } }) {
            Color.clear.frame(width: 14)
            AsyncImage(url: game.headerURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 5).fill(Theme.fill)
            }
            .frame(width: 24, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text(game.name)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
                .opacity(installed == nil ? 0.75 : 1)
            Spacer(minLength: 4)
            SteamViewButton(appID: game.appid, compact: true)
        }
    }
}

/// "Steam에서 보기": the game's page in Steam's own library (or its store page)
struct SteamViewButton: View {
    let appID: Int
    var compact = false
    var store = false

    var body: some View {
        Button {
            SteamClient.shared.openInSteam(appID, store: store)
        } label: {
            if compact {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.accent)
            } else {
                Label("Steam에서 보기", systemImage: "arrow.up.right.square")
            }
        }
        .buttonStyle(compact ? AnyButtonStyle(PlainButtonStyle()) : AnyButtonStyle(BorderedButtonStyle()))
        .help("Steam에서 보기")
    }
}

/// Lets one call site switch between two button styles
struct AnyButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: PrimitiveButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

// MARK: - Library preview page

/// The main-area Steam page: the account signed in to the Steam app, "Steam 열기", the library preview, and store search
struct SteamPageView: View {
    @EnvironmentObject private var steam: SteamAccount
    @ObservedObject private var client = SteamClient.shared
    @State private var query = ""
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        let owned = steam.ownedGames.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                openCard
                searchField

                if !query.isEmpty {
                    storeSection
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 7) {
                        Text(query.isEmpty ? "라이브러리 미리보기" : "라이브러리에서 찾음")
                            .font(.system(size: 19, weight: .bold))
                        Text("\(owned.count)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                        Spacer()
                    }
                    if steam.ownedGames.isEmpty {
                        Text(steam.isLoggedIn
                             ? "Steam이 라이브러리를 아직 받지 않았어요. Steam 창에서 라이브러리를 한 번 열면 여기에 보여요."
                             : "Steam 창에서 로그인하면 여기에 라이브러리가 보여요.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Text("다운로드와 실행은 Steam에서 해요. 다운로드가 끝난 게임은 Miro 라이브러리에 저절로 들어와요.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 18, alignment: .top)],
                              alignment: .leading, spacing: 20) {
                        ForEach(owned) { game in
                            SteamGameCard(appID: game.appid, name: game.name, subtitle: status(game.appid))
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 40)
            .padding(.bottom, 36)
        }
        .onChange(of: query) { _, term in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await steam.searchStore(term)
            }
        }
        .task { client.scanManifests() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            SteamBadge(avatar: steam.avatar, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text("Steam")
                    .font(.system(size: 30, weight: .bold))
                Text(steam.profile.map { "\($0.name) · 게임 \(steam.ownedGames.count)개" } ?? "Steam 앱에 로그인하지 않았어요")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Button {
                steam.refresh()
            } label: {
                Label("새로고침", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }

    /// "Steam 열기": the Steam app downloads, updates and runs the games
    private var openCard: some View {
        HStack(spacing: 14) {
            SteamBadge(avatar: nil, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text("Steam 열기")
                    .font(.system(size: 13.5, weight: .semibold))
                Text(steamStatusLine(client, account: steam))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if case .installing = client.state {
                ProgressView().controlSize(.small)
            } else {
                Button(client.isInstalled ? "Steam 열기" : "Steam 설치") { openSteam() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.separator.opacity(0.6), lineWidth: 0.5))
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondaryText)
            TextField("Steam 게임 검색 (라이브러리와 스토어)", text: $query)
                .textFieldStyle(.plain)
            if steam.isSearching { ProgressView().controlSize(.small) }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.tertiaryText) }
                    .buttonStyle(.plain)
            }
        }
        .font(.system(size: 14))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var storeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Steam 스토어")
                .font(.system(size: 19, weight: .bold))
            if steam.storeResults.isEmpty && !steam.isSearching {
                Text("'\(query)'와(과) 일치하는 게임이 스토어에 없어요")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 18, alignment: .top)],
                      alignment: .leading, spacing: 20) {
                ForEach(steam.storeResults) { item in
                    SteamGameCard(appID: item.id, name: item.name,
                                  subtitle: steam.owns(item.id) ? "라이브러리에 있어요" : "스토어", store: !steam.owns(item.id))
                }
            }
        }
    }

    /// Where the game is: in Miro's library, downloading in Steam, or not installed
    private func status(_ appID: Int) -> String {
        if client.libraryGame(appID) != nil { return "설치됨 · Miro 라이브러리에 있어요" }
        if let download = client.downloads[appID] {
            return download.phase + (download.progress.map { " · \(Int($0 * 100))%" } ?? "")
        }
        return "설치 안 됨"
    }
}

/// A Steam game's header image, name, where it is, and "Steam에서 보기"
struct SteamGameCard: View {
    let appID: Int
    let name: String
    let subtitle: String
    var store = false
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AsyncImage(url: SteamAccount.headerURL(appID)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    Theme.fill
                    Image(systemName: "gamecontroller").font(.system(size: 26)).foregroundStyle(Theme.tertiaryText)
                }
            }
            .aspectRatio(460 / 215, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.separator.opacity(0.6), lineWidth: 0.5))
            .shadow(color: .black.opacity(hovering ? 0.2 : 0.07), radius: hovering ? 10 : 4, y: hovering ? 5 : 2)
            .scaleEffect(hovering ? 1.012 : 1)

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 4)
                SteamViewButton(appID: appID, store: store)
                    .controlSize(.small)
            }
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}
