import SwiftUI

/// Artist landing page (catalog.containersAll): releases + live shows + videos
/// presented via the CrateHeader / CrateOutline library outline components.
struct ArtistDetailView: View {
    let artist: ArtistEntry

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    @State private var containers: [ContainerSummary] = []
    @State private var loading = false
    @State private var error: String?
    @State private var canLoadMore = false
    @State private var videos: [VideoSummary] = []

    private static let pageSize = 100

    // Mapped once per data load, not per body evaluation: CrateItem
    // construction parses each container's date (ContainerSummary.date is
    // computed via DateFormatter), so computing these in body re-parsed the
    // whole page on every render.
    @State private var albumItems: [CrateItem] = []
    @State private var showItems: [CrateItem] = []
    @State private var videoItems: [CrateItem] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                CrateHeader(artist: artist,
                            albumCount: albumItems.count,
                            videoCount: videoItems.count,
                            showCount: showItems.count)

                CrateOutline(albums: albumItems,
                             videos: videoItems,
                             shows: showItems,
                             canLoadMore: canLoadMore,
                             loading: loading,
                             loadMore: { Task { await load(reset: false) } })
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.palette.base)
        .navigationTitle(artist.name)
        .overlay {
            if loading && containers.isEmpty {
                ProgressView()
            } else if let error, containers.isEmpty {
                ContentUnavailableView(
                    "Couldn't load shows",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error))
            }
        }
        .task(id: artist.id) { await load(reset: true) }
    }

    private func load(reset: Bool) async {
        if loading && !reset { return }
        if reset {
            containers = []
            canLoadMore = false
            videos = []
            albumItems = []
            showItems = []
            videoItems = []
            Task { await loadVideos() }
        }
        loading = true
        defer { loading = false }
        do {
            let json = try await app.client.artistShows(
                id: artist.id, offset: containers.count + 1, limit: Self.pageSize)
            let page = Catalog.containers(from: json)
            containers += page
            let releases = containers.filter { !$0.isLiveShow }
            let shows = containers.filter(\.isLiveShow)
            albumItems = releases.map { CrateItem.album($0, artist: artist.name) }
            showItems = shows.map { CrateItem.show($0, artist: artist.name) }
            canLoadMore = page.count >= Self.pageSize
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Videos load independently of the paged shows list: a single
    /// videoReleaseType=6 call. A video failure is swallowed (the section just
    /// stays empty) so it never blocks the shows/releases the user came for.
    private func loadVideos() async {
        do {
            videos = try await app.client.artistVideos(id: artist.id)
        } catch {
            videos = []
        }
        videoItems = videos.map { CrateItem.video($0, artist: artist.name) }
    }
}

/// Square cover-art thumbnail with a placeholder while loading / on miss.
/// Used by ShowCard, AlbumDetailView, and formerly by the old releaseGrid.
struct CoverArt: View {
    let url: URL?

    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholder
                    default:
                        placeholder.overlay(ProgressView().controlSize(.small))
                    }
                }
            } else {
                placeholder
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var placeholder: some View {
        Rectangle()
            .fill(theme.palette.raised)
            .overlay(Image(systemName: "music.note").foregroundStyle(theme.palette.accent.opacity(0.7)))
    }
}
