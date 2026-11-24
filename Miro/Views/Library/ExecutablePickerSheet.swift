//
//  ExecutablePickerSheet.swift
//  Miro
//
//  A dropped game folder contains several .exe files — pick the one that starts the game.
//

import SwiftUI

struct ExecutablePickerSheet: View {
    let choice: FolderChoice
    @EnvironmentObject private var library: GameLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("어떤 파일로 실행할까요?")
                        .font(.system(size: 18, weight: .bold))
                    Text("'\(choice.folder.lastPathComponent)' 폴더에서 실행 파일을 \(choice.candidates.count)개 찾았어요.\n폴더 전체를 Miro(C:\\Games)로 복사한 뒤 선택한 파일로 실행해요.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(22)

            Divider()

            List(selection: $selection) {
                ForEach(Array(choice.candidates.enumerated()), id: \.element) { index, path in
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: choice.folder.appending(path: path).path))
                            .resizable()
                            .frame(width: 26, height: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text((path as NSString).lastPathComponent)
                                    .font(.system(size: 13, weight: .medium))
                                if index == 0 {
                                    Text("추천")
                                        .font(.system(size: 10, weight: .semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Theme.accent, in: Capsule())
                                        .overlay(Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 0.5))
                                        .foregroundStyle(.white)
                                }
                            }
                            Text(path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Text(size(of: path))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.vertical, 3)
                    .tag(path)
                }
            }
            .listStyle(.inset)

            Divider()

            HStack {
                Spacer()
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("복사하고 추가") {
                    guard let selection else { return }
                    dismiss()
                    library.startImport(choice.folder, executable: selection)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil)
            }
            .padding(16)
        }
        .frame(width: 560, height: 460)
        .onAppear { selection = choice.candidates.first }
    }

    private func size(of path: String) -> String {
        let attributes = try? FileManager.default.attributesOfItem(
            atPath: choice.folder.appending(path: path).path(percentEncoded: false))
        return ((attributes?[.size] as? NSNumber)?.int64Value ?? 0).byteString
    }
}

/// Sidebar row for a folder that is being copied into Miro
struct ImportRow: View {
    let job: ImportJob

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill.badge.plus")
                .font(.system(size: 17))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(job.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                ProgressView(value: job.progress)
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                Text("복사 중 \(Int(job.progress * 100))% · \(job.detail)")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}
