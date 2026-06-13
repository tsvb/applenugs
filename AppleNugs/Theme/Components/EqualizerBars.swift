import SwiftUI

/// A 3-bar animated meter for the now-playing row. Driven by a TimelineView at
/// ~8fps and frozen flat when paused, so it costs nothing when idle.
struct EqualizerBars: View {
    @Environment(\.theme) private var theme
    @Environment(\.artColor) private var artColor
    let isPlaying: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.11, paused: !isPlaying)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(theme.effectiveAccent(art: artColor))
                        .frame(width: 2.5, height: height(bar: i, at: t))
                }
            }
            .frame(width: 16, height: 13)
        }
    }

    private func height(bar i: Int, at t: Double) -> CGFloat {
        guard isPlaying else { return 3 }
        let phase = t * 5.5 + Double(i) * 1.9
        return 4 + 8 * (0.5 + 0.5 * sin(phase))
    }
}
