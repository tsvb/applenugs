import SwiftUI

/// An initials tile — the honest stand-in for art when there is none (artists
/// have no cover), reused as the now-playing chip fallback.
struct MonogramTile: View {
    @Environment(\.theme) private var theme
    let text: String
    var size: CGFloat = 28

    private var initials: String {
        let words = text.split(whereSeparator: { $0 == " " || $0 == "&" })
        let first = words.first?.first.map(String.init) ?? ""
        let second = words.dropFirst().first?.first.map(String.init) ?? ""
        let result = (first + second).uppercased()
        return result.isEmpty ? "?" : result
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
            .fill(theme.palette.raised)
            .overlay {
                Text(initials)
                    .font(theme.type.section(size * 0.4))
                    .foregroundStyle(theme.palette.accent)
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                    .strokeBorder(theme.palette.hairline, lineWidth: 1)
            }
            .frame(width: size, height: size)
    }
}
