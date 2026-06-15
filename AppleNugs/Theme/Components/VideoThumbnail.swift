import SwiftUI

/// A 16:9 video poster card: cover art (or the themed placeholder) under a
/// centered play-circle overlay, with LIVE / 4K badges, over a title + artist
/// line. Used by the Videos grid, the Live & Upcoming row, and (later) the
/// per-artist Videos section. Clones ShowCard's text block but draws a 16:9
/// poster instead of the square CoverArt used for audio shows.
struct VideoThumbnail<PosterAccessory: View>: View {
    @Environment(\.theme) private var theme
    let video: VideoSummary
    var width: CGFloat = 220
    /// Optional view placed in normal layout flow directly under the poster,
    /// above the title block (e.g. a Continue Watching progress bar). Kept in
    /// flow so it never depends on the variable height of the text block.
    @ViewBuilder var posterAccessory: () -> PosterAccessory

    init(video: VideoSummary, width: CGFloat = 220,
         @ViewBuilder posterAccessory: @escaping () -> PosterAccessory) {
        self.video = video
        self.width = width
        self.posterAccessory = posterAccessory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            poster
                .frame(width: width)
            posterAccessory()
            Text(video.title)
                .font(theme.type.body(12))
                .foregroundStyle(theme.palette.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let artist = video.artistName {
                Text(artist)
                    .font(theme.type.numeric(10))
                    .foregroundStyle(theme.palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: width, alignment: .leading)
    }

    private var poster: some View {
        ZStack {
            posterImage
            playOverlay
            badges
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var posterImage: some View {
        if let url = video.imageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    placeholder
                default:
                    placeholder.overlay(ProgressView().controlSize(.small))
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(theme.palette.raised)
            .overlay(Image(systemName: "play.rectangle")
                .foregroundStyle(theme.palette.accent.opacity(0.7)))
    }

    private var playOverlay: some View {
        Image(systemName: "play.circle.fill")
            .font(.system(size: 34))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(theme.palette.accent)
            .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
    }

    private var badges: some View {
        VStack {
            HStack(alignment: .top) {
                if video.isLive {
                    badge("LIVE", filled: true)
                }
                Spacer(minLength: 0)
                if video.has4K {
                    badge("4K", filled: false)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(6)
    }

    private func badge(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(theme.type.numeric(9).weight(.semibold))
            .tracking(0.5)
            .foregroundStyle(filled ? Color.white : theme.palette.textPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(filled ? theme.palette.accent : theme.palette.raised.opacity(0.9))
            }
    }
}

extension VideoThumbnail where PosterAccessory == EmptyView {
    init(video: VideoSummary, width: CGFloat = 220) {
        self.init(video: video, width: width, posterAccessory: { EmptyView() })
    }
}
