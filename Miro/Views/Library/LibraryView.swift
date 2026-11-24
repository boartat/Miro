//
//  LibraryView.swift
//  Miro
//
//  20 % sidebar (홈, folders, games / secret box) on the left, 80 % page on the right.
//

import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: GameLibrary
    @EnvironmentObject private var secret: SecretBox

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: max(200, geometry.size.width * 0.2))
                Rectangle()
                    .fill(Theme.separator)
                    .frame(width: 0.5)
                Group {
                    if let game = library.game(library.selectedID), !game.isHidden || secret.isUnlocked {
                        GameDetailView(game: game)
                            .id(game.id)
                    } else if secret.isUnlocked {
                        SecretBoxHomeView()
                    } else {
                        HomeView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.window)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject private var library: GameLibrary
    @EnvironmentObject private var launcher: GameLauncher
    @EnvironmentObject private var secret: SecretBox
    @State private var filter = ""
    @State private var dropTarget: String?
    @State private var folderPrompt: FolderPrompt?
    @State private var folderName = ""

    /// "새 폴더" naming alert: creating from checkboxes, after a drag, or renaming
    enum FolderPrompt: Identifiable {
        case create
        case rename(UUID)
        var id: String {
            switch self {
            case .create: return "create"
            case .rename(let id): return id.uuidString
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 38) // traffic lights

            header
            searchField
            if !secret.isUnlocked {
                Picker("정렬", selection: $library.sortOrder) {
                    ForEach(GameLibrary.SortOrder.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 12)
                .padding(.top, 10)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    if secret.isUnlocked {
                        secretList
                    } else {
                        normalList
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.automatic)

            footer
        }
        .background(VisualEffectView(material: .sidebar))
        .animation(.easeInOut(duration: 0.18), value: library.selectionMode)
        .animation(.easeInOut(duration: 0.18), value: secret.isUnlocked)
        .alert(folderPromptTitle, isPresented: folderPromptBinding) {
            TextField("폴더 이름", text: $folderName)
            Button("취소", role: .cancel) {}
            Button(folderPromptIsCreate ? "만들기" : "확인") { commitFolderPrompt() }
        } message: {
            Text(folderPromptIsCreate ? "선택한 게임 \(library.checked.count)개로 폴더를 만들어요" : "폴더 이름을 입력하세요")
        }
    }

    // MARK: Header / search

    private var header: some View {
        HStack(alignment: .center) {
            if secret.isUnlocked {
                Label("시크릿 박스", systemImage: "lock.open.fill")
                    .font(.system(size: 18, weight: .bold))
                    .labelStyle(.titleAndIcon)
            } else {
                Text("라이브러리")
                    .font(.system(size: 20, weight: .bold))
            }
            Spacer()
            if secret.isUnlocked {
                Menu {
                    Button("비밀번호 변경…") { secret.request = .change }
                    Button("잠그기") { secret.lock() }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 15))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            } else {
                Button {
                    AddGamePanel.present()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(Theme.accent, in: Circle())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .help("게임 추가 (⌘O) — exe 파일이나 게임 폴더를 창에 끌어다 놓아도 돼요")
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.secondaryText)
            TextField(secret.isUnlocked ? "숨긴 게임 검색" : "검색", text: $filter)
                .textFieldStyle(.plain)
            if !filter.isEmpty {
                Button { filter = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 12)
    }

    // MARK: Lists

    @ViewBuilder
    private var normalList: some View {
        SidebarItemRow(
            isSelected: library.selectedID == nil && !library.selectionMode,
            isDropTarget: dropTarget == "home",
            action: { library.selectedID = nil }
        ) {
            Image(systemName: "house.fill")
                .font(.system(size: 14))
                .foregroundStyle(library.selectedID == nil ? Color.white : Theme.accent)
                .frame(width: 30, height: 30)
            Text("홈")
                .font(.system(size: 13, weight: .semibold))
        }
        .dropDestination(for: GameDragItem.self) { items, _ in
            items.forEach { library.removeFromFolder($0.gameID) }
            return !items.isEmpty
        } isTargeted: { dropTarget = $0 ? "home" : (dropTarget == "home" ? nil : dropTarget) }
        .help("게임을 여기로 끌어오면 폴더에서 빠져요")

        let folders = library.sortedFolders
        let ungrouped = library.ungroupedGames(filter: filter)
        let total = library.sorted(filter: filter).count

        Text(filter.isEmpty ? "게임 · \(total)" : "검색 결과 · \(total)")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 8)
            .padding(.top, 12)
            .padding(.bottom, 4)

        ForEach(folders) { folder in
            let games = library.games(in: folder, filter: filter)
            if filter.isEmpty || !games.isEmpty {
                folderRow(folder, count: games.count)
                if folder.isExpanded || !filter.isEmpty {
                    ForEach(games) { game in
                        gameRow(game, indent: true)
                            .id("folder-\(folder.id)-\(game.id)")
                    }
                }
            }
        }
        ForEach(ungrouped) { game in
            gameRow(game, indent: false)
        }

        if total == 0 && !filter.isEmpty {
            Text("'\(filter)'와(과) 일치하는 게임이 없어요")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .padding(10)
        }
        ForEach(library.imports) { job in
            ImportRow(job: job).padding(.horizontal, 6)
        }
    }

    @ViewBuilder
    private var secretList: some View {
        let hidden = library.sorted(filter: filter, hidden: true)
        Text("숨긴 게임 · \(hidden.count)")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 4)
        if hidden.isEmpty {
            Text(filter.isEmpty ? "숨긴 게임이 없어요.\n게임을 우클릭해서 '숨기기'를 누르면 여기로 와요." : "일치하는 게임이 없어요")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .padding(10)
        }
        ForEach(hidden) { game in
            gameRow(game, indent: false)
        }
    }

    private func folderRow(_ folder: GameFolder, count: Int) -> some View {
        SidebarItemRow(
            isSelected: false,
            isDropTarget: dropTarget == "folder:\(folder.id)",
            action: { withAnimation(.easeInOut(duration: 0.15)) { library.toggleFolder(folder.id) } }
        ) {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.secondaryText)
                .rotationEffect(.degrees(folder.isExpanded || !filter.isEmpty ? 90 : 0))
                .frame(width: 10)
            Image(systemName: "folder.fill")
                .font(.system(size: 15))
                .foregroundStyle(Theme.accent)
                .frame(width: 18)
            Text(folder.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("\(count)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
        }
        .dropDestination(for: GameDragItem.self) { items, _ in
            items.forEach { library.addToFolder($0.gameID, folderID: folder.id) }
            return !items.isEmpty
        } isTargeted: { targeted in
            let key = "folder:\(folder.id)"
            dropTarget = targeted ? key : (dropTarget == key ? nil : dropTarget)
        }
        .contextMenu {
            Button("이름 변경…") {
                folderName = folder.name
                folderPrompt = .rename(folder.id)
            }
            Button("폴더 풀기") { library.dissolveFolder(folder.id) }
        }
    }

    private func gameRow(_ game: Game, indent: Bool) -> some View {
        let key = "game:\(game.id)"
        let checking = library.selectionMode && !secret.isUnlocked
        return SidebarItemRow(
            isSelected: !checking && library.selectedID == game.id,
            isDropTarget: dropTarget == key,
            action: {
                if checking { library.toggleChecked(game.id) } else { library.selectedID = game.id }
            }
        ) {
            if indent { Color.clear.frame(width: 14) }
            if checking {
                Image(systemName: library.checked.contains(game.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(library.checked.contains(game.id) ? Theme.accent : Theme.tertiaryText)
                    .transition(.scale.combined(with: .opacity))
            }
            GameIconView(game: game, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(game.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Group {
                    if launcher.isRunning(game.id) {
                        Text("실행 중").foregroundStyle(Theme.play)
                    } else if !game.exists {
                        Text("파일 없음").foregroundStyle(Theme.warning)
                    } else {
                        Text(game.lastPlayedAt == nil ? game.engine.shortName : Game.relativeDate(game.lastPlayedAt))
                    }
                }
                .font(.system(size: 11))
                .opacity(0.75)
            }
            Spacer(minLength: 0)
            if launcher.isRunning(game.id) {
                Circle().fill(Theme.play).frame(width: 7, height: 7)
            }
        }
        .draggable(GameDragItem(gameID: game.id)) {
            HStack(spacing: 8) {
                GameIconView(game: game, size: 24)
                Text(game.name).font(.system(size: 12, weight: .medium))
            }
            .padding(6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .dropDestination(for: GameDragItem.self) { items, _ in
            guard !secret.isUnlocked else { return false }
            var createdFolder: UUID?
            for item in items {
                createdFolder = library.drop(item.gameID, onto: game.id) ?? createdFolder
            }
            if let createdFolder {
                folderName = "새 폴더"
                folderPrompt = .rename(createdFolder)
            }
            return !items.isEmpty
        } isTargeted: { targeted in
            dropTarget = targeted ? key : (dropTarget == key ? nil : dropTarget)
        }
        .contextMenu { GameContextMenu(game: game) }
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            if library.selectionMode && !secret.isUnlocked {
                HStack(spacing: 8) {
                    Text("\(library.checked.count)개 선택")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button("취소") { library.endFolderSelection() }
                        .controlSize(.small)
                    Button("폴더 만들기") {
                        folderName = "새 폴더"
                        folderPrompt = .create
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(library.checked.isEmpty)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            } else {
                InstallProgressFooter()
                HStack(spacing: 8) {
                    SecretBoxButton()
                    Spacer()
                    SettingsLink {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.borderless)
                    .help("설정 · 라이브러리 관리")
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: Folder prompt

    private var folderPromptBinding: Binding<Bool> {
        Binding(get: { folderPrompt != nil }, set: { if !$0 { folderPrompt = nil } })
    }

    private var folderPromptIsCreate: Bool {
        if case .create = folderPrompt { return true }
        return false
    }

    private var folderPromptTitle: String {
        folderPromptIsCreate ? "새 폴더" : "폴더 이름"
    }

    private func commitFolderPrompt() {
        switch folderPrompt {
        case .create:
            library.createFolder(named: folderName, with: Array(library.checked))
            library.endFolderSelection()
        case .rename(let id):
            library.renameFolder(id, to: folderName)
        case nil:
            break
        }
        folderPrompt = nil
    }
}

/// Apple-style sidebar row: accent highlight when selected (grey when the window is inactive)
struct SidebarItemRow<Content: View>: View {
    let isSelected: Bool
    var isDropTarget = false
    let action: () -> Void
    @ViewBuilder var content: () -> Content
    @Environment(\.controlActiveState) private var activeState
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            content()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .foregroundStyle(isSelected && activeState != .inactive ? Color.white : Color.primary)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.accent, lineWidth: isDropTarget ? 2 : 0)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { hovering = $0 }
    }

    private var background: Color {
        if isDropTarget { return Theme.accent.opacity(0.15) }
        if isSelected { return activeState == .inactive ? Color.gray.opacity(0.25) : Theme.accent }
        return hovering ? Theme.fill : .clear
    }
}

struct GameContextMenu: View {
    let game: Game
    @EnvironmentObject private var library: GameLibrary
    @EnvironmentObject private var launcher: GameLauncher
    @EnvironmentObject private var secret: SecretBox

    var body: some View {
        Button(launcher.isRunning(game.id) ? "중지" : "플레이") {
            if launcher.isRunning(game.id) { launcher.stop(game) } else { launcher.launch(game) }
        }
        Divider()
        Button("Finder에서 보기") {
            NSWorkspace.shared.activateFileViewerSelecting([game.executableURL])
        }
        Button("경로 복사") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(game.executablePath, forType: .string)
        }
        Divider()
        if game.isHidden {
            Button("숨기기 해제") { library.setHidden(game.id, false) }
        } else {
            Button("폴더 만들기…") { library.beginFolderSelection(with: game.id) }
            let others = library.sortedFolders.filter { !$0.gameIDs.contains(game.id) }
            if !others.isEmpty {
                Menu("폴더로 이동") {
                    ForEach(others) { folder in
                        Button(folder.name) { library.addToFolder(game.id, folderID: folder.id) }
                    }
                }
            }
            if library.folder(containing: game.id) != nil {
                Button("폴더에서 빼기") { library.removeFromFolder(game.id) }
            }
            Divider()
            Button("숨기기") {
                if secret.hasPassword {
                    library.setHidden(game.id, true)
                } else {
                    secret.request = .create(hideAfter: game.id)
                }
            }
        }
        Divider()
        Button("라이브러리에서 제거…", role: .destructive) {
            library.requestRemove(game.id)
        }
    }
}

/// Background library installs (shown above the footer only while something installs)
struct InstallProgressFooter: View {
    @EnvironmentObject private var installs: InstallCenter

    var body: some View {
        if installs.isBusy, let current = installs.currentID,
           let dependency = DependencyCatalog.dependency(current) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(dependency.name) 설치 중 · 남은 항목 \(installs.pendingCount)개")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                ProgressView(value: installs.job(current)?.progress ?? 0)
                    .progressViewStyle(.linear)
                    .controlSize(.small)
            }
            .padding(.horizontal, 14)
        }
    }
}
