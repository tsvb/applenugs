import SwiftUI

// The now-playing pill's shelf and duck on iPhone Duo.
//
// Where the tab bar is laid out VERTICALLY (`\.toolbarVerticalEdge` non-nil),
// `.tabBarMinimizeBehavior(.onScrollDown)` never moves the bottom accessory out
// of the content's way. Toggling `tabViewBottomAccessory(isEnabled:)` can't
// stand in for it either — it pops (or crossfades in place) and every toggle
// reflows the tab content's bottom safe area by 38–56pt, mid-scroll, under the
// thumb, with no say over the motion. So there, and only there, the shell
// disables the accessory and mounts the pill itself, ON ITS OWN SHELF
// (`docs/design/yeti-theme/yeti-pill-shelf.html`): an opaque band across the
// bottom of the tab content that the content stops at, so nothing busy is ever
// behind the pill's glass. Scrolling down tips the pill into the shelf through
// its hang slot and the shelf folds to a 16pt lip above the home indicator, giving the page the room;
// scrolling up, reaching the top, stopping for a second, or tapping the slot
// opens the shelf and pops the pill back.
//
// The shelf DOES reflow the content mid-scroll — that is the design: every
// scroll view's bottom margin follows the lip, on the shelf's own curve. That
// makes the duck a feedback loop (a fold at the bottom of a page shrinks the
// scrollable range, which reads as a scroll up, which opens the shelf, which
// reads as a scroll down…). `PillDuckPolicy` breaks it: deltas are measured
// inside the range both samples share, and its `Gate` drops every sample that
// isn't the user's own drag or fling, and every sample for `settleWindow`
// after each transition, while the shelf is moving.
//
// Pieces: `PillDuckPolicy` (pure, tested) decides; `PillDuck` holds the one
// observable flag, the gate, and the idle timer; `PillDuckScrollReporter` feeds
// it from every scrolling tab root and pads each to the lip; `PillShelfBand`
// draws the band inside each tab (so it sits UNDER the vertical tab bar, as
// the mockup has it — an overlay on the TabView would paint over the bar);
// `PillShelfOverlay` carries the pill and the slot above the TabView, so they
// ride over pushed screens. Regular iPhones — and the Duo wherever its bar is
// horizontal — never leave the system accessory, and none of this draws.

extension EnvironmentValues {
    /// True while the pill is mounted on its own shelf: the tab bar is
    /// vertical AND something is playing. Set once at the TabView by
    /// `NowPlayingAccessory`, and changes only when either of those does. The
    /// shelf's open/closed state is NOT in here — readers that follow the lip
    /// read `PillDuck` too, so a duck re-evaluates only them.
    @Entry var pillOverlayActive = false
}

/// Pill placement on the shelf (heights live in `PillShelfGeometry`).
enum PillDuckMetrics {
    /// The system accessory's height (system-owned; 48 on every device
    /// measured), kept so the hand-mounted pill matches it.
    static let height: CGFloat = 48

    /// The pill's bottom edge above the screen's physical bottom edge.
    static let bottomInset: CGFloat = 14

    /// Horizontal inset inside the content column (the mockup's 22pt; on the
    /// outer display's 382pt column that leaves a 338pt pill).
    static let horizontalInset: CGFloat = 22

    /// Never wider than the system accessory on a regular iPhone.
    static let maxWidth: CGFloat = 360

    /// The hang slot punched in the shelf's lip, and how far below the lip its
    /// top sits. Its tap target is wider and taller than the slot.
    static let slotSize = CGSize(width: 40, height: 8)
    static let slotTopInset: CGFloat = 5
    static let slotHitSize = CGSize(width: 88, height: 36)

    /// The tuck: down through the slot, squashed (anchored at the pill's top).
    static let tipDrop: CGFloat = 70
    static let tipScale = CGSize(width: 0.94, height: 0.8)

    /// The pop's one overshoot, at 70% of the way: 5pt high, 2% wide, 4% tall.
    static let popRise: CGFloat = -5
    static let popScale = CGSize(width: 1.02, height: 1.04)
}

/// The shelf's timing, from the mockup's CSS (cubic-béziers carried over 1:1).
enum PillShelfMotion {
    /// The shelf folding: 300ms, starting 70ms after the pill starts to tip.
    static let fold = Animation.timingCurve(0.45, 0, 0.25, 1, duration: 0.30).delay(0.07)
    /// The shelf opening: 260ms ease-out, before the pill.
    static let open = Animation.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.26)

    /// The shelf's move for a transition, shared by the band, the slot, every
    /// scroll view's margin and the toast so the lip and all it carries move
    /// as one. Reduce Motion: none — the shelf snaps.
    static func shelf(ducked: Bool, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : (ducked ? fold : open)
    }

    /// The pill tipping in: 240ms ease-in, fading late (160ms from 90ms).
    static let tip = Animation.timingCurve(0.55, 0, 0.75, 0.2, duration: 0.24)
    static let tipFade = Animation.linear(duration: 0.16).delay(0.09)

    /// The pop, 440ms on one overshooting curve: up past the rest pose to the
    /// overshoot at 70%, then settling, opaque by 35%. One bounce, never two.
    static let popRise = Animation.timingCurve(0.2, 0.9, 0.3, 1.35, duration: 0.308)
    static let popSettle = Animation.timingCurve(0.2, 0.9, 0.3, 1.35, duration: 0.132)
    static let popFade = Animation.timingCurve(0.2, 0.9, 0.3, 1.35, duration: 0.154)

    /// The slot appearing (and leaving) late in either move.
    static let slotFade = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.16).delay(0.2)

    /// Reduce Motion: the pill only fades.
    static let reducedFade = Animation.linear(duration: 0.16)
}

/// The pill's ducked flag, owned by `IOSRootView` and shared through the
/// environment. Writes happen only on a transition, never per scroll frame —
/// the scroll bookkeeping lives in `@ObservationIgnored` storage.
@MainActor
@Observable
final class PillDuck {
    private(set) var isDucked = false

    /// The tab content's bottom safe area (the home-indicator band), measured
    /// at the tab's NavigationStack. Content padding is the shelf's height
    /// above THIS (`PillShelfGeometry.contentClearance`).
    private(set) var bottomSafeArea: CGFloat = 0

    @ObservationIgnored private var state = PillDuckPolicy.State.shown
    @ObservationIgnored private var gate = PillDuckPolicy.Gate()
    @ObservationIgnored private var idleReturn: Task<Void, Never>?

    /// How long after scrolling stops a ducked pill comes back.
    static let idleDelay: Duration = .seconds(1)

    /// The extra bottom margin content needs right now to stop at the lip.
    var contentClearance: CGFloat {
        PillShelfGeometry.contentClearance(ducked: isDucked, bottomSafeArea: bottomSafeArea)
    }

    func scrolled(from old: PillDuckPolicy.Sample, to new: PillDuckPolicy.Sample) {
        // The feedback guard: only the user's own scrolling, and never while
        // the shelf is still folding or opening under it. A dropped sample
        // leaves no debt — the next pair's `old` is already past it.
        guard gate.admits(at: Self.now) else { return }
        state = PillDuckPolicy.step(state, from: old, to: new)
        publish()
    }

    func scrollPhaseChanged(_ drive: PillDuckPolicy.Drive) {
        gate.drive = drive
        scheduleIdleReturn()
    }

    func measuredBottomSafeArea(_ inset: CGFloat) {
        guard inset != bottomSafeArea else { return }
        bottomSafeArea = inset
    }

    /// Bring the pill back now and forget any partial travel. The idle timer
    /// and the slot come through here too, so the policy's state is reset
    /// along with the flag — otherwise it would still think it was ducked and
    /// the next downward scroll would have nothing to re-accumulate.
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
        gate.transitioned(at: Self.now)
        // Ducked by a fling whose phase already went idle.
        if ducked { scheduleIdleReturn() }
    }

    private func scheduleIdleReturn() {
        idleReturn?.cancel()
        idleReturn = nil
        guard gate.drive == .idle, isDucked else { return }
        idleReturn = Task { [weak self] in
            try? await Task.sleep(for: Self.idleDelay)
            guard !Task.isCancelled else { return }
            self?.showNow()
        }
    }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    #if DEBUG
    /// Screenshot hook (`-UITestPillTucked`): tucks the pill with no idle
    /// return, so the closed shelf holds still long enough to shoot.
    func holdTuckedForScreenshot() {
        idleReturn?.cancel()
        idleReturn = nil
        state = PillDuckPolicy.State(visibility: .ducked, travel: 0)
        isDucked = true
        gate.transitioned(at: Self.now)
    }
    #endif
}

/// Feeds a scroll view's motion to `PillDuck`. Applied through
/// `View.reportsScrollForPillDuck()` (shared, a no-op on macOS) to every
/// vertically scrolling tab root.
///
/// Always attached — never conditionally — so a fold/unfold or a playback
/// start can't change the scroll view's identity (which would reset its
/// position and its owner's `@State`). While the shelf is inactive the
/// geometry transform returns a constant, so the action fires at most once.
///
/// Also pads the scroll view's bottom safe area so its content comes to rest
/// at the shelf's lip, following the lip as it folds and opens (same curve,
/// same delay). The hand-mounted shelf doesn't inset content the way the system
/// accessory does, and a `.safeAreaPadding` on the tab's NavigationStack does
/// NOT reach the hosted scroll views (measured: bottom inset stayed 34), so it
/// is applied on each scroll view, where it lands as a real content inset on
/// both ScrollView and List. `.contentMargins` also reaches a List, but folds
/// into its `contentSize` instead of its insets. An empty edge set when
/// inactive, so regular iPhones get no margin effect at all.
struct PillDuckScrollReporter: ViewModifier {
    /// False where the caller clears the shelf some other way (Downloads pads
    /// the list AND its storage footer with `clearsPillOverlay()` instead).
    let insetsContent: Bool

    @Environment(PillDuck.self) private var duck: PillDuck?
    @Environment(\.pillOverlayActive) private var overlayActive
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // VoiceOver users never get a pill that runs away from them.
        let active = overlayActive && !voiceOver && duck != nil
        let pads = overlayActive && insetsContent && duck != nil
        content
            .animation(PillShelfMotion.shelf(ducked: duck?.isDucked ?? false,
                                             reduceMotion: reduceMotion)) {
                $0.safeAreaPadding(pads ? .bottom : [], duck?.contentClearance ?? 0)
            }
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
                duck?.scrollPhaseChanged(Self.drive(phase))
            }
            // Pushed away (or tab switched) mid-fling: the phase may never
            // reach `.idle` here, so treat leaving as stopping.
            .onDisappear { duck?.scrollPhaseChanged(.idle) }
    }

    private static func drive(_ phase: ScrollPhase) -> PillDuckPolicy.Drive {
        switch phase {
        case .idle: .idle
        case .tracking, .interacting, .decelerating: .user
        case .animating: .system
        @unknown default: .system
        }
    }
}

/// Extra bottom safe area for a screen whose bottom isn't (only) a scroll view
/// — Downloads' storage footer sits below its list — while the shelf is
/// mounted. Follows the lip exactly as the reporter's margin above does.
struct PillOverlayClearance: ViewModifier {
    @Environment(PillDuck.self) private var duck: PillDuck?
    @Environment(\.pillOverlayActive) private var overlayActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .animation(PillShelfMotion.shelf(ducked: duck?.isDucked ?? false,
                                             reduceMotion: reduceMotion)) {
                $0.safeAreaPadding(overlayActive && duck != nil ? .bottom : [],
                                   duck?.contentClearance ?? 0)
            }
    }
}

/// The shelf itself: an opaque band across the bottom of a tab's content, from
/// the screen's physical bottom edge up to its frost lip. Mounted in each tab
/// (over its NavigationStack, so it stays put across pushes) because tab
/// content sits UNDER the tab bar: the band runs beneath the vertical rail,
/// where an overlay on the TabView would paint over it.
///
/// Draws nothing unless the pill is mounted on it. Opaque to touches too:
/// content scrolled behind it is out of sight, so it must be out of reach.
struct PillShelfBand: View {
    @Environment(PillDuck.self) private var duck: PillDuck?
    @Environment(\.pillOverlayActive) private var overlayActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme

    var body: some View {
        if overlayActive, let duck {
            let ducked = duck.isDucked
            band
                .frame(height: PillShelfGeometry.height(ducked: ducked, bottomSafeArea: duck.bottomSafeArea))
                .animation(PillShelfMotion.shelf(ducked: ducked, reduceMotion: reduceMotion),
                           value: ducked)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                // Under the rail, down to the glass, and behind a keyboard.
                .ignoresSafeArea(.all, edges: [.horizontal, .bottom])
                .accessibilityHidden(true)
        }
    }

    /// A night band a shade lighter at the lip than at the floor, with a frost
    /// hairline for the lip. Palette-derived, so on Yeti it lands on the
    /// mockup's #131A30 → #0E1322 and every other theme gets its own night.
    private var band: some View {
        let palette = theme.palette
        return LinearGradient(
            colors: [palette.base.mix(with: palette.raised, by: 0.5, in: .device),
                     palette.base.mix(with: .black, by: 0.08, in: .device)],
            startPoint: .top, endPoint: .bottom)
            .overlay(alignment: .top) {
                Rectangle().fill(palette.hairline).frame(height: 1)
            }
            .contentShape(Rectangle())
            // The lip's soft edge against the content above it.
            .shadow(color: .black.opacity(0.35), radius: 6, y: -3)
    }
}

/// The pill on its shelf, and the slot that brings it back, mounted by hand
/// over the TabView while the tab bar is vertical. The only view besides the
/// lip-followers that reads `PillDuck.isDucked`, so a duck re-evaluates these
/// and nothing above them.
struct PillShelfOverlay: View {
    @Environment(PillDuck.self) private var duck
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.theme) private var theme

    let onTap: () -> Void
    let onExpand: () -> Void

    /// The pill's tuck/pop transform and its opacity, driven explicitly so the
    /// pop can run as two legs (rise to the overshoot, settle).
    @State private var pose = Pose.rest
    @State private var opacity: Double = 1
    /// Bumped by every transition, so a superseded pop's second leg never runs.
    @State private var generation = 0

    var body: some View {
        let ducked = duck.isDucked
        ZStack(alignment: .bottom) {
            pill(ducked: ducked)
            slot(ducked: ducked)
        }
        // Laid out from the screen's physical bottom edge, like the band —
        // and like the band it stays put behind a keyboard, as the system
        // accessory does, rather than riding up over content without it.
        .ignoresSafeArea(.all, edges: .bottom)
        .onChange(of: ducked) { _, ducked in move(ducked: ducked) }
        // VoiceOver never tucks the pill: turning it on brings the pill (and
        // the shelf, and every margin that follows it) straight back.
        .onChange(of: voiceOver) { _, on in if on { duck.showNow() } }
        // A pill re-mounted (playback restarted, or the bar went vertical
        // again) never inherits a stale duck.
        .onAppear {
            duck.showNow()
            #if DEBUG
            // -UITestPillTucked: tuck the pill once and hold it, so the closed
            // shelf can be screenshotted (simctl can't scroll).
            if ProcessInfo.processInfo.arguments.contains("-UITestPillTucked") {
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    duck.holdTuckedForScreenshot()
                }
            }
            #endif
        }
    }

    private func pill(ducked: Bool) -> some View {
        // `tabViewBottomAccessoryPlacement` is nil out here; PillLayout reads
        // nil as `.expanded` and still sheds controls by measured width.
        NowPlayingPill(onTap: onTap, onExpand: onExpand)
            .frame(height: PillDuckMetrics.height)
            .glassEffect(in: Capsule())
            .frame(maxWidth: PillDuckMetrics.maxWidth)
            .padding(.horizontal, PillDuckMetrics.horizontalInset)
            // Anchored at the top: it tips forward into the slot below it.
            .scaleEffect(x: pose.scaleX, y: pose.scaleY, anchor: .top)
            .offset(y: pose.drop)
            .opacity(opacity)
            .padding(.bottom, PillDuckMetrics.bottomInset)
            // Out of reach while tucked: no taps on a pill that isn't there,
            // and nothing for VoiceOver focus to land on and get stranded by.
            .allowsHitTesting(!ducked)
            .accessibilityHidden(ducked)
    }

    /// The hang slot in the lip. Rides the lip as the shelf moves; shows only
    /// while the pill is tucked, and is then the button that brings it back.
    private func slot(ducked: Bool) -> some View {
        let height = PillShelfGeometry.height(ducked: ducked, bottomSafeArea: duck.bottomSafeArea)
        // The slot's center, above the physical bottom edge.
        let center = height - PillDuckMetrics.slotTopInset - PillDuckMetrics.slotSize.height / 2
        let hit = PillDuckMetrics.slotHitSize
        return Button {
            duck.showNow()
        } label: {
            Capsule()
                .fill(theme.palette.base.mix(with: .black, by: 0.65, in: .device)
                    .shadow(.inner(color: .black.opacity(0.7), radius: 1.5, y: 2)))
                .frame(width: PillDuckMetrics.slotSize.width,
                       height: PillDuckMetrics.slotSize.height)
                .shadow(color: theme.palette.textPrimary.opacity(0.08), radius: 0, y: 1)
                .animation(PillShelfMotion.slotFade) { $0.opacity(ducked ? 1 : 0) }
                .frame(width: hit.width, height: hit.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show the player")
        .animation(PillShelfMotion.shelf(ducked: ducked, reduceMotion: reduceMotion)) {
            $0.offset(y: hit.height / 2 - center)
        }
        .allowsHitTesting(ducked)
        .accessibilityHidden(!ducked)
    }

    private func move(ducked: Bool) {
        generation += 1
        let leg = generation
        if reduceMotion {
            // No tip, no squash, no travel: the pill only fades.
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { pose = .rest }
            withAnimation(PillShelfMotion.reducedFade) { opacity = ducked ? 0 : 1 }
            return
        }
        if ducked {
            withAnimation(PillShelfMotion.tip) { pose = .tipped }
            withAnimation(PillShelfMotion.tipFade) { opacity = 0 }
        } else {
            // Already on the shelf (a re-mount clearing a stale duck): no pop.
            guard pose != .rest || opacity < 1 else { return }
            withAnimation(PillShelfMotion.popRise) {
                pose = .overshoot
            } completion: {
                guard leg == generation else { return }
                withAnimation(PillShelfMotion.popSettle) { pose = .rest }
            }
            withAnimation(PillShelfMotion.popFade) { opacity = 1 }
        }
    }

    struct Pose: Equatable {
        var drop: CGFloat
        var scaleX: CGFloat
        var scaleY: CGFloat

        static let rest = Pose(drop: 0, scaleX: 1, scaleY: 1)
        static let tipped = Pose(drop: PillDuckMetrics.tipDrop,
                                 scaleX: PillDuckMetrics.tipScale.width,
                                 scaleY: PillDuckMetrics.tipScale.height)
        static let overshoot = Pose(drop: PillDuckMetrics.popRise,
                                    scaleX: PillDuckMetrics.popScale.width,
                                    scaleY: PillDuckMetrics.popScale.height)
    }
}
