//
//  Theme.swift
//  Miro
//
//  Apple system colours and materials — everything adapts to Light / Dark mode automatically.
//

import AppKit
import SwiftUI

enum Theme {
    static let accent = Color.accentColor                         // systemBlue
    static let play = Color(nsColor: .systemGreen)
    static let stop = Color(nsColor: .systemRed)
    static let warning = Color(nsColor: .systemOrange)
    static let success = Color(nsColor: .systemGreen)
    static let window = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let separator = Color(nsColor: .separatorColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
    static let fill = Color(nsColor: .quaternaryLabelColor).opacity(0.5)

    static let cardRadius: CGFloat = 14
}

/// NSVisualEffectView bridge for real sidebar vibrancy
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

/// Rounded card used for the info sections on the game page
struct Card<Content: View>: View {
    let title: String
    var symbol: String?
    var trailing: AnyView?
    @ViewBuilder var content: () -> Content

    init(_ title: String, symbol: String? = nil, trailing: AnyView? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.symbol = symbol
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .foregroundStyle(Theme.accent)
                }
                Text(title)
                    .font(.headline)
                Spacer()
                if let trailing { trailing }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Theme.separator.opacity(0.6), lineWidth: 0.5)
        )
    }
}

/// Label + value pair ("마지막 실행 / 오늘")
struct StatView: View {
    let label: String
    let value: String
    var symbol: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol).font(.caption).foregroundStyle(Theme.secondaryText)
                }
                Text(value)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
        }
    }
}

/// Key/value row inside a card
struct InfoRow: View {
    let label: String
    let value: String
    var lineLimit: Int?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(lineLimit)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12.5))
    }
}

/// Capsule badge (engine, architecture …)
struct Badge: View {
    let text: String
    var symbol: String?
    var tint: Color = .white

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .foregroundStyle(tint)
    }
}

/// Game icon with a generated fallback (first letter on a tinted tile)
struct GameIconView: View {
    let game: Game
    var size: CGFloat = 28
    @EnvironmentObject private var library: GameLibrary

    var body: some View {
        Group {
            if let icon = library.icon(for: game) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(Self.tint(for: game.name).gradient)
                    .overlay(
                        Text(String(game.name.prefix(1)).uppercased())
                            .font(.system(size: size * 0.48, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    )
            }
        }
        .frame(width: size, height: size)
        .id(library.artworkRevision)
    }

    static func tint(for name: String) -> Color {
        let palette: [NSColor] = [.systemBlue, .systemPurple, .systemPink, .systemOrange, .systemTeal,
                                  .systemIndigo, .systemGreen, .systemRed, .systemMint, .systemCyan]
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Color(nsColor: palette[hash % palette.count])
    }
}
