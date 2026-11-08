import SwiftUI

// Yeti's two small tags, translated from the surfaces sheet's `.tag` and
// `.tag.plain`: one 19pt-tall shape, two meanings. Offers and states get a
// sticker; facts get a plain tag, never sticker stock.

/// A label sticker for an offer or state on a poster or row — "Live", "Free".
/// Night ink on sticker stock, tilted −4°, with the tag lift.
struct LabelSticker: View {
    @Environment(\.theme) private var theme
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        TagText(text: text)
            .foregroundStyle(theme.palette.stickerInk)
            .background { StickerStock(shape: shape, lift: .tag) }
            .rotationEffect(.degrees(-4))
    }
}

/// A plain tag for a fact — "4K", "Audio", "PPV". Snow type on translucent
/// night, a 1pt frost outline, set square (no tilt, no lift).
struct PlainTag: View {
    @Environment(\.theme) private var theme
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        TagText(text: text)
            .foregroundStyle(theme.palette.textPrimary)
            .background {
                // rgba(15,20,36,.74): night ink; inset 1px rgba(233,238,247,.3): snow.
                shape.fill(theme.palette.stickerInk.opacity(0.74))
                shape.strokeBorder(theme.palette.textPrimary.opacity(0.3), lineWidth: 1)
            }
    }
}

/// `.tag`'s box: 19pt tall, 7pt side padding, 10.5pt black rounded, +0.01em.
private struct TagText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .black, design: .rounded))
            .tracking(0.105)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .frame(height: 19)
    }
}
