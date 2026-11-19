import SwiftUI

extension View {
    /// Caps the full-screen player's content column at a readable width when it
    /// stands ALONE on a regular-width canvas (iPhone Duo's inner display held
    /// upright, or unfolded flat before the queue column existed). Apply it to
    /// the content stack, BEFORE its full-size frame and background, so the
    /// column centers and the background stays full-bleed.
    ///
    /// iOS-only: the macOS Now Playing window shares these views and must not
    /// change. iPhone is compact, so it takes the `.infinity` arm — a no-op,
    /// since the stack is already followed by an infinite frame.
    func nowPlayingReadableWidth() -> some View {
        modifier(NowPlayingReadableWidth())
    }
}

private struct NowPlayingReadableWidth: ViewModifier {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    /// The column cap. Inside the Duo's split the player column is narrower
    /// than this, so the cap only bites when the player is alone.
    static let maxWidth: CGFloat = 520

    func body(content: Content) -> some View {
        #if os(iOS)
        // A conditional VALUE, not an if/else branch: a size-class flip (fold
        // or unfold with the cover open) must not change the content's view
        // identity, or the players' @State (scrubbing, sheets) would reset.
        content.frame(maxWidth: sizeClass == .regular ? Self.maxWidth : .infinity)
        #else
        content
        #endif
    }
}
