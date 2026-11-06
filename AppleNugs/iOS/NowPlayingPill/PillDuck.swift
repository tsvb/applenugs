import SwiftUI

// The now-playing pill's duck on iPhone Duo.
//
// Where the tab bar is laid out VERTICALLY (`\.toolbarVerticalEdge` non-nil),
// `.tabBarMinimizeBehavior(.onScrollDown)` never moves the bottom accessory out
// of the content's way. Toggling `tabViewBottomAccessory(isEnabled:)` can't
// stand in for it either — it pops (or crossfades in place) and every toggle
// reflows the tab content's bottom safe area by 38–56pt, mid-scroll, under the
// thumb. So there, and only there, the shell disables the accessory and mounts
// the pill as its own overlay (`PillDuckOverlay`), which sinks below the bottom
// edge while the user scrolls down and springs back when they scroll up, reach
// the top, or stop for a second.
//
// Pieces: `PillDuckPolicy` (pure, tested) decides; `PillDuck` holds the one
// observable flag plus the idle timer; `PillDuckScrollReporter` feeds it from
// every scrolling tab root; `PillDuckOverlay` is the only view that reads the
// flag. Regular iPhones — and the Duo wherever its bar is horizontal — never
// leave the system accessory.

extension EnvironmentValues {
    /// True while the pill is mounted as our own overlay: the tab bar is
    /// vertical AND something is playing. Set once at the TabView by
    /// `NowPlayingAccessory`. Changes only when either of those does, never on
    /// a duck — the content clearance keyed on it must not reflow mid-scroll.
    @Entry var pillOverlayActive = false
}

/// Overlay geometry, measured against the system accessory on iPhone Duo's
/// outer display (probe: the accessory capsule spans y 606–654 in a 678pt
/// screen whose bottom safe-area edge is at 644, x 50–340 in a 382pt column).
enum PillDuckMetrics {
    /// The system accessory's height (system-owned; 48 on every device measured).
    static let height: CGFloat = 48

    /// The system accessory dips this far BELOW the bottom safe-area edge.
    /// The overlay is laid out against that edge, then pushed down to match.
    static let overhang: CGFloat = 10

    /// Horizontal inset inside the content column: 382 − 2×46 = the system's
    /// 290pt on the outer display.
    static let horizontalInset: CGFloat = 46

    /// Never wider than the system accessory on a regular iPhone.
    static let maxWidth: CGFloat = 360

    /// How far the pill's top rises above the bottom safe-area edge, and so
    /// the extra bottom margin scroll content gets while the overlay is
    /// mounted — the same clearance the system accessory gives (outer display:
    /// bottom safe area 34 → 72). The toast adds it to its 8pt gap.
    static let contentClearance: CGFloat = height - overhang

    /// How far the pill sinks when ducked. Clears the pill plus any bottom
    /// safe area up to ~80pt; past the screen edge the excess is invisible.
    static let duckDrop: CGFloat = 130
}

/// The pill's ducked flag, owned by `IOSRootView` and shared through the
/// environment. Writes happen only on a transition, never per scroll frame —
/// the scroll bookkeeping lives in `@ObservationIgnored` storage.
@MainActor
@Observable
final class PillDuck {
    private(set) var isDucked = false

    @ObservationIgnored private var state = PillDuckPolicy.State.shown
    @ObservationIgnored private var scrollIsIdle = true
    @ObservationIgnored private var idleReturn: Task<Void, Never>?

    /// How long after scrolling stops a ducked pill comes back.
    static let idleDelay: Duration = .seconds(1)

    func scrolled(from old: PillDuckPolicy.Sample, to new: PillDuckPolicy.Sample) {
        state = PillDuckPolicy.step(state, from: old, to: new)
        publish()
    }

    func scrollPhaseChanged(isIdle: Bool) {
        scrollIsIdle = isIdle
        scheduleIdleReturn()
    }

    /// Bring the pill back now and forget any partial travel. The idle timer
    /// comes through here too, so the policy's state is reset along with the
    /// flag — otherwise it would still think it was ducked and the next
    /// downward scroll would have nothing to re-accumulate.
    func showNow() {
        idleReturn?.cancel()
        idleReturn = nil
        state = .shown
        publish()
    }

    private func publish() {
        let ducked = state.visibility == .ducked
        guard ducked != isDucked else { return }
        isDucked = ducked
        // Ducked by a scroll that is already settling (a programmatic scroll,
        // or the last frame of a deceleration landing after `.idle`).
        if ducked { scheduleIdleReturn() }
    }

    private func scheduleIdleReturn() {
        idleReturn?.cancel()
        idleReturn = nil
        guard scrollIsIdle, isDucked else { return }
        idleReturn = Task { [weak self] in
            try? await Task.sleep(for: Self.idleDelay)
            guard !Task.isCancelled else { return }
            self?.showNow()
        }
    }
}

/// Feeds a scroll view's motion to `PillDuck`. Applied through
/// `View.reportsScrollForPillDuck()` (shared, a no-op on macOS) to every
/// vertically scrolling tab root.
///
/// Always attached — never conditionally — so a fold/unfold or a playback
/// start can't change the scroll view's identity (which would reset its
/// position and its owner's `@State`). While the overlay is inactive the
/// geometry transform returns a constant, so the action fires at most once.
///
/// Also gives the scroll view a constant extra bottom safe area while the
/// overlay is mounted, so the last row can scroll clear of the pill. The
/// hand-mounted overlay doesn't inset content the way the system accessory
/// does, and a `.safeAreaPadding` on the tab's NavigationStack does NOT reach
/// the hosted scroll views (measured: bottom inset stayed 34), so it is applied
/// on each scroll view, where it lands as a real content inset on both
/// ScrollView and List (measured: 72, the accessory's own figure).
/// `.contentMargins` also reaches a List, but folds into its `contentSize`
/// instead of its insets. Keyed on `pillOverlayActive` alone —
/// it reflows at playback start/stop exactly as the accessory would, and
/// NEVER on a duck. An empty edge set when inactive, so regular iPhones get
/// no margin effect at all.
struct PillDuckScrollReporter: ViewModifier {
    /// False where the caller clears the pill some other way (Downloads pads
    /// the list AND its storage footer with `clearsPillOverlay()` instead).
    let insetsContent: Bool

    @Environment(PillDuck.self) private var duck: PillDuck?
    @Environment(\.pillOverlayActive) private var overlayActive
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    func body(content: Content) -> some View {
        // VoiceOver users never get a pill that runs away from them.
        let active = overlayActive && !voiceOver && duck != nil
        content
            .safeAreaPadding(overlayActive && insetsContent ? .bottom : [],
                             PillDuckMetrics.contentClearance)
            .onScrollGeometryChange(for: PillDuckPolicy.Sample.self) { geometry in
                guard active else { return .inactive }
                return PillDuckPolicy.Sample(
                    contentOffsetY: geometry.contentOffset.y,
                    insetTop: geometry.contentInsets.top,
                    insetBottom: geometry.contentInsets.bottom,
                    contentHeight: geometry.contentSize.height,
                    frameHeight: geometry.visibleRect.height)
            } action: { old, new in
                guard active else { return }
                duck?.scrolled(from: old, to: new)
            }
            .onScrollPhaseChange { _, phase in
                guard active else { return }
                duck?.scrollPhaseChanged(isIdle: phase == .idle)
            }
            // Pushed away (or tab switched) mid-fling: the phase may never
            // reach `.idle` here, so treat leaving as stopping.
            .onDisappear { duck?.scrollPhaseChanged(isIdle: true) }
    }
}

/// Extra bottom safe area for a screen whose bottom isn't (only) a scroll view
/// — Downloads' storage footer sits below its list — while the overlay is
/// mounted. Same key and same reflow rules as the reporter's margin above.
struct PillOverlayClearance: ViewModifier {
    @Environment(\.pillOverlayActive) private var overlayActive

    func body(content: Content) -> some View {
        content.safeAreaPadding(overlayActive ? .bottom : [],
                                PillDuckMetrics.contentClearance)
    }
}

/// The pill, mounted by hand over the TabView while the tab bar is vertical.
/// The only view that reads `PillDuck.isDucked`, so a duck re-evaluates this
/// and nothing above it.
struct PillDuckOverlay: View {
    @Environment(PillDuck.self) private var duck
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    let onTap: () -> Void
    let onExpand: () -> Void

    var body: some View {
        // VoiceOver turning on while ducked brings the pill straight back.
        let ducked = duck.isDucked && !voiceOver
        let moves = ducked && !reduceMotion

        // `tabViewBottomAccessoryPlacement` is nil out here; PillLayout reads
        // nil as `.expanded` and still sheds controls by measured width.
        NowPlayingPill(onTap: onTap, onExpand: onExpand)
            .frame(height: PillDuckMetrics.height)
            .glassEffect(in: Capsule())
            .frame(maxWidth: PillDuckMetrics.maxWidth)
            .padding(.horizontal, PillDuckMetrics.horizontalInset)
            // Squash on the way down (anchored at the bottom, so it flattens
            // into the edge it's sinking past); the return spring overshoots
            // through 1.0, so it briefly stretches tall before settling.
            .scaleEffect(x: moves ? 1.06 : 1, y: moves ? 0.82 : 1, anchor: .bottom)
            .offset(y: PillDuckMetrics.overhang + (moves ? PillDuckMetrics.duckDrop : 0))
            // Reduce Motion: no travel, no squash — a plain fade.
            .opacity(ducked && reduceMotion ? 0 : 1)
            .animation(animation(ducked: ducked), value: ducked)
            // Out of reach while ducked: no taps on an off-screen pill, and
            // nothing for VoiceOver focus to land on and get stranded by.
            .allowsHitTesting(!ducked)
            .accessibilityHidden(ducked)
            // A pill re-mounted (playback restarted, or the bar went vertical
            // again) never inherits a stale duck.
            .onAppear { duck.showNow() }
    }

    private func animation(ducked: Bool) -> Animation {
        if reduceMotion { return .easeInOut(duration: 0.2) }
        return ducked
            ? .easeIn(duration: 0.22)
            : .spring(response: 0.42, dampingFraction: 0.58)
    }
}
