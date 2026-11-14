import SwiftUI

/// Yeti's empty state (`.es` under a `.card.pack.sm` in the surfaces sheet):
/// the EMPTY blister pack, the app before anything has arrived, over a heavy
/// snow title and one slush line. Shared by the Library's Downloads and
/// Favorites, and the Videos tab.
struct EmptyPackMessage: View {
    @Environment(\.theme) private var theme

    let title: String
    let message: String

    /// The sheet's `.card.pack.sm` in the Library figure: 120pt wide.
    static let packWidth: CGFloat = 120

    var body: some View {
        VStack(spacing: 0) {
            BlisterPack(emptyStyle: .small)
                .frame(width: Self.packWidth)
                .accessibilityHidden(true)
            Text(title)
                .font(theme.type.title(20))
                .foregroundStyle(theme.palette.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.top, 22)
            Text(message)
                .font(theme.type.body(15))
                .foregroundStyle(theme.palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 290)
                .padding(.top, 6)
        }
        .padding(.horizontal, 28)
        .accessibilityElement(children: .combine)
    }
}
