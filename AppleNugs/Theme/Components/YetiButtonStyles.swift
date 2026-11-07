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
            .opacity(isEnabled ? 1 : 0.5)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
