import SwiftUI

/// One video (catalog.container with a video product): an inline native player
/// surface at the top, then title / artist / date / venue / description, a
/// tappable chapter list, a quality menu, a resume affordance, and a save star.
/// Clones the AlbumDetailView load/overlay idiom; playback is owned by the
/// shared VideoPlayerService (one AVPlayer, audio/video arbiter).
struct VideoDetailView: View {
    let videoId: String
    var titleHint: String?
    var webcast: WebcastContext? = nil

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    @State private var detail: VideoDetail?
    @State private var error: String?
    @State private var linkOut: URL?   // set when a free item has no in-app stream

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if isBuyOnly {
                    buyPanel
                    if let detail { header(detail) }
                    if let bn = webcast?.benefitNotes { benefitNotes(bn) }
                } else {
                    playerSurface
                    if let linkOut {   // free item with no in-app stream
                        Button { openURL(linkOut) } label: {
                            Label("Watch on nugs.net", systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if let detail {
                        header(detail)
                        if linkOut == nil {   // hide transport when we're linking out
                            actions(detail)
                            qualityMenu
                            resumeBanner(detail)
                        }
                        if let bn = webcast?.benefitNotes { benefitNotes(bn) }
                        notes(detail)
                        chapterList(detail)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.palette.base)
        .navigationTitle(detail?.title ?? titleHint ?? "Video")
        .compactNavigationTitle()
        .overlay {
            if shouldAttemptPlay && linkOut == nil && detail == nil && error == nil {
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

    @ViewBuilder
    private var playerSurface: some View {
        if webcast?.isAudio == true {
            audioSurface
        } else {
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
    }

    /// Audio webcast: cover art in place of video; the AVPlayer still drives the
    /// HLS audio and the transport row below works unchanged.
    private var audioSurface: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(theme.palette.raised)
            .aspectRatio(16.0/9.0, contentMode: .fit)
            .overlay {
                AsyncImage(url: detail?.imageURL) { img in
                    img.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    Image(systemName: "waveform")
                        .font(.system(size: 40))
                        .foregroundStyle(theme.palette.accent)
                }
                .padding(24)
            }
            .overlay(alignment: .topLeading) { liveBadge }
    }

    private var isBuyOnly: Bool { webcast?.access == .ppv }

    /// Whether this screen resolves + plays in-app. VOD and exclusive webcasts
    /// play; free-AUDIO plays (resolved from the feed sku); PPV and
    /// free-VIDEO-without-a-link do not (buy / link-out instead).
    private var shouldAttemptPlay: Bool {
        guard let w = webcast else { return true }   // VOD
        switch w.access {
        case .exclusive: return true
        case .free:      return w.isAudio
        case .ppv:       return false
        }
    }

    @Environment(\.openURL) private var openURL

    /// PPV: honest buy-out. No player, no stream-resolve. Opens nugs's own
    /// watch/buy page (which gates on login, then offers purchase).
    @ViewBuilder private var buyPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.palette.raised)
                .aspectRatio(16.0/9.0, contentMode: .fit)
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "lock.circle")
                            .font(.system(size: 34))
                            .foregroundStyle(theme.palette.accent)
                        Text("Pay-per-view").font(theme.type.title(15))
                            .foregroundStyle(theme.palette.textPrimary)
                        Text("Not included in your subscription")
                            .font(theme.type.body(12))
                            .foregroundStyle(theme.palette.textSecondary)
                    }
                }
            Button {
                if let url = nugsWatchURL(access: .ppv, skuId: webcast?.sku ?? 0) { openURL(url) }
            } label: {
                Label("Buy on nugs.net", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// Benefit/donation framing that ships with some free webcasts. Rendered
    /// as attributed HTML so links (e.g. donation pages) stay tappable.
    @ViewBuilder private func benefitNotes(_ html: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: htmlToMarkdownish(html),
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributed)
                .font(theme.type.body(13))
                .foregroundStyle(theme.palette.textSecondary)
                .tint(theme.palette.accent)
                .textSelection(.enabled)
        }
    }

    /// Minimal HTML→text: strip tags, keep anchor hrefs as markdown links.
    /// The notes are short nugs-authored blurbs, not arbitrary documents.
    private func htmlToMarkdownish(_ html: String) -> String {
        var s = html
        // <a href="URL">text</a> -> [text](URL)
        if let re = try? NSRegularExpression(
            pattern: "<a[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>", options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let range = NSRange(s.startIndex..., in: s)
            s = re.stringByReplacingMatches(in: s, range: range, withTemplate: "[$2]($1)")
        }
        s = s.replacingOccurrences(of: "</p>", with: "\n\n")
             .replacingOccurrences(of: "<br>", with: "\n")
             .replacingOccurrences(of: "<br/>", with: "\n")
             .replacingOccurrences(of: "<br />", with: "\n")
        // strip any remaining tags
        if let re = try? NSRegularExpression(pattern: "<[^>]+>") {
            let range = NSRange(s.startIndex..., in: s)
            s = re.stringByReplacingMatches(in: s, range: range, withTemplate: "")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
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
        // Metadata loads for every state (unauthenticated; drives header/venue).
        detail = try? await app.client.videoDetail(containerId: videoId)

        // PPV: buy-only. Never resolve or play.
        if isBuyOnly { return }

        // Free item with no in-app stream (e.g. free-video whose watch link is
        // on YouTube): send the user to nugs's page, not a dead player.
        guard shouldAttemptPlay else {
            linkOut = nugsWatchURL(access: webcast?.access ?? .free, skuId: webcast?.sku ?? 0)
            return
        }

        guard var toPlay = detail else {
            error = "Couldn't load this video."
            return
        }
        error = nil
        // Webcasts carry the correct sku from the feed; the legacy detail can't
        // derive an audio SKU (returns 0). Prefer the feed sku.
        if let sku = webcast?.sku, sku > 0 { toPlay.videoSku = sku }
        if app.video.current?.id != toPlay.id {
            await app.video.play(toPlay)
        }
        // Free-audio the account can't resolve → link-out fallback.
        if app.video.loadError != nil, webcast?.isAudio == true {
            linkOut = nugsWatchURL(access: webcast?.access ?? .free, skuId: webcast?.sku ?? 0)
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
