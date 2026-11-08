import SwiftUI

// MARK: - Environment keys

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.tapeRoom
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - Root modifier

/// Recolors the bulk of the app from one place: tint, default text color,
/// window-ish background, default font, dark scheme, and a crossfade on switch.
private struct ThemedRoot: ViewModifier {
    let theme: Theme

    func body(content: Content) -> some View {
        content
            .tint(theme.rootTint)
            .foregroundStyle(theme.palette.textPrimary)
            .background(theme.palette.base)
            .environment(\.font, theme.type.body(13))
            .preferredColorScheme(.dark)
            .animation(.easeInOut(duration: 0.35), value: theme.id)
    }
}

extension View {
    func themed(_ theme: Theme) -> some View {
        modifier(ThemedRoot(theme: theme))
    }
}

// MARK: - Surface helpers

extension View {
    /// A themed background surface (sidebar / inspector / transport).
    func themedSurface(_ theme: Theme, raised: Bool = true) -> some View {
        background(raised ? theme.palette.raised : theme.palette.base)
    }

    /// iOS List rows paint an opaque system background over the themed base
    /// (macOS rows are transparent already) — clear it so the theme's warm
    /// base shows through. No-op on macOS.
    func themedListRow() -> some View {
        #if os(iOS)
        return listRowBackground(Color.clear)
        #else
        return self
        #endif
    }

    /// `.tint(color)` only when there is one, so a `nil` leaves the inherited
    /// root tint in place rather than resetting it (the five themes' controls
    /// must keep exactly the tint they inherit today). Yeti passes foil where
    /// time moves, against its snow root tint.
    @ViewBuilder
    func tintIfSet(_ color: Color?) -> some View {
        if let color { tint(color) } else { self }
    }
}
