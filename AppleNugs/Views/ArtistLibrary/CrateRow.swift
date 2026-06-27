import SwiftUI

/// One dense library row: number · thumbnail · title · LIVE/4K badges · date.
/// Tapping navigates via the item's route; the context menu mirrors the
/// existing per-kind favorites behavior (albums aren't favoritable).
struct CrateRow: View {
    let item: CrateItem
    let index: Int

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationLink(value: item.route) {
            HStack(spacing: 9) {
                Text("\(index)")
                    .font(theme.type.numeric(11))
                    .foregroundStyle(theme.palette.textSecondary)
                    .frame(width: 22, alignment: .trailing)
                CrateThumb(url: item.imageURL, kind: item.kind)
                Text(item.title)
                    .font(theme.type.body(13))
                    .foregroundStyle(theme.palette.textPrimary)
                    .lineLimit(1)
                if item.isLive { badge("LIVE") }
                if item.has4K { badge("4K") }
                Spacer(minLength: 8)
                if let dateText = item.dateText {
                    Text(dateText)
                        .font(theme.type.numeric(11))
                        .foregroundStyle(theme.palette.textSecondary)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .help(item.title)
        .accessibilityLabel([item.title, item.kind.word, item.dateText].compactMap { $0 }.joined(separator: ", "))
        .contextMenu { favoriteButton }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(theme.type.numeric(10))
            .foregroundStyle(theme.palette.base)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(theme.palette.accent, in: RoundedRectangle(cornerRadius: 3))
    }

    @ViewBuilder private var favoriteButton: some View {
        switch item.kind {
        case .show:
            let fav = app.favorites.isShowFavorited(item.rawID)
            Button(fav ? "Remove from Favorites" : "Add to Favorites",
                   systemImage: fav ? "star.slash" : "star") {
                app.favorites.toggleShow(
                    id: item.rawID, title: item.title, artistName: item.artistName,
                    dateText: item.dateText, venue: item.venue,
                    imageURL: item.imageURL?.absoluteString)
            }
        case .video:
            let fav = app.favorites.isVideoFavorited(item.rawID)
            Button(fav ? "Remove from Favorites" : "Add to Favorites",
                   systemImage: fav ? "star.slash" : "star") {
                app.favorites.toggleVideo(
                    FavVideo(id: item.rawID, videoSku: 0, title: item.title,
                             artistName: item.artistName, dateText: item.dateText,
                             isLive: item.isLive,
                             imageURL: item.imageURL?.absoluteString, savedAt: Date()))
            }
        case .album:
            EmptyView()
        }
    }
}
