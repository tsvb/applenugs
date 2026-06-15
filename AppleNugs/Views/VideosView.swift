import SwiftUI

/// The Videos sidebar destination. Three stacked sections, all themed:
/// a Continue Watching strip (recent VOD progress), a Live & Upcoming row
/// (webcasts), and a paged On-Demand grid of recently-added VOD. Each card
/// pushes Route.video; VideoDetailView resolves resume position and live edge.
struct VideosView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    @State private var recent: [VideoSummary] = []
    @State private var webcasts: [VideoSummary] = []
    @State private var offset = 0
    @State private var loading = false
    @State private var loadingMore = false
    @State private var reachedEnd = false
    @State private var error: String?

    private let pageSize = 30

    var body: some View {
        ScrollView {
            if loading && recent.isEmpty {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, minHeight: 360)
            } else if let error, recent.isEmpty {
                errorState(error)
                    .frame(maxWidth: .infinity, minHeight: 360)
            } else if recent.isEmpty && webcasts.isEmpty && continueWatching.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, minHeight: 360)
            } else {
                VStack(alignment: .leading, spacing: 28) {
                    if !continueWatching.isEmpty { continueWatchingSection }
                    if !webcasts.isEmpty { liveSection }
                    if !recent.isEmpty { onDemandSection }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(theme.palette.base)
        .navigationTitle("Videos")
        .task { await load() }
    }

    // --- section title (shared idiom) --------------------------------------

    private func sectionTitle(_ text: String) -> some View {
        let condensed = theme.caps.contains(.condensedHeaders)
        return Text(condensed ? text.uppercased() : text)
            .font(theme.type.section(17))
            .tracking(condensed ? 1.4 : 0)
            .foregroundStyle(theme.palette.textPrimary)
    }

    // --- Continue Watching --------------------------------------------------

    private var continueWatching: [VideoProgress] { app.videoProgress.recent }

    private var continueWatchingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Continue Watching")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(continueWatching) { progress in
                        NavigationLink(value: Route.video(id: progress.id, title: progress.title)) {
                            resumeCard(progress)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func resumeCard(_ progress: VideoProgress) -> some View {
        let summary = VideoSummary(id: progress.id, title: progress.title,
                                   artistName: progress.artistName, performanceDate: nil,
                                   imagePath: progress.imageURL, isLive: false,
                                   eventStart: nil, has4K: false)
        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottom) {
                VideoThumbnail(video: summary, width: 220)
                resumeBar(progress)
            }
            .frame(width: 220)
        }
    }

    private func resumeBar(_ progress: VideoProgress) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.palette.hairline)
                Capsule().fill(theme.palette.accent)
                    .frame(width: geo.size.width * resumeFraction(progress))
            }
        }
        .frame(height: 3)
        .padding(.horizontal, 4)
        .padding(.bottom, 56) // sit just under the 16:9 poster, above the title block
    }

    private func resumeFraction(_ progress: VideoProgress) -> CGFloat {
        guard progress.durationSeconds > 0 else { return 0 }
        return min(max(CGFloat(progress.positionSeconds / progress.durationSeconds), 0), 1)
    }

    // --- Live & Upcoming ----------------------------------------------------

    private var liveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Live & Upcoming")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(webcasts) { video in
                        NavigationLink(value: Route.video(id: video.id, title: video.title)) {
                            VideoThumbnail(video: video, width: 220)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { favoriteButton(video) }
                    }
                }
            }
        }
    }

    // --- On-Demand grid -----------------------------------------------------

    private var onDemandSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("On Demand")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 16)],
                      alignment: .leading, spacing: 20) {
                ForEach(recent) { video in
                    NavigationLink(value: Route.video(id: video.id, title: video.title)) {
                        VideoThumbnail(video: video)
                            .onAppear { loadMoreIfNeeded(video) }
                    }
                    .buttonStyle(.plain)
                    .contextMenu { favoriteButton(video) }
                }
            }
            if loadingMore {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
        }
    }

    // --- favorite (right-click) --------------------------------------------

    @ViewBuilder
    private func favoriteButton(_ video: VideoSummary) -> some View {
        let fav = app.favorites.isVideoFavorited(video.id)
        Button(fav ? "Remove from Favorites" : "Add to Favorites",
               systemImage: fav ? "star.slash" : "star") {
            app.favorites.toggleVideo(FavVideo(
                id: video.id, videoSku: 0, title: video.title,
                artistName: video.artistName ?? "", dateText: video.dateText,
                isLive: video.isLive, imageURL: video.imageURL?.absoluteString,
                savedAt: Date()))
        }
    }

    // --- empty / error states ----------------------------------------------

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 34))
                .foregroundStyle(theme.palette.accent)
            Text("No videos right now")
                .font(theme.type.hero(22))
                .foregroundStyle(theme.palette.textPrimary)
            Text("Recently added concerts and webcasts will show up here.")
                .font(theme.type.body(13))
                .foregroundStyle(theme.palette.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView(
            "Couldn't load videos",
            systemImage: "exclamationmark.triangle",
            description: Text(message))
    }

    // --- loading ------------------------------------------------------------

    private func load() async {
        guard recent.isEmpty && webcasts.isEmpty && !loading else { return }
        loading = true
        defer { loading = false }
        do {
            async let recentFetch = app.client.recentVideos(offset: 0, limit: pageSize)
            async let webcastFetch = app.client.liveWebcasts()
            let (recentResult, webcastResult) = try await (recentFetch, webcastFetch)
            recent = recentResult
            webcasts = webcastResult
            offset = recentResult.count
            reachedEnd = recentResult.count < pageSize
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadMoreIfNeeded(_ video: VideoSummary) {
        guard !reachedEnd, !loadingMore, video.id == recent.last?.id else { return }
        Task { await loadMore() }
    }

    private func loadMore() async {
        guard !loadingMore, !reachedEnd else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let page = try await app.client.recentVideos(offset: offset, limit: pageSize)
            // De-dupe in case the recent feed shifts between pages.
            let known = Set(recent.map(\.id))
            let fresh = page.filter { !known.contains($0.id) }
            recent.append(contentsOf: fresh)
            offset += page.count
            if page.count < pageSize { reachedEnd = true }
        } catch {
            reachedEnd = true // stop paging on error; keep what we have
        }
    }
}
