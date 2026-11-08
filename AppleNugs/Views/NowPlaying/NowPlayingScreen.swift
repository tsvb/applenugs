import SwiftUI

/// Scene id for the macOS Now Playing window (see AppleNugsApp). Shared so the
/// window scene, the Window-menu command, and the transport expand buttons all
/// reference one constant.
enum NowPlayingWindow {
    static let id = "now-playing"
}

/// Full-screen now-playing, presented from a tap on the compact transport bar.
/// Themes with the faceplate transport (The Receiver) get the TouchFaceplate;
/// everything else gets the standard layout below, tinted by theme tokens.
struct NowPlayingScreen: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            switch theme.transport {
            case .faceplate:
                TouchFaceplate()
            case .clickWheel:
                ClickWheelScreen()
            case .standard, .tapeLabel, .jCard:
                StandardNowPlayingScreen()
            }
        }
    }
}

// MARK: - Standard layout

struct StandardNowPlayingScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.artColor) private var artColor
    @Environment(\.dismiss) private var dismiss
    @Environment(UIState.self) private var ui
    @Environment(\.nowPlayingQueueBeside) private var queueBeside

    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var dashboardShown = false
    @State private var confirmClear = false

    private var player: PlayerService { app.player }

    /// Yeti's card layout (`.blisterPack`): the pack replaces the artwork and
    /// title block, and the stack trades its 22pt spacing for the mockup's
    /// tighter per-row margins (`NowPlayingCardMetrics`) so the whole player
    /// fits the Duo's 433×635pt column. Values, not containers: every other
    /// theme lays out exactly as before.
    private var card: Bool { theme.caps.contains(.blisterPack) }

    var body: some View {
        VStack(spacing: card ? 0 : 22) {
            header

            Spacer(minLength: 0)

            if card {
                NowPlayingPackCard(
                    track: player.current,
                    image: player.nowPlayingImage,
                    isPlaying: player.isPlaying,
                    price: theme.caps.contains(.stickers) ? PriceStickerLabel(player: player) : nil)
                    .padding(.horizontal, NowPlayingCardMetrics.cardInset)
                    .padding(.top, NowPlayingCardMetrics.cardTop)
            } else {
                artwork
                    .padding(.horizontal, 36)
            }

            // Tape Room: the label card's "tape counter" under-rule rides
            // directly beneath the reel (in addition to the scrubber below).
            if theme.transport == .tapeLabel {
                tapeCounter
                    .padding(.horizontal, 72)
            }

            if !card {
                titleBlock
            }

            Spacer(minLength: 0)

            seekBlock
                .padding(.horizontal, 24)
                .padding(.top, card ? NowPlayingCardMetrics.scrubTop : 0)

            // Rigid (five fixed glyphs, a 68pt play button): in a column
            // narrower than the row plus the seek block's 24pt insets — the
            // ~300pt player column on iPhone Duo's upright inner display — it
            // shrinks as a unit. Its natural width measured ~308pt on the Duo
            // simulator, so the scale is 1 on every iPhone (390 − 48 ≥ 308)
            // and the Mac window at its default 400pt; ~0.82 at a 300pt column.
            transportRow
                .nowPlayingFitWidth(margin: 24)
                .padding(.top, card ? NowPlayingCardMetrics.transportTop : 0)

            volumeRow
                .padding(.horizontal, 32)
                .padding(.top, card ? NowPlayingCardMetrics.volumeTop : 0)

            bottomRow
                .padding(.horizontal, 28)
                .padding(.top, card ? NowPlayingCardMetrics.bottomTop : 0)
        }
        .padding(.vertical, card ? NowPlayingCardMetrics.verticalPadding : 18)
        .nowPlayingReadableWidth()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            theme.palette.base
                .overlay { ArtWashBackground(style: theme.washStyle, color: artColor ?? .clear) }
                .overlay {
                    if theme.textureOpacity > 0 {
                        PaperGrain().opacity(theme.textureOpacity).allowsHitTesting(false)
                    }
                }
                .ignoresSafeArea()
        }
        .dismissesOnNavigation($dashboardShown, ui: ui)
        .sheet(isPresented: $dashboardShown) {
            DashboardPanel()
                #if os(iOS)
                .presentationDetents([.medium, .large])
                #endif
                .presentationBackground(theme.palette.base)
        }
        .clearQueueConfirmation(isPresented: $confirmClear) { app.player.clear() }
    }

    /// The five themes' title + meta under the artwork. (Yeti prints both on
    /// its card instead — `NowPlayingPackCard`.)
    private var titleBlock: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                // Under `.stickers` the nameplate stands alone (spec's
                // EqualizerBars table); the card branch never reaches here,
                // but the rule holds on its own.
                if theme.caps.contains(.equalizerRows), !theme.caps.contains(.stickers) {
                    EqualizerBars(isPlaying: player.isPlaying)
                }
                Text(player.current?.title ?? "Nothing playing")
                    .font(theme.type.hero(22))
                    .foregroundStyle(theme.palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            if let track = player.current {
                // Shoebox liner-note treatment: typed-out tracked caps,
                // as on its J-card spine.
                if theme.transport == .jCard {
                    NowPlayingMetaText(track: track, casing: .upper)
                        .font(theme.type.numeric(11))
                        .tracking(0.9)
                        .foregroundStyle(theme.palette.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                } else {
                    NowPlayingMetaText(track: track)
                        .font(theme.type.title(14))
                        .foregroundStyle(theme.palette.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.palette.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close now playing")

            Spacer()

            // Queue position while loaded; the theme's flavor copy only for
            // the empty state (its keyboard hints don't apply on iOS anyway).
            // `.plainVoice` says it in sentence case, untracked ("Track 3 of
            // 24", ruling 3).
            if theme.caps.contains(.plainVoice) {
                Text(player.current != nil
                     ? "Track \(player.index + 1) of \(player.queue.count)"
                     : theme.copy.nowPlaying)
                    .font(theme.type.body(14))
                    .foregroundStyle(theme.palette.textSecondary)
                    .lineLimit(1)
            } else {
                Text(player.current != nil
                     ? "TRACK \(player.index + 1) OF \(player.queue.count)"
                     : theme.copy.nowPlaying.uppercased())
                    .font(theme.type.numeric(11))
                    .tracking(1.6)
                    .foregroundStyle(theme.palette.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            // The card layout moves the star to the bottom row (AirPlay / star
            // / queue, as drawn); the ⋯ queue menu takes its slot here so the
            // bottom row holds exactly three.
            // The ZStack keeps the 44pt slot when `moreMenu` is empty (no
            // queue) — a frame around an empty `if` reserves nothing, and the
            // centered header line would drift. The plain menu style drops the
            // macOS pull-down bezel and chevron, which spill past the slot.
            if card {
                ZStack {
                    Color.clear
                    moreMenu
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .menuIndicator(.hidden)
                }
                .frame(width: 44, height: 44)
            } else {
                star
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 12)
    }

    private var artwork: some View {
        ZStack {
            if let image = player.nowPlayingImage {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // The monogram scales with the box it is given, capped at its
                // old fixed 280pt — the same flexibility the real-art Image
                // above already has. A rigid 280×280 tile can't shrink, which
                // overflowed the stack: on iPhone Duo's ~669pt-tall landscape
                // inner display it pushed the header and bottom row off
                // screen, and even on a portrait iPhone the stack overflowed
                // its 18pt vertical padding by ~15pt at each end (truncating
                // the meta line to one row). The ideal size keeps 280 for
                // unconstrained (nil) proposals.
                GeometryReader { geo in
                    MonogramTile(
                        text: player.current?.artist ?? player.current?.title ?? "?",
                        size: min(geo.size.width, geo.size.height))
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                .frame(idealWidth: 280, maxWidth: 280, idealHeight: 280, maxHeight: 280)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(theme.palette.textPrimary.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: (artColor ?? theme.palette.accent).opacity(0.35), radius: 28, y: 10)
    }

    private var seekBlock: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    // A stream that reports no duration would otherwise pin the
                    // thumb hard right — `sliderMax` falls back to 1 and the
                    // position clamps to it — which reads as "finished" while
                    // the track is only seconds in. Sit at 0 instead; the
                    // slider is already disabled in that state.
                    get: { scrubbing ? scrubValue
                                     : (player.duration > 0 ? min(player.currentTime, sliderMax) : 0) },
                    set: { scrubValue = $0 }),
                in: 0...sliderMax
            ) { editing in
                if editing { scrubValue = player.currentTime } else { player.seek(to: scrubValue) }
                scrubbing = editing
            }
            .tint(theme.effectiveAccent(art: artColor))
            .disabled(player.duration <= 0)
            .accessibilityLabel("Playback position")
            .accessibilityValue(TransportBar.format(seconds: scrubbing ? scrubValue : player.currentTime))

            HStack {
                Text(TransportBar.format(seconds: scrubbing ? scrubValue : player.currentTime))
                Spacer()
                Text(remainingText)
            }
            .font(theme.type.numeric(11))
            .foregroundStyle(theme.palette.textSecondary)
        }
    }

    private var tapeCounter: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.palette.hairline)
                Capsule().fill(theme.palette.accent)
                    .frame(width: geo.size.width * counterProgress)
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }

    private var counterProgress: CGFloat {
        guard player.duration > 0 else { return 0 }
        return min(max(CGFloat(player.currentTime / player.duration), 0), 1)
    }

    private var sliderMax: Double { max(player.duration, 1) }

    private var remainingText: String {
        guard player.duration > 0 else { return "--:--" }
        let position = scrubbing ? scrubValue : player.currentTime
        return "-" + TransportBar.format(seconds: max(player.duration - position, 0))
    }

    private var transportRow: some View {
        HStack(spacing: 26) {
            HapticButton(.transportStep) { player.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: 26))
            }
            .disabled(!player.hasPrevious)
            .accessibilityLabel("Previous track")

            HapticButton(.transportStep) { player.seek(by: -15) } label: {
                Image(systemName: "gobackward.15").font(.system(size: 20))
            }
            .disabled(player.current == nil)
            .accessibilityLabel("Back 15 seconds")

            HapticButton(.transportToggle) { player.togglePlayPause() } label: {
                if theme.caps.contains(.stickers) {
                    // The sticker keeps the spinner inside its own disc, so the
                    // control never changes size while buffering.
                    PlaySticker(isPlaying: player.isPlaying,
                                isBuffering: player.isBuffering,
                                size: .s64)
                } else if player.isBuffering {
                    ProgressView()
                        .frame(width: 68, height: 68)
                } else {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 68))
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .disabled(player.current == nil)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            HapticButton(.transportStep) { player.seek(by: 30) } label: {
                Image(systemName: "goforward.30").font(.system(size: 20))
            }
            .disabled(player.current == nil)
            .accessibilityLabel("Forward 30 seconds")

            HapticButton(.transportStep) { player.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 26))
            }
            .disabled(!player.hasNext)
            .accessibilityLabel("Next track")
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.palette.textPrimary)
    }

    private var volumeRow: some View {
        @Bindable var player = app.player
        return HStack(spacing: 12) {
            Image(systemName: "speaker.fill").font(.system(size: 12))
            Slider(value: $player.volume, in: 0...1)
                // Volume isn't time, so under `.plainVoice` it isn't foil.
                .tint(theme.caps.contains(.plainVoice)
                      ? theme.palette.textSecondary
                      : theme.effectiveAccent(art: artColor))
                .accessibilityLabel("Volume")
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 12))
        }
        .foregroundStyle(theme.palette.textSecondary)
    }

    @ViewBuilder
    private var bottomRow: some View {
        if card {
            cardBottomRow
        } else {
            standardBottomRow
        }
    }

    /// The card layout's bottom row: AirPlay / star / queue, spread like the
    /// sheet's `.np-bottom`. No format badge — the price sticker on the
    /// bubble's corner carries it.
    private var cardBottomRow: some View {
        HStack {
            RoutePicker(tint: theme.caps.contains(.plainVoice)
                        ? theme.palette.textSecondary
                        : theme.effectiveAccent(art: artColor))
                .frame(width: 44, height: 44)

            Spacer()

            star
                .frame(width: 44, height: 44)

            Spacer()

            queueButton
        }
    }

    /// The queue slot: a button, or — with the queue already beside the
    /// player on iPhone Duo's inner display — a same-size placeholder so the
    /// row doesn't shift.
    @ViewBuilder
    private var queueButton: some View {
        if queueBeside {
            Color.clear
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        } else {
            Button {
                dashboardShown = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 17))
                    .foregroundStyle(theme.palette.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Queue and stream details")
        }
    }

    /// "More queue actions" (Clear Queue, confirmed). Present while there is a
    /// queue; nothing otherwise (the card header's ZStack keeps the 44pt slot).
    @ViewBuilder
    private var moreMenu: some View {
        if !player.queue.isEmpty {
            Menu {
                Button(role: .destructive) {
                    confirmClear = true
                } label: {
                    Label("Clear Queue", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 17))
                    .foregroundStyle(theme.palette.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("More queue actions")
        }
    }

    private var standardBottomRow: some View {
        HStack {
            if let pick = player.nowPick {
                Text(pick.format.badge)
                    .font(theme.type.numeric(10).weight(.semibold))
                    .foregroundStyle(theme.palette.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.palette.hairline, in: RoundedRectangle(cornerRadius: 4))
            }

            Spacer()

            RoutePicker(tint: theme.effectiveAccent(art: artColor))
                .frame(width: 44, height: 44)

            // The queue already sits beside the player on iPhone Duo's inner
            // display; keep its 44pt slot so the row doesn't shift.
            queueButton

            moreMenu
        }
    }

    private var star: some View {
        let saved = NowPlayingFavorite.isSaved(player.current, favorites: app.favorites)
        return Button {
            NowPlayingFavorite.toggle(player.current, favorites: app.favorites)
        } label: {
            Image(systemName: saved ? "star.fill" : "star")
                .font(.system(size: 17))
                // A saved show isn't time moving: under `.plainVoice` the
                // filled star is snow, not an accent fill.
                .foregroundStyle(saved
                                 ? (theme.caps.contains(.plainVoice) ? theme.palette.textPrimary
                                                                     : theme.palette.accent)
                                 : theme.palette.textSecondary)
        }
        .buttonStyle(.plain)
        .disabled(player.current?.showId == nil)
        .accessibilityLabel("Save show to Favorites")
        .accessibilityAddTraits(saved ? .isSelected : [])
    }
}
