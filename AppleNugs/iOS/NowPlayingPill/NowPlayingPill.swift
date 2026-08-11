import SwiftUI

/// The resting now-playing capsule, hosted by `tabViewBottomAccessory`.
///
/// Because the TabView owns the accessory, this rides above every screen —
/// including pushed detail views — with no per-screen wiring. That is the
/// entire reason the old `.safeAreaInset` bar is gone.
///
/// The system owns the height (48pt, measured) and hands us a narrower box
/// when the tab bar minimizes; `PillLayout` decides what survives that.
struct NowPlayingPill: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    /// What a tap on the pill body does. Injected so the pill owns no
    /// presentation state of its own.
    let onTap: () -> Void

    /// What the chevron does. Injected for the same reason as `onTap`, and for
    /// a second one: a `.sheet` attached inside `tabViewBottomAccessory` runs
    /// its content's body but never becomes visible — the accessory is a
    /// system-hosted container, not a normal presentation context. The shell
    /// presents the panel instead.
    ///
    /// Optional because the pill is also hand-mounted outside a tab accessory
    /// (the offline Downloads sheet), where there is no panel to expand into.
    /// `nil` hides the chevron entirely — a chevron that does nothing is
    /// worse than no chevron.
    let onExpand: (() -> Void)?

    /// Trailing padding: the chevron's lane, only when the chevron renders.
    private var trailingPadding: CGFloat {
        PillLayout.horizontalPadding
            + (onExpand != nil ? PillLayout.controlWidth + PillLayout.controlSpacing : 0)
    }

    private var slot: PillLayout.Slot {
        // `.map` rather than `placement == .inline`: the latter would collapse
        // the optional to false before PillLayout sees it, so the nil case
        // (rendered outside a tab accessory — the offline sheet does this)
        // would never reach the branch its tests pin.
        PillLayout.slot(isInline: placement.map { $0 == .inline })
    }

    /// Whether tapping the pill actually opens something. `onTap` stays a
    /// plain non-optional `() -> Void` — giving it the same optionality as
    /// `onExpand` would cascade into every call site for one accessibility
    /// gate — so this keys off `onExpand` instead. At both current call
    /// sites (the tab accessory, and the offline Downloads sheet) the two
    /// are wired together on purpose: there is a full-screen player to open
    /// exactly when there is a panel to expand into, and both are `nil`/no-op
    /// together in the sheet.
    private var canOpenFullScreen: Bool { onExpand != nil }

    /// "Now playing: title, artist" — but without a trailing ", " when a
    /// track has no artist.
    private var accessibilityLabelText: String {
        guard let subtitle else { return "Now playing: \(title)" }
        return "Now playing: \(title), \(subtitle)"
    }

    var body: some View {
        HStack(spacing: PillLayout.slotTextGap) {
            PillLeadingSlot()

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(theme.type.body(12.5).weight(.semibold))
                    .foregroundStyle(theme.palette.textPrimary)
                    .lineLimit(1)
                if PillLayout.showsArtistLine(for: slot), let subtitle {
                    Text(subtitle)
                        .font(theme.type.body(10.5))
                        .foregroundStyle(theme.palette.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            PillTransportControls(slot: slot)
        }
        .padding(.leading, PillLayout.horizontalPadding)
        // Trailing side reserves a lane for the panel-open chevron below —
        // rendered as an `.overlay` rather than an HStack sibling purely to
        // keep it out of the row's layout flow: the lane is reserved above
        // via `trailingPadding` regardless, and an overlay lets the chevron
        // appear or disappear (when `onExpand` is nil) without shifting any
        // other child in the HStack. The lane itself is only reserved when
        // the chevron actually renders — when `onExpand` is nil (the offline
        // Downloads sheet) there is no control to make room for, so the
        // title/artist column gets the space back instead of truncating
        // against dead space.
        .padding(.trailing, trailingPadding)
        .overlay(alignment: .trailing) {
            // Fallback for a drag-up gesture that fought the tab bar's own
            // scroll-to-minimize handling (didn't recognize reliably against
            // the system gesture) — a plain tap into the panel instead.
            // Tap on the pill body still opens the full-screen player.
            if let onExpand {
                HapticButton(.transportStep, action: onExpand) {
                    Image(systemName: "chevron.up")
                        .font(.caption.weight(.semibold))
                        .frame(width: PillLayout.controlWidth, height: PillLayout.controlWidth)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.palette.textSecondary)
                .accessibilityLabel("Show playback controls")
                .padding(.trailing, PillLayout.horizontalPadding)
            }
        }
        // The container tap sits in front, over the whole pill, and the nested
        // transport Buttons still win hit-testing against it — verified in the
        // simulator: tapping play/pause does NOT open the full-screen player,
        // and tapping the text column does. An earlier attempt to move this
        // into a `.background` broke the text-column tap entirely (the tap
        // never reached the background layer), so it stays here.
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .contain)
        // Both of these accessibility actions have to be applied AFTER
        // `.accessibilityElement(children: .contain)` above, or they attach
        // to the pre-container element and get dropped instead of landing on
        // the combined pill.
        .modifier(PillExpandAccessibilityAction(onExpand: onExpand))
        .modifier(PillOpenAccessibilityAction(canOpenFullScreen: canOpenFullScreen, onTap: onTap))
        .accessibilityLabel(accessibilityLabelText)
        // The offline Downloads sheet wires `onTap` to a no-op (there is no
        // full-screen player to open from there), so the hint and action
        // promising one are gated behind `canOpenFullScreen` too.
        .accessibilityHint(canOpenFullScreen ? "Opens full-screen now playing" : "")
    }

    private var title: String {
        app.player.current?.title ?? "Nothing playing"
    }

    private var subtitle: String? {
        app.player.current?.artist
    }
}

/// Applies the "Show playback controls" accessibility action only when the
/// pill actually has a panel to expand into. `.accessibilityAction` has no
/// optional-closure overload, so this conditionally attaches it rather than
/// wiring a no-op — mirrors the chevron's own `if let onExpand` above.
private struct PillExpandAccessibilityAction: ViewModifier {
    let onExpand: (() -> Void)?

    func body(content: Content) -> some View {
        if let onExpand {
            content.accessibilityAction(named: "Show playback controls", onExpand)
        } else {
            content
        }
    }
}

/// Applies the "Open full-screen player" accessibility action only when
/// there is somewhere for it to go — see `canOpenFullScreen` above. Same
/// `if let`-style shape as `PillExpandAccessibilityAction`: there is no
/// optional-closure overload of `.accessibilityAction` to lean on instead.
private struct PillOpenAccessibilityAction: ViewModifier {
    let canOpenFullScreen: Bool
    let onTap: () -> Void

    func body(content: Content) -> some View {
        if canOpenFullScreen {
            content.accessibilityAction(named: "Open full-screen player", onTap)
        } else {
            content
        }
    }
}
