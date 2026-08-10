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
    let onExpand: () -> Void

    private var slot: PillLayout.Slot {
        // `.map` rather than `placement == .inline`: the latter would collapse
        // the optional to false before PillLayout sees it, so the nil case
        // (rendered outside a tab accessory — the offline sheet does this)
        // would never reach the branch its tests pin.
        PillLayout.slot(isInline: placement.map { $0 == .inline })
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
        // an `.overlay`, not an HStack sibling. A plain nested Button here
        // loses the touch to the container's own `.onTapGesture` (measured:
        // even the pre-existing play/pause button does, since it shares this
        // view's tap-gesture region); `PillSeekEdge` is proof an overlay
        // wins hit-testing instead, so the chevron follows that shape.
        .padding(.trailing, PillLayout.horizontalPadding + PillLayout.controlWidth + PillLayout.controlSpacing)
        .overlay(alignment: .bottom) { PillSeekEdge() }
        .overlay(alignment: .trailing) {
            // Fallback for a drag-up gesture that fought the tab bar's own
            // scroll-to-minimize handling (didn't recognize reliably against
            // the system gesture) — a plain tap into the panel instead.
            // Tap on the pill body still opens the full-screen player.
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
        // Buttons inside the pill win over this container tap.
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityAction(named: "Show playback controls", onExpand)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Now playing: \(title), \(subtitle ?? "")"))
        .accessibilityHint("Opens full-screen now playing")
    }

    private var title: String {
        app.player.current?.title ?? "Nothing playing"
    }

    private var subtitle: String? {
        app.player.current?.artist
    }
}
