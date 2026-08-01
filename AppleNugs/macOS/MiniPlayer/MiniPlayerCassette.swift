import SwiftUI

/// Tape Room's miniplayer: a Compact Cassette at true 25:16 proportions
/// (a real shell is 100 × 64 mm).
///
/// Layout note — the ratio is a *target*, not a cage. Ornament (screws, corner
/// marks) is absolutely positioned in an overlay, while the label, window and
/// ridged band form a real `VStack`: the label takes its intrinsic height, the
/// window absorbs the slack, and if text ever needs more room than the ratio
/// allows, the stack reports a taller size and the ratio yields. Text is never
/// clipped to preserve a shape.
struct MiniPlayerCassette: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    private var player: PlayerService { app.player }

    /// Cassette aspect: 100 mm × 64 mm.
    private let shellRatio: CGFloat = 25.0 / 16.0

    private var paper: Color { theme.palette.labelPaper ?? theme.palette.textPrimary }
    private var ink: Color { theme.palette.labelInk ?? theme.palette.base }

    var body: some View {
        VStack(spacing: 8) {
            label.layoutPriority(2)
            windowBlock
            ridgedBand.layoutPriority(2)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .aspectRatio(shellRatio, contentMode: .fit)
        .background(shell)
        .overlay(ornament)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    // --- shell ---------------------------------------------------------------

    private var shell: some View {
        LinearGradient(
            colors: [theme.palette.hairline.opacity(0.9),
                     theme.palette.raised,
                     theme.palette.base],
            startPoint: .topLeading, endPoint: .bottomTrailing)
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.10)).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(.black.opacity(0.5)).frame(height: 1)
        }
    }

    /// Screws and the two bottom-corner marks. Decorative only.
    private var ornament: some View {
        ZStack {
            VStack {
                HStack { screw; Spacer(); screw }
                Spacer()
                HStack { screw; Spacer(); screw }
            }
            .padding(6)

            VStack {
                Spacer()
                HStack {
                    corner { EmptyView() }
                    Spacer()
                    corner {
                        Image(systemName: "play.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(theme.palette.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var screw: some View {
        Circle()
            .fill(RadialGradient(colors: [theme.palette.textIdle.opacity(0.55),
                                          theme.palette.base],
                                 center: .init(x: 0.35, y: 0.32),
                                 startRadius: 0, endRadius: 6))
            .overlay { Circle().strokeBorder(.black.opacity(0.5), lineWidth: 1) }
            .frame(width: 9, height: 9)
    }

    private func corner<Mark: View>(@ViewBuilder mark: () -> Mark) -> some View {
        ZStack {
            Circle()
                .fill(theme.palette.base)
                .overlay { Circle().strokeBorder(.black.opacity(0.5), lineWidth: 1) }
            mark()
        }
        .frame(width: 12, height: 12)
    }

    // --- the write-on label ---------------------------------------------------

    private var label: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(LinearGradient(colors: [theme.palette.accent.opacity(0.75),
                                              theme.palette.accent.opacity(0.45)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(height: 4)

            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .top, spacing: 6) {
                    Text(player.current?.title ?? "Unknown track")
                        .font(theme.type.title(13))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    losslessTick
                }
                Text(player.current?.artist ?? "—")
                    .font(theme.type.body(10))
                    .foregroundStyle(ink.opacity(0.78))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let show = player.current?.show {
                    Text(show.uppercased())
                        .font(theme.type.numeric(9))
                        .tracking(0.5)
                        .foregroundStyle(ink.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
        }
        .background(paper)
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(ink.opacity(0.35), lineWidth: 1)
        }
    }

    /// The `NR ☐YES ☐NO` corner of a real label, repurposed for the one bit of
    /// state worth printing there.
    private var losslessTick: some View {
        let lossless: Set<AudioFormat> = [.flac16, .alac16, .mqa24]
        let isLossless = player.nowPick.map { lossless.contains($0.format) } ?? false
        return Text(isLossless ? "LOSSLESS ☑" : "LOSSLESS ☐")
            .font(theme.type.numeric(7))
            .foregroundStyle(ink.opacity(0.5))
            .lineLimit(1)
            .fixedSize()
            .accessibilityHidden(true)
    }

    // --- shoulders + window ----------------------------------------------------

    private var windowBlock: some View {
        HStack(spacing: 8) {
            leftShoulder
            window
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            rightShoulder
        }
    }

    private var leftShoulder: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("A")
                .font(theme.type.title(14))
            if let badge = player.nowPick?.format.badge {
                Text(badge)
                    .font(theme.type.numeric(11).weight(.bold))
            }
            Text("POSITION HIGH")
                .font(theme.type.numeric(6))
                .tracking(0.75)
            if let specsLine {
                Text(specsLine)
                    .font(theme.type.numeric(12).weight(.bold))
            }
        }
        .foregroundStyle(theme.palette.accent.opacity(0.85))
        .lineLimit(1)
        .truncationMode(.tail)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 54, alignment: .leading)
        .accessibilityHidden(true)
    }

    /// Rendered only when both halves are known — never a `--/--` placeholder.
    private var specsLine: String? {
        guard let specs = player.specs, let bits = specs.bitDepth, specs.sampleRate > 0 else {
            return nil
        }
        return "\(bits)/\(Int((specs.sampleRate / 1000).rounded()))"
    }

    private var rightShoulder: some View {
        let saved = NowPlayingFavorite.isSaved(player.current, favorites: app.favorites)
        return VStack(spacing: 4) {
            HapticButton(.transportStep) {
                NowPlayingFavorite.toggle(player.current, favorites: app.favorites)
            } label: {
                Image(systemName: saved ? "star.fill" : "star")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.palette.accent)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(player.current?.showId == nil)
            .accessibilityLabel("Save show to Favorites")
            .accessibilityAddTraits(saved ? .isSelected : [])

            Text("applenugs")
                .font(theme.type.numeric(6).weight(.bold))
                .tracking(0.9)
                .foregroundStyle(theme.palette.accent.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
                .fixedSize()
        }
        .frame(width: 54)
    }

    /// The cover shows through the window behind the reels, and the exposed
    /// tape span across the bottom **is** the scrubber — the detail the whole
    /// variant is built around. `MiniPlayerScrubTrack` already reserves a 20 pt
    /// hit area behind its 4 pt strip, so it is draggable despite being thin.
    ///
    /// The reels are pinned to the *top* of the window on purpose: now that
    /// their tape packs are real (up to 42 pt across, Task 5), a bottom-anchor
    /// would run the packs straight through the scrubber strip instead of a
    /// real cassette's read: two full reels up top, a bare span of tape
    /// exposed along the bottom edge underneath them.
    private var window: some View {
        ZStack {
            LinearGradient(colors: [.white.opacity(0.16), .black.opacity(0.45)],
                           startPoint: .top, endPoint: .bottom)

            VStack(spacing: 0) {
                CassetteReels()          // Task 5 gives these their progress-driven packs
                    .padding(.top, 6)
                Spacer(minLength: 2)
                MiniPlayerScrubTrack(trackHeight: 4,
                                     showsClocks: false,
                                     fillColor: theme.palette.accent)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 2)
            }
        }
        .background {
            if let image = player.nowPlayingImage {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(0.8)
                    .accessibilityHidden(true)
            } else {
                theme.palette.raised
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(.black.opacity(0.55), lineWidth: 1)
        }
        .frame(minHeight: 78)
    }

    // --- ridged bottom edge -----------------------------------------------------

    /// Transport molded into the ridged edge, with the clocks in the shell's
    /// bottom corners where a real cassette has its two round openings.
    private var ridgedBand: some View {
        HStack(spacing: 6) {
            MiniPlayerClock(kind: .elapsed)
                .frame(width: 44, alignment: .leading)

            MiniPlayerTransportTriad(style: .bare, glyphSize: 12, playDiameter: 26)
                .padding(.vertical, 3)
                .background {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(theme.palette.raised)
                        .overlay {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(.white.opacity(0.07), lineWidth: 1)
                        }
                }

            MiniPlayerClock(kind: .remaining)
                .frame(width: 44, alignment: .trailing)
        }
    }
}

/// The two reels in the cassette window, with tape packs that trade size as the
/// track runs — the supply reel on the left empties into the take-up on the right.
///
/// **A leaf view.** Pack radii derive from `currentTime`, which the playback
/// tick mutates ~4×/sec. Keeping that read here — and not in
/// `MiniPlayerCassette` — is what stops the whole shell, and the inspector's
/// queue list below it, from re-diffing on every tick.
struct CassetteReels: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    private let hubRadius: Double = 7.5
    private let fullRadius: Double = 21

    private var player: PlayerService { app.player }

    var body: some View {
        let progress = TapeGeometry.progress(currentTime: player.currentTime,
                                             duration: player.duration)
        HStack {
            reel(fraction: 1 - progress)   // supply
            Spacer()
            reel(fraction: progress)       // take-up
        }
        .padding(.horizontal, 10)
        .accessibilityHidden(true)
    }

    private func reel(fraction: Double) -> some View {
        let radius = TapeGeometry.packRadius(fraction: fraction,
                                             hub: hubRadius,
                                             full: fullRadius)
        return ZStack {
            Circle()
                .fill(RadialGradient(colors: [theme.palette.raised, theme.palette.base],
                                     center: .center,
                                     startRadius: 0,
                                     endRadius: CGFloat(radius)))
                .frame(width: CGFloat(radius) * 2, height: CGFloat(radius) * 2)
            ReelHub(isPlaying: player.isPlaying)
        }
        // Reserve the full footprint so a shrinking pack never shifts the layout.
        .frame(width: CGFloat(fullRadius) * 2, height: CGFloat(fullRadius) * 2)
    }
}

/// A splined hub that turns while the tape runs. `TimelineView` with
/// `paused:` costs nothing when stopped — same idiom as `VUMeter`.
///
/// The schedule itself already stops advancing `timeline.date` once paused,
/// so the angle derived from it holds at wherever the tape last stopped
/// instead of springing back to a fixed rest position — a real reel doesn't
/// snap backwards when you hit pause.
struct ReelHub: View {
    @Environment(\.theme) private var theme
    let isPlaying: Bool
    var diameter: CGFloat = 15

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !isPlaying)) { timeline in
            let angle = Angle.degrees(timeline.date.timeIntervalSinceReferenceDate * 100)
            ZStack {
                Circle().fill(theme.palette.textPrimary)
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(theme.palette.textPrimary)
                        .frame(width: diameter * 0.18, height: diameter)
                        .rotationEffect(.degrees(Double(i) * 60))
                }
                Circle()
                    .fill(theme.palette.base)
                    .frame(width: diameter * 0.45, height: diameter * 0.45)
            }
            .frame(width: diameter, height: diameter)
            .rotationEffect(angle)
        }
    }
}
