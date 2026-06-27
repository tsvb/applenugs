import SwiftUI

/// Player-style header: a reused EQ/VU strip, an LCD-style summary panel, and
/// the Follow control. The LCD line truncates if it overflows (a scrolling
/// marquee is a deferred enhancement).
struct CrateHeader: View {
    let artist: ArtistEntry
    let albumCount: Int
    let videoCount: Int
    let showCount: Int

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            EqualizerBars(isPlaying: app.player.isPlaying)
            lcd
            followButton
        }
    }

    private var lcd: some View {
        Text(summary)
            .font(theme.type.numeric(12))
            .foregroundStyle(theme.palette.accent)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(theme.palette.base.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(theme.palette.hairline, lineWidth: 0.5))
            .accessibilityLabel(summary)
    }

    private var summary: String {
        let name = theme.caps.contains(.condensedHeaders) ? artist.name.uppercased() : artist.name
        var parts: [String] = []
        if videoCount > 0 { parts.append("\(videoCount) videos") }
        if showCount > 0 { parts.append("\(showCount) shows") }
        if albumCount > 0 { parts.append("\(albumCount) albums") }
        let tail = parts.joined(separator: " · ")
        return tail.isEmpty ? name : "\(name) — \(tail)"
    }

    private var followButton: some View {
        let fav = app.favorites.isArtistFavorited(artist.id)
        return Button {
            app.favorites.toggleArtist(id: artist.id, name: artist.name)
        } label: {
            Label(fav ? "Following" : "Follow", systemImage: fav ? "star.fill" : "star")
                .font(theme.type.body(12))
        }
        .buttonStyle(.bordered)
        .tint(fav ? theme.palette.accent : theme.palette.textSecondary)
        .help(fav ? "Unfollow artist" : "Follow artist")
    }
}
