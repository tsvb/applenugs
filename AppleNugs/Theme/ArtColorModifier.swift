import SwiftUI

/// Owns an `ArtColorProvider` and applies a window root's theming + live
/// art-color environment. Extracted from `RootView` so the main window and the
/// macOS Now Playing window tint from the same value.
struct ArtColorProvision: ViewModifier {
    let app: AppModel
    let theme: Theme

    @State private var artProvider = ArtColorProvider()

    /// The accent the chrome should use right now: the live art color when the
    /// active theme is art-driven, else nil (so static themes are untouched).
    private var activeArtColor: Color? {
        theme.consumesArtColor ? artProvider.color : nil
    }

    /// Refires the extractor when the track changes, when its art finishes
    /// loading, or when the theme's appetite for art changes.
    private var artTaskID: String {
        let track = app.player.current?.id.uuidString ?? "none"
        return "\(track)|\(app.player.nowPlayingImage != nil)|\(theme.consumesArtColor)"
    }

    func body(content: Content) -> some View {
        content
            .themed(theme, art: activeArtColor)
            .environment(\.artColor, activeArtColor)
            .task(id: artTaskID) {
                artProvider.update(
                    image: app.player.nowPlayingImage,
                    key: app.player.current?.artworkPath,
                    enabled: theme.consumesArtColor)
            }
    }
}

extension View {
    func providesArtColor(app: AppModel, theme: Theme) -> some View {
        modifier(ArtColorProvision(app: app, theme: theme))
    }
}
