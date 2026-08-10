import SwiftUI

/// The pill's 32pt leading slot: one skeleton, five faces. The layout around
/// it never changes, so truncation rules stay uniform, but each theme still
/// announces itself at a glance.
///
/// Nothing here observes `player.currentTime`. The reel's rotation and the VU's
/// sway are `TimelineView`-driven (wall clock, paused when playback pauses),
/// which keeps the 4Hz playback tick out of a view that is on screen at all
/// times.
struct PillLeadingSlot: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    private var size: CGFloat { PillLayout.leadingSlotSize }

    var body: some View {
        Group {
            switch theme.transport {
            case .standard:
                artChip
            case .jCard:
                // Shoebox's identity is the J-card spine; echo it as a rule
                // down the leading edge of the cover.
                artChip.overlay(alignment: .leading) {
                    Rectangle()
                        .fill(theme.palette.accent)
                        .frame(width: 3)
                }
                .clipShape(RoundedRectangle(cornerRadius: size * 0.14, style: .continuous))
            case .tapeLabel:
                PillReelSlot(size: size)
            case .faceplate:
                PillVUSlot(size: size)
            case .clickWheel:
                PillWheelSlot(size: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)   // the pill's button label already says what's playing
    }

    private var artChip: some View {
        ArtChip(image: app.player.nowPlayingImage,
                fallbackText: app.player.current?.artist
                    ?? app.player.current?.title ?? "?",
                size: size)
    }
}

/// Tape Room: a single reel, turning while the tape runs.
private struct PillReelSlot: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    let size: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0,
                                paused: !app.player.isPlaying)) { timeline in
            let angle = timeline.date.timeIntervalSinceReferenceDate * 90
            ZStack {
                Circle().fill(theme.palette.labelInk ?? theme.palette.base)
                Circle()
                    .strokeBorder(theme.palette.labelPaper ?? theme.palette.textPrimary,
                                  lineWidth: size * 0.10)
                    .padding(size * 0.16)
                // Three spokes: the whole point is that rotation must be VISIBLE.
                // Contrast against the hub, never hub-on-hub (see ef33039).
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(theme.palette.labelPaper ?? theme.palette.textPrimary)
                        .frame(width: size * 0.07, height: size * 0.42)
                        .rotationEffect(.degrees(Double(i) * 60))
                }
                Circle()
                    .fill(theme.palette.labelPaper ?? theme.palette.textPrimary)
                    .frame(width: size * 0.22)
            }
            .rotationEffect(.degrees(angle))
        }
    }
}

/// The Receiver: the faceplate's meter, shrunk into the slot.
private struct PillVUSlot: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    let size: CGFloat

    var body: some View {
        EqualizerBars(isPlaying: app.player.isPlaying)
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                    .fill(theme.palette.hairline)
            }
    }
}

/// Click Wheel: the wheel itself, reduced to its silhouette.
private struct PillWheelSlot: View {
    @Environment(\.theme) private var theme
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(theme.palette.textPrimary.opacity(0.9))
            Circle()
                .fill(theme.palette.base)
                .frame(width: size * 0.34)
        }
    }
}
