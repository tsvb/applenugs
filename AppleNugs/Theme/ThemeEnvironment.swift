import SwiftUI

// MARK: - Environment keys

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.tapeRoom
}

private struct ArtColorKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
    /// The clamped dominant color of the current cover, when an art-driven
    /// theme is active; nil otherwise.
    var artColor: Color? {
        get { self[ArtColorKey.self] }
        set { self[ArtColorKey.self] = newValue }
    }
}

// MARK: - Root modifier

/// Recolors the bulk of the app from one place: tint, default text color,
/// window-ish background, default font, dark scheme, and a crossfade on switch.
private struct ThemedRoot: ViewModifier {
    let theme: Theme
    let artColor: Color?

    func body(content: Content) -> some View {
        content
            .tint(theme.effectiveAccent(art: artColor))
            .foregroundStyle(theme.palette.textPrimary)
            .background(theme.palette.base)
            .environment(\.font, theme.type.body(13))
            .preferredColorScheme(.dark)
            .animation(.easeInOut(duration: 0.35), value: theme.id)
    }
}

extension View {
    func themed(_ theme: Theme, art: Color?) -> some View {
        modifier(ThemedRoot(theme: theme, artColor: art))
    }
}

// MARK: - Surface helpers

extension View {
    /// A themed background surface (sidebar / inspector / transport) that also
    /// carries the faint paper grain when the theme asks for it.
    func themedSurface(_ theme: Theme, raised: Bool = true) -> some View {
        background(raised ? theme.palette.raised : theme.palette.base)
            .overlay {
                if theme.textureOpacity > 0 {
                    PaperGrain()
                        .opacity(theme.textureOpacity)
                        .allowsHitTesting(false)
                }
            }
    }

    /// The album-art wash behind a region, a no-op for themes without one.
    @ViewBuilder
    func artWash(_ style: WashStyle, color: Color?) -> some View {
        if style == .none || color == nil {
            self
        } else {
            background(ArtWashBackground(style: style, color: color ?? .clear))
        }
    }
}

// MARK: - Procedural paper grain (no bundled asset)

/// A cheap monochrome grain drawn with Canvas, tiling-free and theme-tintable.
/// Kept subtle; only used on raised surfaces at low opacity.
struct PaperGrain: View {
    var body: some View {
        Canvas { ctx, size in
            // A coarse deterministic speckle — enough tooth to kill flat paint.
            let step: CGFloat = 3
            var y: CGFloat = 0
            var seed: UInt64 = 0x9E3779B97F4A7C15
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    let v = Double((seed >> 33) & 0xFF) / 255.0
                    if v > 0.72 {
                        let rect = CGRect(x: x, y: y, width: 1, height: 1)
                        ctx.fill(Path(rect), with: .color(.white.opacity(v - 0.5)))
                    }
                    x += step
                }
                y += step
            }
        }
        .blendMode(.overlay)
    }
}
