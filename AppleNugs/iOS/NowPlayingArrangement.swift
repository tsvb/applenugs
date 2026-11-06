import SwiftUI

/// The full-screen player's container: on a canvas wide enough to split
/// (iPhone Duo's inner display, unfolded flat ≈ 951×669pt landscape), the
/// player sits beside its own queue — player primary, `DashboardPanel`
/// secondary, with the panel's "Now" section dropped because the player IS
/// the now-playing view. Where `.split.axes(.horizontal)` can't split — iPhone,
/// the Duo's compact outer display, Split View halves — the SDK shows only the
/// primary, and the player keeps its queue button and sheet.
///
/// The inner display held UPRIGHT (taller than wide, regular width) is the
/// one canvas the arrangement won't split but the queue still belongs beside
/// the player, so it gets explicit columns instead: a ~300pt player and a
/// narrower queue column (`NowPlayingColumns` holds the rule and the widths).
///
/// Measured on the Duo simulator (iOS 27.1, unfolded flat): the split is an
/// even 50/50 of the safe area (two 433.5×635pt columns), and each column
/// reports a COMPACT horizontal size class — so the players' regular-width
/// readable-width cap does not apply inside the split.
///
/// "Queue beside" is derived from the secondary's own appearance because the
/// SDK exposes no "is the secondary visible" signal for `.split` (only the
/// `.overlay` style has `overlayArrangementZIndex`). That assumes the
/// arrangement REMOVES the secondary when it can't split rather than keeping
/// it at zero size. It flips on layout change, never per tick, and this view
/// reads no `player.currentTime`.
///
/// `ArrangementView` is iOS 27.1+; the floor stays 26.1, so older systems take
/// the bare player on a compact canvas and the explicit columns on a regular one.
///
/// Swipe down to close: a vertical drag on the PLAYER (never the queue column,
/// whose ScrollView keeps its own vertical scrolling) moves the whole
/// arrangement down 1:1 and closes it past a threshold, otherwise springs it
/// back — policy in `NowPlayingDismissDrag`. It is a plain `.gesture`, so any
/// child gesture that recognizes wins: the scrub and volume sliders, every
/// button, and The Receiver's volume ladder (`DragGesture(minimumDistance: 0)`,
/// which recognizes on touch-down). The cover is presented with a clear
/// presentation background so the app shows through as the player slides;
/// at rest every player and the panel paint their own opaque, safe-area-
/// ignoring backgrounds, and the `palette.base` backing below covers any seam
/// (see the comment in `body` for why the moving layer carries its own safe area).
/// The drag state is per presentation (the cover's content is rebuilt each
/// time), and nothing here reads `player.currentTime`.
struct NowPlayingArrangement: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    /// The scene's size class — regular only on iPhone Duo's inner display.
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Live secondary instances, counted rather than flagged: if the
    /// arrangement rebuilds the secondary on a fold or rotation, the new
    /// instance's `onAppear` can land before the old one's `onDisappear`,
    /// which would leave a single Bool false while the column is on screen.
    @State private var visibleSecondaries = 0

    /// This drag's latched decision (see `NowPlayingDismissDrag.Phase`).
    @State private var dragPhase: NowPlayingDismissDrag.Phase = .undecided
    /// How far down the arrangement sits. `@State`, not `@GestureState`: a
    /// gesture state resets the moment the finger lifts, which would snap the
    /// player back before the close animation could carry it off-screen.
    @State private var dragOffset: CGFloat = 0
    /// Set once a close starts, so a stray sample can't fight the animation.
    @State private var closing = false
    /// Full height including the safe areas — the distance that takes the
    /// arrangement's top edge past the bottom of the screen.
    @State private var offscreenDistance: CGFloat = 0
    /// True while a drag is live. Its reset is the only signal of a CANCELED
    /// drag (`onEnded` doesn't run then), used to spring back from mid-drag.
    @GestureState private var dragActive = false

    var body: some View {
        // Why the reader: translated content does NOT paint the parts of its
        // backgrounds that extend into the window's safe area (measured on the
        // iPhone 17 Pro simulator: the 62pt top band went missing and the app
        // showed through above the player). So the moving layer is laid out
        // full-screen with the system safe area IGNORED, and the same insets
        // are handed back as `safeAreaPadding` — a safe area of its own that
        // moves with it. The reader itself respects the safe area so its proxy
        // reports the real insets in the same layout pass (a reader that
        // ignores them reports zero).
        GeometryReader { proxy in
            arrangement(NowPlayingColumns.layout(size: proxy.size,
                                                 regular: sizeClass == .regular,
                                                 supportsArrangement: Self.supportsArrangement))
                .safeAreaPadding(proxy.safeAreaInsets)
                .background { theme.palette.base.ignoresSafeArea() }
                .offset(y: dragOffset)
                .ignoresSafeArea()
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
        } action: { offscreenDistance = $0 }
        .onChange(of: dragActive) { _, active in
            guard !active else { return }
            // `onEnded` (if it runs at all) resets the phase in this same
            // event; hop once so we only act when it didn't.
            Task { @MainActor in
                guard !closing, dragPhase != .undecided else { return }
                dragPhase = .undecided
                withAnimation(Self.springBack) { dragOffset = 0 }
            }
        }
        .accessibilityAction(.escape) { dismiss() }
    }

    /// Whether this system has `ArrangementView` (iOS 27.1+).
    private static var supportsArrangement: Bool {
        if #available(iOS 27.1, *) { return true }
        return false
    }

    /// View identity across a pose change: the explicit columns and the
    /// `ArrangementView` are different containers, so moving between them — the
    /// inner display rotating between upright and flat, or folding from upright
    /// to the outer display — rebuilds the player and resets its `@State` (a
    /// scrub in progress, an open sheet). That is the price of keeping the
    /// SDK's fold-aware arrangement for the flat and folded poses, where it is
    /// verified to keep the player's state across a fold. Everything else is a
    /// VALUE change inside one structure: the queue column's width, and on
    /// older systems the column appearing or going away (`columns` keeps the
    /// player at the same position whether or not the queue is there).
    @ViewBuilder
    private func arrangement(_ layout: NowPlayingColumns.Layout) -> some View {
        if #available(iOS 27.1, *) {
            if case .columns(let queueWidth) = layout {
                columns(queueWidth: queueWidth)
            } else {
                // `.single` lands here too, deliberately: on a canvas the
                // arrangement can't split it shows the primary alone (every
                // iPhone, the outer display, Split View halves) — today's
                // behavior, and the structure the fold test verified.
                ArrangementView {
                    player
                } secondary: {
                    DashboardPanel(showsNowPlaying: false)
                        .onAppear { visibleSecondaries += 1 }
                        .onDisappear { visibleSecondaries = max(visibleSecondaries - 1, 0) }
                }
                .arrangementViewStyle(.split.axes(.horizontal))
                .environment(\.nowPlayingQueueBeside, visibleSecondaries > 0)
            }
        } else {
            switch layout {
            case .columns(let queueWidth): columns(queueWidth: queueWidth)
            case .single, .arrangement: columns(queueWidth: nil)
            }
        }
    }

    /// The player beside its queue in explicit columns — for the canvases
    /// `.split.axes(.horizontal)` won't split (iPhone Duo's inner display held
    /// UPRIGHT, ~535pt wide) — or, with a nil width, the player alone. The
    /// player takes everything the queue doesn't (>= `minPlayerWidth`).
    ///
    /// Both columns report a COMPACT horizontal size class, matching what the
    /// arrangement's columns report, so the players' readable-width cap stays
    /// off and they lay out exactly as they do in the flat split. Alone, the
    /// player keeps the scene's own size class.
    private func columns(queueWidth: CGFloat?) -> some View {
        HStack(spacing: 0) {
            player
                .environment(\.horizontalSizeClass, queueWidth != nil ? .compact : sizeClass)
                .environment(\.nowPlayingQueueBeside, queueWidth != nil)
            if let queueWidth {
                DashboardPanel(showsNowPlaying: false)
                    .frame(width: queueWidth)
                    .environment(\.horizontalSizeClass, .compact)
            }
        }
    }

    /// The swipe-down gesture sits on the PLAYER only, never the queue column.
    private var player: some View {
        NowPlayingScreen()
            .gesture(dismissDrag)
    }

    private static let springBack = Animation.spring(response: 0.3, dampingFraction: 0.85)

    /// Global coordinates: the view moves under the finger, so a local
    /// translation would feed the offset back into itself.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .global)
            .updating($dragActive) { _, active, _ in active = true }
            .onChanged { value in
                guard !closing else { return }
                dragPhase = NowPlayingDismissDrag.phase(after: dragPhase, translation: value.translation)
                dragOffset = NowPlayingDismissDrag.offset(for: value.translation, phase: dragPhase)
            }
            .onEnded { value in
                let phase = dragPhase
                dragPhase = .undecided
                guard !closing, phase == .tracking else { return }
                if NowPlayingDismissDrag.shouldDismiss(translation: value.translation,
                                                       predictedEnd: value.predictedEndTranslation,
                                                       phase: phase) {
                    close()
                } else {
                    withAnimation(Self.springBack) { dragOffset = 0 }
                }
            }
    }

    /// Carry the arrangement the rest of the way off-screen, then dismiss with
    /// animations disabled so the cover's own slide-down doesn't run on top.
    private func close() {
        closing = true
        let target = max(offscreenDistance > 0 ? offscreenDistance : 2000, dragOffset)
        withAnimation(.easeOut(duration: 0.22), completionCriteria: .logicallyComplete) {
            dragOffset = target
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { dismiss() }
        }
    }
}
