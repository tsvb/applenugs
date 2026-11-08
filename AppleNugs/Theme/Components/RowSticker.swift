import SwiftUI

/// Yeti's play-state disc for a row: four night-ink bars stepping down
/// 100/75/50/25 on sticker stock while playing; the same disc with the bars
/// lying flat on idle-gray stock (`palette.textIdle`) while paused. Marks the
/// queue's playing slot and the setlist's playing row. Translated from the
/// design sheet's `.rs` / `.rs .stair` / `.rs.paused` / `.rs.sm`.
///
/// **One constant frame in both states** — a pause must never resize a row.
/// Static: no `TimelineView`, no animation, so it costs nothing per frame.
struct RowSticker: View {
    enum Size: CGFloat, CaseIterable, Sendable {
        /// Setlist rows (the number column of the playing row).
        case s20 = 20
        /// The queue's playing slot.
        case s16 = 16

        var diameter: CGFloat { rawValue }
    }

    /// The bar heights while playing, as fractions of the stair's height.
    static let stair: [CGFloat] = [1, 0.75, 0.5, 0.25]
    /// Paused, every bar lies at the stair's lowest step.
    static let flat: CGFloat = 0.25
    static let tilt: Angle = .degrees(-9)

    @Environment(\.theme) private var theme

    let isPlaying: Bool
    var size: Size = .s20

    var body: some View {
        let d = size.diameter
        let stairHeight = d * 0.46
        ZStack {
            if isPlaying {
                StickerStock(shape: Circle())
            } else {
                Circle().fill(theme.palette.textIdle)
            }
            HStack(alignment: .bottom, spacing: d * 0.07) {
                ForEach(Self.stair.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(theme.stickerInk)
                        .frame(width: d * 0.1,
                               height: stairHeight * (isPlaying ? Self.stair[i] : Self.flat))
                }
            }
            .frame(height: stairHeight, alignment: .bottom)
        }
        .frame(width: d, height: d)
        .rotationEffect(Self.tilt)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isPlaying ? "Playing" : "Paused")
    }
}
