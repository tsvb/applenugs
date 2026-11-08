import SwiftUI

// Yeti's two button shapes. Primaries are snow with night ink and secondaries
// are frost-outlined with a snow label, never an accent fill: under Yeti the
// root tint is snow (`Theme.rootTint(art:)`), and a snow-tinted
// `.borderedProminent` would still draw a white label on the snow capsule.
//
// Colors come from the theme's tokens: snow = `textPrimary`, night ink =
// `base`, frost = `hairline`, shelf = `raised`. Size follows the environment's
// `controlSize` (`.small` 30pt, regular 34pt, `.large`/`.extraLarge` 50pt),
// the three button heights the design pages draw. A full-width button puts
// `.frame(maxWidth: .infinity)` on its label.

/// Snow capsule, night-ink heavy rounded label.
struct YetiPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        YetiButtonBody(configuration: configuration, kind: .primary)
    }
}

/// 1pt frost outline, snow heavy rounded label.
struct YetiSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        YetiButtonBody(configuration: configuration, kind: .secondary)
    }
}

extension ButtonStyle where Self == YetiPrimaryButtonStyle {
    static var yetiPrimary: YetiPrimaryButtonStyle { YetiPrimaryButtonStyle() }
}

extension ButtonStyle where Self == YetiSecondaryButtonStyle {
    static var yetiSecondary: YetiSecondaryButtonStyle { YetiSecondaryButtonStyle() }
}

/// The shared body: a view (not the style itself) so it can read the theme,
/// enabled state and control size from the environment.
private struct YetiButtonBody: View {
    enum Kind { case primary, secondary }

    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    let configuration: ButtonStyleConfiguration
    let kind: Kind

    private struct Metrics {
        let height, padding, fontSize: CGFloat
    }

    private var metrics: Metrics {
        switch controlSize {
        case .mini, .small:      return Metrics(height: 30, padding: 12, fontSize: 13)
        case .large, .extraLarge: return Metrics(height: 50, padding: 22, fontSize: 17)
        default:                 return Metrics(height: 34, padding: 16, fontSize: 14)
        }
    }

    var body: some View {
        let m = metrics
        configuration.label
            .font(.system(size: m.fontSize, weight: .heavy, design: .rounded))
            .lineLimit(1)
            .foregroundStyle(kind == .primary ? theme.palette.base : theme.palette.textPrimary)
            .padding(.horizontal, m.padding)
            .frame(minHeight: m.height)
            .background {
                switch kind {
                case .primary:
                    Capsule().fill(theme.palette.textPrimary
                        .opacity(configuration.isPressed ? 0.78 : 1))
                case .secondary:
                    Capsule().fill(theme.palette.raised
                        .opacity(configuration.isPressed ? 1 : 0))
                }
            }
            .overlay {
                if kind == .secondary {
                    Capsule().strokeBorder(theme.palette.hairline, lineWidth: 1)
                }
            }
            .contentShape(Capsule())
            .foilFocusOutline(Capsule())
            .opacity(isEnabled ? 1 : 0.5)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Icon buttons

/// Yeti's round icon button (`.ib` in the surfaces sheet): a 36pt disc with a
/// 1pt frost ring around a snow glyph, the show page's Play next / Queue /
/// Save on iPhone. `ringed: false` is `.ib.bare`, the glyph alone: the show
/// page's Downloaded state, a filled snow disc at `glyphSize` 26. Pair it with
/// `.labelStyle(.iconOnly)` so a `Label` keeps its title for accessibility.
struct YetiIconButtonStyle: ButtonStyle {
    var ringed = true
    var glyphSize: CGFloat = 16

    func makeBody(configuration: Configuration) -> some View {
        YetiIconButtonBody(configuration: configuration, ringed: ringed, glyphSize: glyphSize)
    }
}

extension ButtonStyle where Self == YetiIconButtonStyle {
    static var yetiIcon: YetiIconButtonStyle { YetiIconButtonStyle() }
}

private struct YetiIconButtonBody: View {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    let configuration: ButtonStyleConfiguration
    let ringed: Bool
    let glyphSize: CGFloat

    static let side: CGFloat = 36

    var body: some View {
        configuration.label
            .font(.system(size: glyphSize, weight: .semibold))
            .foregroundStyle(theme.palette.textPrimary)
            .frame(width: Self.side, height: Self.side)
            .background {
                Circle().fill(theme.palette.raised.opacity(configuration.isPressed ? 1 : 0))
            }
            .overlay {
                if ringed {
                    Circle().strokeBorder(theme.palette.hairline, lineWidth: 1)
                }
            }
            .contentShape(Circle())
            .foilFocusOutline(Circle())
            .opacity(isEnabled ? 1 : 0.5)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Keyboard focus (macOS)

extension View {
    /// The design sheet's `:focus-visible`: on macOS, while the enclosing
    /// focusable control (the button this sits inside) has keyboard focus, a
    /// 2pt foil (`palette.accent`) outline 3pt outside `shape`, in place of the
    /// system focus ring. Apply it inside a button's style or label, where
    /// `\.isFocused` reflects that button. An overlay only — it never changes
    /// the control's size. iOS: no change.
    ///
    /// Our own controls only; system controls (text fields, lists, menus,
    /// sliders) keep the system ring.
    func foilFocusOutline<S: InsettableShape>(_ shape: S) -> some View {
        modifier(FoilFocusOutline(shape: shape))
    }

    /// `.focusEffectDisabled()` on macOS only, for a `.plain` button whose
    /// label draws `foilFocusOutline` — so the foil outline replaces the
    /// system ring instead of joining it. iOS keeps its focus effects.
    @ViewBuilder
    func macFocusEffectDisabled(_ disabled: Bool = true) -> some View {
        #if os(macOS)
        focusEffectDisabled(disabled)
        #else
        self
        #endif
    }
}

private struct FoilFocusOutline<S: InsettableShape>: ViewModifier {
    let shape: S

    #if os(macOS)
    @Environment(\.theme) private var theme
    @Environment(\.isFocused) private var isFocused

    /// CSS `outline: 2px; outline-offset: 3px` — the stroke spans 3...5pt
    /// outside the control's edge.
    static var width: CGFloat { 2 }
    static var offset: CGFloat { 3 }

    func body(content: Content) -> some View {
        content
            .focusEffectDisabled()
            .overlay {
                if isFocused {
                    shape
                        .inset(by: -(Self.offset + Self.width))
                        .strokeBorder(theme.palette.accent, lineWidth: Self.width)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
    #else
    func body(content: Content) -> some View { content }
    #endif
}
