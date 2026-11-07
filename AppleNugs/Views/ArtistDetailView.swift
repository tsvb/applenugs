import SwiftUI

/// Artist landing page (catalog.containersAll): releases + live shows + videos
/// presented via the CrateHeader / CrateList library components.
struct ArtistDetailView: View {
    let artist: ArtistEntry

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    @State private var containers: [ContainerSummary] = []
    @State private var loading = false
    @State private var error: String?
    @State private var videos: [VideoSummary] = []

    private static let pageSize = ArtistCatalogPaging.pageSize

    // Mapped once per data load, not per body evaluation: CrateItem
    // construction parses each container's date (ContainerSummary.date is
    // computed via DateFormatter) and builds its search haystack, so computing
    // these in body re-parsed the whole page on every render.
    @State private var albumItems: [CrateItem] = []
    @State private var showItems: [CrateItem] = []
    @State private var videoItems: [CrateItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CrateHeader(artist: artist,
                        albumCount: albumItems.count,
                        videoCount: videoItems.count,
                        showCount: showItems.count)
                .padding(.horizontal, 20)
                .padding(.top, 20)

            CrateList(albums: albumItems,
                      videos: videoItems,
                      shows: showItems,
                      loading: loading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.palette.base)
        .navigationTitle(artist.name)
        .compactNavigationTitle()
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
        .task(id: artist.id) { await load() }
    }

    /// Fetch every page up front. The catalog pages 100 at a time, so a deep
    /// artist is ~5 requests (capped at `ArtistCatalogPaging.maxPages`, and a
    /// short page ends it); the list renders what has arrived and the footer
    /// says more is coming. Paging is deliberately NOT driven from inside the
    /// list: the old outline triggered it from an `onAppear` on a 1pt spacer
    /// nested in the very LazyVStack that each page then mutated.
    ///
    /// A complete load is kept on `AppModel` for 30 minutes, so coming back
    /// to the artist (the usual back-and-forth from a show) makes no requests.
    private func load() async {
        containers = []
        albumItems = []
        showItems = []
        videoItems = []
        videos = []
        error = nil
        // Videos are one independent request; run them alongside the paged
        // shows. `Task {}` rather than `async let` — the View isn't Sendable.
        Task { await loadVideos() }

        if let cached = app.cachedArtistShows(id: artist.id) {
            containers = cached
            rebuildItems()
            return
        }

        loading = true
        defer { loading = false }
        do {
            var lastPageCount = Self.pageSize
            var pagesFetched = 0
            while ArtistCatalogPaging.shouldFetchAnother(lastPageCount: lastPageCount,
                                                         pagesFetched: pagesFetched,
                                                         pageSize: Self.pageSize) {
                let json = try await app.client.artistShows(
                    id: artist.id, offset: containers.count + 1, limit: Self.pageSize)
                let page = Catalog.containers(from: json)
                pagesFetched += 1
                lastPageCount = page.count
                containers += page
                rebuildItems()
                if Task.isCancelled { return }
            }
            // Only a load that ran to its end is reused: an error or a
            // navigation away mid-paging leaves nothing behind.
            app.storeArtistShows(containers, id: artist.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func rebuildItems() {
        albumItems = containers.filter { !$0.isLiveShow }.map { CrateItem.album($0, artist: artist.name) }
        showItems = containers.filter(\.isLiveShow).map { CrateItem.show($0, artist: artist.name) }
    }

    /// Videos load independently of the paged shows list: a single
    /// videoReleaseType=6 call. A video failure is swallowed (the section just
    /// stays empty) so it never blocks the shows/releases the user came for.
    private func loadVideos() async {
        if let cached = app.cachedArtistVideos(id: artist.id) {
            videos = cached
        } else {
            do {
                let fetched = try await app.client.artistVideos(id: artist.id)
                videos = fetched
                app.storeArtistVideos(fetched, id: artist.id)
            } catch {
                videos = []
            }
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
