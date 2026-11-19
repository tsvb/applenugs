import SwiftUI

/// One video (catalog.container with a video product): an inline native player
/// surface at the top, then title / artist / date / venue / description, a
/// tappable chapter list, a quality menu, a resume affordance, and a save star.
/// Clones the AlbumDetailView load/overlay idiom; playback is owned by the
/// shared VideoPlayerService (one AVPlayer, audio/video arbiter).
///
/// AVKit's controls are untouched; we own only the Live sticker over them.
/// Play/Pause and the screen's other lone primaries (Watch on…, Buy on
/// nugs.net) are snow, everything else is a frost ring, benefit links are snow
/// with a dotted underline, the PPV panel is card stock, and errors are said
/// in snow and slush, never colored.
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
                    if (linkOut == nil && shouldAttemptPlay) || webcast?.isAudio == true {
                        playerSurface
                    }
                    if let linkOut {
                        Button { openURL(linkOut) } label: {
                            Label(watchButtonTitle, systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(.yetiPrimary)
                    }
                    if let detail {
                        header(detail)
                        if linkOut == nil {
                            actions(detail)
                            qualityMenu
                            resumeBanner(detail)
                        }
                        if let bn = webcast?.benefitNotes { benefitNotes(bn) }
                        notes(detail)
                        chapterList(detail)
                    }
                    if detail == nil, let bn = webcast?.benefitNotes { benefitNotes(bn) }
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
                VideoErrorMessage(title: "Couldn't load this video", reason: error)
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
                        VideoErrorMessage(title: "Can't play this video",
                                          reason: loadError,
                                          overPlayer: true)
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
                        .foregroundStyle(theme.palette.textSecondary)
                }
                .padding(24)
            }
            .overlay(alignment: .topLeading) { liveBadge }
    }

    private var isBuyOnly: Bool { webcast?.access == .ppv }

    /// The link-out button targets YouTube for free-video items (which carry an
    /// externalURL) and nugs.net otherwise.
    private var watchButtonTitle: String {
        webcast?.externalURL != nil ? "Watch on YouTube" : "Watch on nugs.net"
    }

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
    private var buyPanel: some View {
        PayPerViewPanel {
            if let url = nugsWatchURL(access: .ppv, skuId: webcast?.sku ?? 0) { openURL(url) }
        }
    }

    /// Benefit/donation framing that ships with some free webcasts. Rendered
    /// as attributed HTML so links (e.g. donation pages) stay tappable; falls
    /// back to plain text if the markdown parse fails.
    ///
    /// Each link run is snow with a dotted underline, never the accent. The runs keep their `.link`, so a tap still goes through
    /// `openURL`, where the root `.nowPlayingMetaLinks` interceptor hands any
    /// foreign URL back to the system: the donation page opens externally.
    @ViewBuilder private func benefitNotes(_ html: String) -> some View {
        let md = htmlToMarkdownish(html)
        BenefitNotesText(markdown: md)
    }

    /// Minimal HTML→text for short, first-party nugs blurbs: keep http/https/
    /// mailto anchors as markdown links (drop other schemes to plain text),
    /// turn <p>/<br> into breaks, strip remaining tags.
    private func htmlToMarkdownish(_ html: String) -> String {
        var s = html
        if let re = try? NSRegularExpression(
            pattern: "<a[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let ns = s as NSString
            var out = ""
            var last = 0
            for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let href = ns.substring(with: m.range(at: 1))
                let text = ns.substring(with: m.range(at: 2))
                let scheme = URL(string: href)?.scheme?.lowercased()
                if scheme == "http" || scheme == "https" || scheme == "mailto" {
                    out += "[\(text)](\(href))"
                } else {
                    out += text
                }
                last = m.range.location + m.range.length
            }
            out += ns.substring(from: last)
            s = out
        }
        s = s.replacingOccurrences(of: "</p>", with: "\n\n")
             .replacingOccurrences(of: "<br>", with: "\n")
             .replacingOccurrences(of: "<br/>", with: "\n")
             .replacingOccurrences(of: "<br />", with: "\n")
        if let re = try? NSRegularExpression(pattern: "<[^>]+>") {
            let range = NSRange(s.startIndex..., in: s)
            s = re.stringByReplacingMatches(in: s, range: range, withTemplate: "")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private var liveBadge: some View {
        if app.video.isLive { VideoLiveBadge() }
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
        let fav = app.favorites.isVideoFavorited(videoId)
        return VideoActionRow(
            isPlaying: app.video.isPlaying,
            isLive: detail.isLive,
            atLiveEdge: app.video.atLiveEdge,
            saved: fav,
            playPause: {
                // If this video is already loaded, toggle play/pause; only do a
                // cold start (re-resolve + buffer) when it isn't the current item.
                if app.video.current?.id == detail.id {
                    app.video.togglePlayPause()
                } else {
                    Task { await app.video.play(detail) }
                }
            },
            goLive: { app.video.seekToLiveEdge() },
            toggleSave: {
                app.favorites.toggleVideo(
                    FavVideo(id: videoId, videoSku: detail.videoSku,
                             title: detail.title, artistName: detail.artistName,
                             dateText: detail.dateText, isLive: detail.isLive,
                             imageURL: detail.imageURL?.absoluteString, savedAt: Date()))
            })
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
            .buttonStyle(.yetiSecondary)
            .controlSize(.small)
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
            // `.minisec`: heavy 15 in slush.
            Text("Chapters")
                .font(theme.type.section(15))
                .foregroundStyle(theme.palette.textSecondary)
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
            detail = try await app.client.videoDetail(containerId: videoId)
        } catch {
            // Buy-only and link-out screens don't strictly need metadata; only
            // the play path does, so only there do we surface the specific error.
            if isBuyOnly || !shouldAttemptPlay {
                detail = nil
            } else {
                self.error = error.localizedDescription
                return
            }
        }
        if isBuyOnly { return }
        // Free item with no in-app stream (free-video whose watch link is on
        // YouTube): send the user to that link; else nugs's page.
        guard shouldAttemptPlay else {
            linkOut = webcast?.externalURL
                ?? nugsWatchURL(access: webcast?.access ?? .free, skuId: webcast?.sku ?? 0)
            return
        }
        guard var toPlay = detail else {
            error = "Couldn't load this video."
            return
        }
        error = nil
        if let sku = webcast?.sku, sku > 0 { toPlay.videoSku = sku }
        if app.video.current?.id != toPlay.id {
            await app.video.play(toPlay)
        }
        // Free-audio the account can't resolve → link-out fallback.
        if app.video.loadError != nil, webcast?.isAudio == true {
            linkOut = webcast?.externalURL
                ?? nugsWatchURL(access: webcast?.access ?? .free, skuId: webcast?.sku ?? 0)
        }
    }
}

// MARK: - Parts (plain values in, so they render without a player)

/// One row in the chapter list: title, start time, hover highlight, seek on tap.
/// No play glyph (`.rows li.nolead`); the current chapter takes the
/// playing-row sale yellow; every title is heavy 15 (so being current never
/// changes a row's weight) and rows are ruled in frost.
struct ChapterRow: View {
    let chapter: VideoChapter
    let isCurrent: Bool
    let seek: () -> Void

    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: seek) {
            HStack(spacing: 8) {
                Text(chapter.title)
                    .font(theme.type.title(15))
                    .foregroundStyle(isCurrent ? theme.palette.playState : theme.palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(TransportBar.format(seconds: chapter.startSeconds))
                    .font(theme.type.numeric(13.5))
                    .foregroundStyle(theme.palette.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(hovering ? theme.palette.raised : .clear,
                    in: RoundedRectangle(cornerRadius: 5))
        .overlay(alignment: .top) {
            Rectangle().fill(theme.palette.hairline).frame(height: 1)
        }
        .onHover { hovering = $0 }
    }
}

/// The badge over the player when the stream is live: the `Live` label
/// sticker.
struct VideoLiveBadge: View {
    var body: some View {
        LabelSticker("Live")
            .padding(10)
    }
}

/// Play/Pause, Go Live (live streams only) and Save. Play/Pause is the snow
/// primary, Go Live a frost ring that says "Go Live" while it can act and the
/// copy's `liveEdgeDisabled` while it has nothing to do, and Save the iPhone's
/// 36pt ring pushed to the trailing edge (a labeled frost button on the Mac).
struct VideoActionRow: View {
    let isPlaying: Bool
    let isLive: Bool
    let atLiveEdge: Bool
    let saved: Bool
    let playPause: () -> Void
    let goLive: () -> Void
    let toggleSave: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Button(action: playPause) {
                Label(isPlaying ? "Pause" : "Play",
                      systemImage: isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.yetiPrimary)

            if isLive {
                Button(action: goLive) {
                    Label(atLiveEdge ? theme.copy.liveEdgeDisabled : "Go Live",
                          systemImage: "dot.radiowaves.left.and.right")
                }
                .disabled(atLiveEdge)
                .buttonStyle(.yetiSecondary)
            }

            Spacer(minLength: 0)

            saveButton
        }
    }

    private var saveButton: some View {
        Button(action: toggleSave) {
            Label(saved ? "Saved" : "Save", systemImage: saved ? "star.fill" : "star")
        }
        // Saving isn't time moving: never the accent.
        .yetiPageAction()
        .help(saved ? "Remove from Favorites" : "Save video to Favorites")
    }
}

/// PPV's locked panel and its buy button. The panel is card stock with a frost keyline and a slush lock, and "Buy on nugs.net"
/// is the full-width snow primary, its outbound arrow saying it leaves the app.
struct PayPerViewPanel: View {
    let buy: () -> Void

    @Environment(\.theme) private var theme

    /// `.ppv`: card stock, 14pt corners, a 1pt frost keyline.
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return VStack(alignment: .leading, spacing: 16) {
            shape
                .fill(theme.palette.cardStock)
                .overlay { shape.strokeBorder(theme.palette.hairline, lineWidth: 1) }
                .aspectRatio(16.0/9.0, contentMode: .fit)
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "lock")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(theme.palette.textSecondary)
                            .accessibilityHidden(true)
                        Text("Pay-per-view")
                            .font(theme.type.title(19))
                            .foregroundStyle(theme.palette.textPrimary)
                        Text("Not part of your subscription")
                            .font(theme.type.body(14))
                            .foregroundStyle(theme.palette.textSecondary)
                    }
                    .multilineTextAlignment(.center)
                    .accessibilityElement(children: .combine)
                }
            Button(action: buy) {
                Label("Buy on nugs.net", systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.yetiPrimary)
            .controlSize(.large)
        }
    }
}

/// A load or playback error, said, not colored: a slush mark, a heavy snow
/// title and the slush reason, with no triangle; over the player it sits on
/// the sheet's near-black.
struct VideoErrorMessage: View {
    let title: String
    let reason: String
    var overPlayer = false

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(theme.palette.textSecondary)
                .accessibilityHidden(true)
            Text(title)
                .font(theme.type.title(17))
                .foregroundStyle(theme.palette.textPrimary)
            Text(reason)
                .font(theme.type.body(13.5))
                .foregroundStyle(theme.palette.textSecondary)
                .lineLimit(3)
        }
        .multilineTextAlignment(.center)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { if overPlayer { theme.palette.videoErrorBackdrop } }
        .accessibilityElement(children: .combine)
    }
}

/// Benefit/donation notes as attributed markdown. Every link run carries snow
/// and a dotted underline explicitly (SwiftUI honors a run's own color over
/// the link tint), on slush body text. Attributes are set with the
/// `AttributeScopes` key subscript, not the dynamic-member form, which warns
/// under strict concurrency.
struct BenefitNotesText: View {
    let markdown: String

    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if let attributed = styled() {
                Text(attributed)
            } else {
                Text(markdown)
            }
        }
        .font(theme.type.body(14))
        .foregroundStyle(theme.palette.textSecondary)
        .tint(theme.palette.textPrimary)
        .textSelection(.enabled)
    }

    /// The parsed markdown (nil if the parse fails), with the link styling
    /// applied to every run that carries a link.
    private func styled() -> AttributedString? {
        guard var attributed = try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else { return nil }
        let linkRanges = attributed.runs
            .filter { $0[AttributeScopes.FoundationAttributes.LinkAttribute.self] != nil }
            .map(\.range)
        for range in linkRanges {
            attributed[range][AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] =
                theme.palette.textPrimary
            attributed[range][AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute.self] =
                Text.LineStyle(pattern: .dot, color: theme.palette.textPrimary)
        }
        return attributed
    }
}
