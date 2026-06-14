import SwiftUI

/// The Favorites destination: followed artists as text chips, then saved shows
/// as a cover-art grid (newest saved first). Stacked sections, fully themed.
struct FavoritesView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    private var favorites: FavoritesStore { app.favorites }

    var body: some View {
        ScrollView {
            if favorites.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, minHeight: 360)
            } else {
                VStack(alignment: .leading, spacing: 26) {
                    if !favorites.artists.isEmpty { artistsSection }
                    if !favorites.shows.isEmpty { showsSection }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(theme.palette.base)
        .navigationTitle("Favorites")
    }

    private func sectionTitle(_ text: String) -> some View {
        let condensed = theme.caps.contains(.condensedHeaders)
        return Text(condensed ? text.uppercased() : text)
            .font(theme.type.section(17))
            .tracking(condensed ? 1.4 : 0)
            .foregroundStyle(theme.palette.textPrimary)
    }

    private var artistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Artists")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 10)],
                      alignment: .leading, spacing: 10) {
                ForEach(favorites.artists) { fav in
                    NavigationLink(value: Route.artist(ArtistEntry(id: fav.id, name: fav.name))) {
                        HStack {
                            Text(fav.name)
                                .font(theme.type.body(13))
                                .foregroundStyle(theme.palette.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(theme.palette.raised)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Remove from Favorites", systemImage: "star.slash") {
                            app.favorites.toggleArtist(id: fav.id, name: fav.name)
                        }
                    }
                }
            }
        }
    }

    private var showsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Saved shows")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 16)],
                      alignment: .leading, spacing: 16) {
                ForEach(favorites.shows) { show in
                    NavigationLink(value: Route.album(id: show.id, title: show.title)) {
                        ShowCard(show: show, width: 150)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Remove from Favorites", systemImage: "star.slash") {
                            app.favorites.toggleShow(id: show.id, title: show.title,
                                                     artistName: show.artistName,
                                                     dateText: show.dateText, venue: show.venue,
                                                     imageURL: show.imageURL)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "star")
                .font(.system(size: 34))
                .foregroundStyle(theme.palette.accent)
            Text("Nothing saved yet")
                .font(theme.type.hero(22))
                .foregroundStyle(theme.palette.textPrimary)
            Text("Star an artist or a show to keep it here.")
                .font(theme.type.body(13))
                .foregroundStyle(theme.palette.textSecondary)
        }
    }
}
