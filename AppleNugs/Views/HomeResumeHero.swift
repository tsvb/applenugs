import SwiftUI

// Home's "what's playing" heroes under Yeti, plus the progress rule every Home
// hero shares. Shared code: `HomeView` mounts the iPhone hero on iOS and the
// flat resume card on macOS, but both views take plain values (no
// `PlayerService`), so either compiles anywhere and an offscreen render can
// build them as-is.

extension EnvironmentValues {
    /// Opens the full-screen now-playing cover. Set once by `IOSRootView` on
    /// its `TabView`, wired to the same `nowPlayingPresented` state the pill's
    /// tap sets — so the Home hero reuses the one presentation instead of
    /// adding a second. Nil (a no-op) everywhere else, macOS included.
    @Entry var openNowPlaying: OpenNowPlayingAction? = nil
}

/// The `openNowPlaying` environment action, `OpenURLAction`-style: call it.
///
/// Equatable and always equal, deliberately: there is exactly one owner of the
/// cover and the action always does the same thing (presents it), so a fresh
/// closure on each `IOSRootView` update is not a new value — without this,
/// every update would invalidate every reader of the key.
struct OpenNowPlayingAction: Equatable, Sendable {
    private let open: @MainActor @Sendable () -> Void

    init(_ open: @escaping @MainActor @Sendable () -> Void) {
        self.open = open
    }

    @MainActor func callAsFunction() { open() }

    static func == (_: Self, _: Self) -> Bool { true }
}

// MARK: - Progress rule

/// The hero's thin progress rule: a hairline track with the elapsed part in
/// the theme's accent (foil under Yeti — set explicitly, since Yeti's root
/// tint is snow).
///
/// A LEAF view: the ~4Hz playback-time dependency registers here, not on the
/// whole editorial landing page or the hero around it (CLAUDE.md, the
/// leaf-view rule). Always 3pt tall, whatever the time reads.
struct ResumeProgressRule: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    /// 320 on the Mac card today, 360 on Yeti's (`.resume .prog`), unbounded
    /// in the iPhone hero's name panel.
    var maxWidth: CGFloat = 320

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.palette.hairline)
                Capsule().fill(theme.palette.accent)
                    .frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 3)
        .frame(maxWidth: maxWidth, alignment: .leading)
        .accessibilityHidden(true)
    }

    private var fraction: CGFloat {
        let player = app.player
        guard player.duration > 0 else { return 0 }
        return min(max(CGFloat(player.currentTime / player.duration), 0), 1)
    }
}

// MARK: - iPhone hero

/// The iPhone Home hero under `.blisterPack` (Tim's ruling 1: the Mac's resume
/// card, ported, on the peg): the cover in the bubble on card stock with the
/// price sticker on its corner; the title, meta and a foil progress rule
/// printed on the card; and a 54pt play sticker beside them. Translated from
/// `yeti-decisions.html` §1 option A (`.hero-card`). No foil sweep — that
/// lives only on the now-playing card and the Mac miniplayer.
///
/// Two targets: the sticker toggles playback; anywhere else on the card opens
/// the full-screen player. The sticker is a real `Button` nested inside the
/// card's tap gesture — the pill's verified pattern: the nested button wins
/// hit-testing, so a sticker tap never also opens the player. The meta line's
/// artist and show are real links too (`tappableText` on, as on the pill and
/// the Mac hero, by Tim's call).
struct YetiHomeHero: View {
    @Environment(\.theme) private var theme

    let track: QueueTrack
    let image: PlatformImage?
    let isPlaying: Bool
    let isBuffering: Bool
    /// The corner sticker's label; pass `PriceStickerLabel(player:)`.
    let price: PriceStickerLabel?
    let onToggle: () -> Void
    let onOpen: () -> Void

    /// `.hero-card .bubble { width: 186px }`.
    static let bubbleSide: CGFloat = 186

    var body: some View {
        BlisterPack(style: .hero,
                    price: price,
                    // The sheet's full 62pt sticker; the auto size would pick
                    // 44 for a bubble this size.
                    priceSize: .s62,
                    maxBubbleSide: Self.bubbleSide) {
            PackArt(image: image, monogram: track.artist ?? track.title ?? "?")
        } below: {
            // `.hero-card .name`: text column + sticker, bottoms aligned.
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(track.title ?? "Unknown track")
                        .font(theme.type.hero(28))
                        .foregroundStyle(theme.palette.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    NowPlayingMetaText(track: track)
                        .font(theme.type.body(15))
                        .foregroundStyle(theme.palette.textSecondary)
                        .lineLimit(1)
                        .padding(.top, 6)
                    ResumeProgressRule(maxWidth: .infinity)
                        .padding(.top, 10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HapticButton(.transportToggle, action: onToggle) {
                    PlaySticker(isPlaying: isPlaying, isBuffering: isBuffering, size: .s54)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "Pause" : "Play")
                .accessibilityValue(isBuffering ? "Buffering" : "")
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: BlisterCard.cornerRadius, style: .continuous))
        .onTapGesture(perform: onOpen)
        // The pill's pattern: a container, so the play sticker and the meta
        // links stay their own elements, that itself says what's playing and
        // carries the open action. The action, label and hint all come AFTER
        // `.accessibilityElement(children: .contain)` — applied before it they
        // land on the pre-container element and are dropped.
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open now playing", onOpen)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint("Opens full-screen now playing")
    }

    private var accessibilityLabelText: String {
        let title = track.title ?? "Unknown track"
        guard let artist = track.artist else { return "Now playing: \(title)" }
        return "Now playing: \(title), \(artist)"
    }
}

// MARK: - Mac resume card

/// The macOS Home resume card under `.blisterPack` (Tim's ruling 4): card
/// stock with a FLAT 96pt cover — no bubble (that stays special to the
/// miniplayer and the Now Playing window, so an open dashboard never shows
/// two bubbles of one cover) and no hang slot (`.resume::before { display:
/// none }`) — no "CONTINUE LISTENING" eyebrow, a foil progress rule and a
/// 54pt play sticker. From `yeti-surfaces.html` "Mac Home" (`.card.resume`).
///
/// The whole card toggles playback, exactly as the other themes' card does.
struct YetiResumeCard: View {
    @Environment(\.theme) private var theme

    let track: QueueTrack
    let image: PlatformImage?
    let isPlaying: Bool
    let isBuffering: Bool
    let onToggle: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: BlisterCard.cornerRadius, style: .continuous)
        Button(action: onToggle) {
            HStack(spacing: 20) {
                ArtChip(image: image,
                        fallbackText: track.artist ?? track.title ?? "?",
                        size: 96)

                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title ?? "Unknown track")
                        .font(theme.type.hero(26))
                        .foregroundStyle(theme.palette.textPrimary)
                        .lineLimit(1)
                    NowPlayingMetaText(track: track)
                        .font(theme.type.body(14))
                        .foregroundStyle(theme.palette.textSecondary)
                        .lineLimit(1)
                    ResumeProgressRule(maxWidth: 360)
                        .padding(.top, 8)
                }
                Spacer(minLength: 8)
                PlaySticker(isPlaying: isPlaying, isBuffering: isBuffering, size: .s54)
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 22)
            .background {
                shape
                    .fill(theme.palette.labelPaper ?? theme.palette.raised)
                    .overlay { shape.strokeBorder(theme.palette.hairline, lineWidth: 1) }
                    .stickerLift(BlisterCard.lift, in: shape)
            }
            .contentShape(shape)
            // The whole card is the button, so the card takes the outline.
            .foilFocusOutline(shape)
        }
        .buttonStyle(.plain)
        .macFocusEffectDisabled()
    }
}
