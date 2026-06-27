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
                    if !favorites.videos.isEmpty { videosSection }
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

    private var videosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Saved videos")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 16)],
                      alignment: .leading, spacing: 20) {
                ForEach(favorites.videos) { video in
                    NavigationLink(value: Route.video(id: video.id, title: video.title)) {
                        VideoThumbnail(video: videoSummary(for: video))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Remove from Favorites", systemImage: "star.slash") {
                            app.favorites.toggleVideo(video)
                        }
                    }
                }
            }
        }
    }

    /// Map a saved video onto the `VideoSummary` the shared `VideoThumbnail`
    /// draws. The poster card shows only title, artist, and the LIVE/4K badges,
    /// so the fields `FavVideo` doesn't persist (performanceDate, eventStart,
    /// has4K) are left nil/false. Opening the card re-fetches full detail via
    /// `Route.video`, so the saved `videoSku` isn't needed to reopen.
    private func videoSummary(for fav: FavVideo) -> VideoSummary {
        VideoSummary(id: fav.id, title: fav.title, artistName: fav.artistName,
                     performanceDate: nil, imagePath: fav.imageURL, isLive: fav.isLive,
                     eventStart: nil, has4K: false)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "star")
                .font(.system(size: 34))
                .foregroundStyle(theme.palette.accent)
            Text("Nothing saved yet")
                .font(theme.type.hero(22))
                .foregroundStyle(theme.palette.textPrimary)
            Text("Star an artist, show, or video to keep it here.")
                .font(theme.type.body(13))
                .foregroundStyle(theme.palette.textSecondary)
        }
    }
}
