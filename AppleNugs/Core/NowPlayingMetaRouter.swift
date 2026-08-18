import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Turns a tap on a now-playing meta link into navigation.
///
/// The show half is exact and synchronous — `QueueTrack.showId` is a real
/// container id. The artist half is not: the player only ever knows a NAME, so
/// it has to be resolved against the catalog first.
///
/// Order matters. The resolve happens BEFORE anything is dismissed or pushed,
/// so a miss leaves the user exactly where they were with a toast, rather than
/// closing their full-screen player and then failing. `DeepLinkRouter` states
/// the same rule for the same reason.
@MainActor
enum NowPlayingMetaRouter {

    /// Serialises taps so a double-click can't push twice.
    private static var inFlight: Task<Void, Never>?

    static func open(_ target: NowPlayingMetaLine.Target, app: AppModel, ui: UIState) {
        switch target {
        case .show(let id, let title):
            raiseMainWindowIfNeeded()
            ui.navigate(to: .album(id: id, title: title.isEmpty ? nil : title))

        case .artist(let name):
            // Usually already warm: any visit to the Artists tab, the Home
            // crate, or a deep link populates the lifetime cache.
            if let entry = app.cachedArtist(named: name) {
                raiseMainWindowIfNeeded()
                ui.navigate(to: .artist(entry))
                return
            }
            let previous = inFlight
            inFlight = Task {
                await previous?.value
                guard let entry = try? await app.artist(named: name) else {
                    ui.showToast("Couldn't find that artist on nugs")
                    return
                }
                raiseMainWindowIfNeeded()
                ui.navigate(to: .artist(entry))
            }
        }
    }

    /// On macOS the Now Playing window is a separate scene sharing this same
    /// `UIState`, so a push navigates the MAIN window — which may be behind it,
    /// or hidden. Raise it rather than closing the player: the user asked to go
    /// somewhere, not to lose their now-playing view.
    ///
    /// No-op when the main window is already key, which is the common case.
    private static func raiseMainWindowIfNeeded() {
        #if os(macOS)
        guard let main = NSApp.windows.first(where: {
            $0.identifier?.rawValue == mainWindowIdentifier
        }) ?? NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible }) else { return }
        guard !main.isKeyWindow else { return }
        NSApp.unhide(nil)
        NSApp.activate()
        main.makeKeyAndOrderFront(nil)
        #endif
    }

    /// Stamped onto the main window by `WindowMinSizeUpdater`, because
    /// `NSApp.mainWindow` is whichever window is key — which is exactly the Now
    /// Playing window in the case we need to handle.
    static let mainWindowIdentifier = "applenugs.main"
}

// MARK: - installing the interceptor

extension View {
    /// Routes taps on now-playing meta links into navigation.
    ///
    /// Installed once per SCENE ROOT — the main window, the iOS shell, and the
    /// macOS Now Playing window, which is a separate scene with its own
    /// environment. Sheets and covers inherit it from their presenter.
    func nowPlayingMetaLinks(app: AppModel, ui: UIState) -> some View {
        environment(\.openURL, OpenURLAction { url in
            guard let target = NowPlayingMetaLine.Target(url: url) else {
                // MUST fall through. VideoDetailView's webcast benefit notes
                // render real markdown links (donation pages) through the same
                // environment; swallowing them here would silently break them.
                return .systemAction
            }
            NowPlayingMetaRouter.open(target, app: app, ui: ui)
            return .handled
        })
    }
}
