import SwiftUI

/// The Favorites destination: followed artists as photo tiles (`ArtistTile`, as
/// on Home's crate), then saved shows as a cover-art grid (newest saved first).
/// Stacked sections, fully themed.
struct FavoritesView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    private var favorites: FavoritesStore { app.favorites }

    /// Followed artists' photos, by id. Empty until the lookup lands (and for
    /// good if it fails) — tiles show the monogram meanwhile.
    @State private var avatars: [String: URL] = [:]

    var body: some View {
        ScrollView {
            if favorites.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, minHeight: 360)
            } else {
                VStack(alignment: .leading, spacing: 26) {
                    // `avatars` is read HERE, in body, and handed down. Read only
                    // inside the LazyVGrid's cells, it never registered as a
                    // dependency of this body, so a photo landing after the
                    // grid was built never redrew the tile (Goose stayed a
                    // monogram on Tim's Duo, 2026-11-16).
                    if !favorites.artists.isEmpty { artistsSection(avatars) }
                    if !favorites.shows.isEmpty { showsSection }
                    if !favorites.videos.isEmpty { videosSection }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(theme.palette.base)
        .navigationTitle("Favorites")
        // Re-asks only when the followed set changes; known photos are
        // remembered on AppModel, so a follow adds one lookup, not a refetch.
        .task(id: favorites.artists.map(\.id)) {
            let ids = favorites.artists.map(\.id)
            guard !ids.isEmpty else { return }
            avatars = (try? await app.artistAvatars(ids: ids)) ?? avatars
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(theme.type.section(17))
            .foregroundStyle(theme.palette.textPrimary)
    }

    private func artistsSection(_ avatars: [String: URL]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Artists")
            LazyVGrid(columns: [GridItem(ArtistTile.column, spacing: ArtistTile.spacing)],
                      alignment: .leading, spacing: ArtistTile.spacing) {
                ForEach(favorites.artists) { fav in
                    NavigationLink(value: Route.artist(ArtistEntry(id: fav.id, name: fav.name))) {
                        ArtistTile(name: fav.name, photo: avatars[fav.id])
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

    /// The empty pack.
    private var emptyState: some View {
        EmptyPackMessage(title: "Nothing saved yet",
                         message: "Star an artist, show, or video to keep it here.")
    }
}
