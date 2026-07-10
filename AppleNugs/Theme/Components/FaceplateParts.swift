import SwiftUI

// Shared hardware-flavored controls for The Receiver's transports — the Mac
// FaceplateTransport and the iOS TouchFaceplate render the same parts.

/// Two horizontal LED-segment level bars (L/R) that sway while playing and rest
/// at the floor when paused. Synthesized motion (no FFT), throttled to ~12fps
/// and frozen when not playing.
struct VUMeter: View {
    @Environment(\.theme) private var theme
    let isPlaying: Bool

    private let segments = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: !isPlaying)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            VStack(spacing: 3) {
                channel(level: level(t, seed: 0.0), label: "L")
                channel(level: level(t, seed: 1.7), label: "R")
            }
        }
    }

    private func level(_ t: Double, seed: Double) -> Double {
        guard isPlaying else { return 0.06 }
        let a = 0.5 + 0.5 * sin(t * 6.0 + seed)
        let b = 0.5 + 0.5 * sin(t * 11.3 + seed * 2.3)
        return min(1, 0.22 + 0.62 * (0.6 * a + 0.4 * b))
    }

    private func channel(level: Double, label: String) -> some View {
        let lit = Int((level * Double(segments)).rounded())
        return HStack(spacing: 4) {
            Text(label)
                .font(theme.type.numeric(8).weight(.bold))
                .foregroundStyle(theme.palette.textSecondary)
                .frame(width: 8)
            HStack(spacing: 1.5) {
                ForEach(0..<segments, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color(index: i, lit: i < lit))
                        .frame(width: 5, height: 7)
                        .opacity(i < lit ? 1 : 0.35)
                }
            }
        }
    }

    private func color(index: Int, lit: Bool) -> Color {
        guard lit else { return theme.palette.hairline }
        let isPeak = index >= segments - 2
        return isPeak ? (theme.palette.vuPeak ?? theme.palette.accent) : theme.palette.accent
    }
}

/// A round machined-metal transport button: radial-gradient face, hairline rim,
/// accent glyph, optional glow while engaged.
struct KnurledButton: View {
    @Environment(\.theme) private var theme
    let system: String
    let size: CGFloat
    let glow: Bool
    let action: () -> Void

    var body: some View {
        // The whole point of a machined button is that it thunks; a silent one
        // is a picture of a button.
        HapticButton(.machinedPress, action: action) {
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(hex: 0x2A2622), Color(hex: 0x141210)],
                        center: .center, startRadius: 1, endRadius: size))
                Circle().strokeBorder(theme.palette.hairline, lineWidth: 1)
                Image(systemName: system)
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(theme.palette.accent)
            }
            .frame(width: size, height: size)
            .shadow(color: glow ? theme.palette.accent.opacity(0.55) : .clear, radius: glow ? 6 : 0)
        }
        .buttonStyle(.plain)
    }
}
