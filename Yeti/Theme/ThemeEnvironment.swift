import SwiftUI

// MARK: - Environment keys

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.yeti
}

extension EnvironmentValues {
    /// The design's tokens. Its default is `Theme.yeti`, the only design, so
    /// nothing has to inject it.
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - Root modifier

/// Recolors the bulk of the app from one place: tint, default text color,
/// window-ish background, default font, dark scheme.
///
/// The tint is snow (`textPrimary`), so system-tinted controls (prominent
/// buttons, the selected tab, toggles, links, untinted sliders) never paint an
/// accent fill; the accent is applied explicitly, only where time moves
/// (scrub sliders, the pill ring, progress).
private struct ThemedRoot: ViewModifier {
    let theme: Theme

    func body(content: Content) -> some View {
        content
            .tint(theme.palette.textPrimary)
            .foregroundStyle(theme.palette.textPrimary)
            .background(theme.palette.base)
            .environment(\.font, theme.type.body(13))
            .preferredColorScheme(.dark)
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
}
