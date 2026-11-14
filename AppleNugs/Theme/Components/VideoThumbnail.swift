import SwiftUI

/// A 16:9 video poster card: cover art (or the themed placeholder) under a
/// centered play-circle overlay, with LIVE / 4K badges, over a title + artist
/// line. Used by the Videos grid, the Live & Upcoming row, and (later) the
/// per-artist Videos section. Clones ShowCard's text block but draws a 16:9
/// poster instead of the square CoverArt used for audio shows.
///
/// The surfaces sheet's `.vt`: no centered play glyph (the poster is the
/// button); the badges are a `LabelSticker` for offers (Live, Free) and a
/// `PlainTag` for facts (PPV, Audio, 4K); the poster sits flat with a 1pt
/// frost keyline, the placeholder glyph is slush, and the text block takes
/// ShowCard's heavy title over a slush artist line.
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
                .font(theme.type.title(15))
                .foregroundStyle(theme.palette.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let artist = video.artistName {
                Text(artist)
                    .font(theme.type.body(13))
                    .foregroundStyle(theme.palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: width, alignment: .leading)
    }

    private var poster: some View {
        ZStack {
            posterImage
            badges
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6).strokeBorder(theme.palette.hairline, lineWidth: 1)
        }
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
                .foregroundStyle(theme.palette.textSecondary))
    }

    /// `.vt .badges`: offers on the left, facts on the right, 8pt in, 5pt
    /// apart (the inset also clears the sticker's tilt and lift).
    private var badges: some View {
        VStack {
            HStack(alignment: .top, spacing: 5) {
                if video.isLive { LabelSticker("Live") }
                if video.access == .free { LabelSticker("Free") }
                if video.access == .ppv { PlainTag("PPV") }
                Spacer(minLength: 0)
                if video.isAudio { PlainTag("Audio") }
                if video.has4K { PlainTag("4K") }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
    }
}

extension VideoThumbnail where PosterAccessory == EmptyView {
    init(video: VideoSummary, width: CGFloat = 220) {
        self.init(video: video, width: width, posterAccessory: { EmptyView() })
    }
}
