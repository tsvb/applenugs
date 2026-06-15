import SwiftUI

/// One video (catalog.container with a video product): an inline native player
/// surface at the top, then title / artist / date / venue / description, a
/// tappable chapter list, a quality menu, a resume affordance, and a save star.
/// Clones the AlbumDetailView load/overlay idiom; playback is owned by the
/// shared VideoPlayerService (one AVPlayer, audio/video arbiter).
struct VideoDetailView: View {
    let videoId: String
    var titleHint: String?

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    @State private var detail: VideoDetail?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                playerSurface
                if let detail {
                    header(detail)
                    actions(detail)
                    qualityMenu
                    resumeBanner(detail)
                    notes(detail)
                    chapterList(detail)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.palette.base)
        .navigationTitle(detail?.title ?? titleHint ?? "Video")
        .overlay {
            if detail == nil && error == nil {
                ProgressView()
            } else if let error {
                ContentUnavailableView(
                    "Couldn't load this video",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error))
            }
        }
        .task(id: videoId) { await load() }
        .onDisappear { app.video.stop() }
    }

    // --- player -----------------------------------------------------------------

    private var playerSurface: some View {
        VideoPlayerSurface(player: app.video.player)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topLeading) { liveBadge }
            .overlay {
                if let loadError = app.video.loadError {
                    ContentUnavailableView(
                        "Can't play this video",
                        systemImage: "play.slash",
                        description: Text(loadError))
                        .background(.black.opacity(0.6))
                }
            }
    }

    @ViewBuilder
    private var liveBadge: some View {
        if app.video.isLive {
            Text("LIVE")
                .font(theme.type.numeric(10).weight(.bold))
                .tracking(1.2)
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(theme.palette.accent, in: RoundedRectangle(cornerRadius: 4))
                .padding(10)
        }
    }

    // --- sections ---------------------------------------------------------------

    private func header(_ detail: VideoDetail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(detail.title).font(theme.type.hero(26))
            Text(detail.artistName).font(theme.type.title(18))
                .foregroundStyle(theme.palette.textSecondary)
            HStack(spacing: 10) {
                if let date = detail.dateText {
                    Text(date).font(theme.type.numeric(12))
                }
                if let venue = detail.venue {
                    Text(venue)
                }
            }
            .font(.callout)
            .foregroundStyle(theme.palette.textSecondary)
        }
    }

    private func actions(_ detail: VideoDetail) -> some View {
        HStack(spacing: 8) {
            Button {
                // If this video is already loaded, toggle play/pause; only do a
                // cold start (re-resolve + buffer) when it isn't the current item.
                if app.video.current?.id == detail.id {
                    app.video.togglePlayPause()
                } else {
                    Task { await app.video.play(detail) }
                }
            } label: {
                Label(app.video.isPlaying ? "Pause" : "Play",
                      systemImage: app.video.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)

            if detail.isLive {
                Button {
                    app.video.seekToLiveEdge()
                } label: {
                    Label("Go Live", systemImage: "dot.radiowaves.left.and.right")
                }
                .disabled(app.video.atLiveEdge)
            }

            saveButton(detail)
        }
    }

    private func saveButton(_ detail: VideoDetail) -> some View {
        let fav = app.favorites.isVideoFavorited(videoId)
        return Button {
            app.favorites.toggleVideo(
                FavVideo(id: videoId, videoSku: detail.videoSku,
                         title: detail.title, artistName: detail.artistName,
                         dateText: detail.dateText, isLive: detail.isLive,
                         imageURL: detail.imageURL?.absoluteString, savedAt: Date()))
        } label: {
            Label(fav ? "Saved" : "Save", systemImage: fav ? "star.fill" : "star")
        }
        .tint(fav ? theme.palette.accent : nil)
        .help(fav ? "Remove from Favorites" : "Save video to Favorites")
    }

    // --- quality ----------------------------------------------------------------

    @ViewBuilder
    private var qualityMenu: some View {
        if app.video.availableQualities.count > 1 {
            @Bindable var video = app.video
            Menu {
                Picker("Quality", selection: $video.selectedQuality) {
                    ForEach(app.video.availableQualities, id: \.self) { quality in
                        Text(Self.qualityLabel(quality)).tag(quality)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label(Self.qualityLabel(app.video.selectedQuality), systemImage: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private static func qualityLabel(_ quality: VideoQuality) -> String {
        switch quality {
        case .auto: return "Auto"
        case .capped(let height): return "\(height)p"
        }
    }

    // --- resume -----------------------------------------------------------------

    /// `load()`/`play()` already auto-resume to the saved position on a cold
    /// start, so this banner is purely a manual *re-jump* affordance: if the
    /// viewer has since scrubbed elsewhere, it sends them back to the saved
    /// point. It seeks the already-loaded item — never re-runs `play()`, which
    /// would re-resolve and re-buffer the stream.
    @ViewBuilder
    private func resumeBanner(_ detail: VideoDetail) -> some View {
        if !detail.isLive,
           app.video.current?.id == detail.id,
           let saved = app.videoProgress.progress(for: videoId),
           saved.positionSeconds > 5 {
            Button {
                app.video.seek(to: saved.positionSeconds)
            } label: {
                Label("Resume from \(TransportBar.format(seconds: saved.positionSeconds))",
                      systemImage: "arrow.clockwise")
                    .font(theme.type.body(12))
            }
            .buttonStyle(.bordered)
            .tint(theme.palette.accent)
        }
    }

    // --- description ------------------------------------------------------------

    @ViewBuilder
    private func notes(_ detail: VideoDetail) -> some View {
        let text = (detail.description ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            DisclosureGroup("About") {
                Text(text)
                    .font(theme.type.body(13))
                    .foregroundStyle(theme.palette.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
    }

    // --- chapters ---------------------------------------------------------------

    @ViewBuilder
    private func chapterList(_ detail: VideoDetail) -> some View {
        if !detail.chapters.isEmpty {
            let condensed = theme.caps.contains(.condensedHeaders)
            Text(condensed ? "CHAPTERS" : "Chapters")
                .font(theme.type.section(15))
                .tracking(condensed ? 1.4 : 0)
                .foregroundStyle(theme.palette.textPrimary)
                .padding(.top, 6)
            VStack(spacing: 0) {
                ForEach(detail.chapters) { chapter in
                    ChapterRow(
                        chapter: chapter,
                        isCurrent: isCurrentChapter(chapter, in: detail),
                        seek: { app.video.seek(to: chapter.startSeconds) })
                }
            }
        }
    }

    /// A chapter is "current" when playback is at or past its start and before
    /// the next chapter's start.
    private func isCurrentChapter(_ chapter: VideoChapter, in detail: VideoDetail) -> Bool {
        guard app.video.current?.id == detail.id else { return false }
        let now = app.video.currentTime
        guard now >= chapter.startSeconds else { return false }
        let next = detail.chapters
            .map(\.startSeconds)
            .filter { $0 > chapter.startSeconds }
            .min()
        return next.map { now < $0 } ?? true
    }

    // --- load -------------------------------------------------------------------

    private func load() async {
        do {
            let loaded = try await app.client.videoDetail(containerId: videoId)
            detail = loaded
            error = nil
            await app.video.play(loaded)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// One row in the chapter list: title, start time, hover highlight, seek on tap.
private struct ChapterRow: View {
    let chapter: VideoChapter
    let isCurrent: Bool
    let seek: () -> Void

    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: seek) {
            HStack(spacing: 8) {
                Image(systemName: isCurrent ? "play.fill" : "play")
                    .font(.system(size: 10))
                    .foregroundStyle(isCurrent ? theme.palette.accent : theme.palette.textSecondary)
                    .frame(width: 16, alignment: .center)
                Text(chapter.title)
                    .font(theme.type.body(13))
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .foregroundStyle(isCurrent ? theme.palette.accent : theme.palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(TransportBar.format(seconds: chapter.startSeconds))
                    .font(theme.type.numeric(12))
                    .foregroundStyle(theme.palette.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(hovering ? theme.palette.raised : .clear,
                    in: RoundedRectangle(cornerRadius: 5))
        .onHover { hovering = $0 }
    }
}
