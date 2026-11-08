import Observation
import SwiftUI

/// Navigation targets pushed onto the detail stack.
enum Route: Hashable {
    case artist(ArtistEntry)
    case album(id: String, title: String?)
    case video(id: String, title: String?)
    case webcast(WebcastContext)
}

/// Window-level UI state: sidebar selection, navigation stack, the dashboard
/// inspector toggle, the global-search focus relay, and transient toasts.
@MainActor
@Observable
final class UIState {
    enum SidebarItem: Hashable {
        case home
        case artists
        case videos
        case favorites
        case downloads
        case search
    }

    var sidebarSelection: SidebarItem? = .home {
        didSet {
            // Switching sections resets the drill-down stack.
            if sidebarSelection != oldValue { navPath = NavigationPath() }
        }
    }

    var navPath = NavigationPath()
    var inspectorOpen = true

    /// Bumped by the global "/" shortcut; SearchView focuses its field on change.
    private(set) var searchFocusTick = 0

    func requestSearchFocus() {
        sidebarSelection = .search
        searchFocusTick += 1
    }

    func open(_ route: Route) {
        navPath.append(route)
    }

    /// Bumped by `navigate(to:)`. Every modally-presented surface that can
    /// navigate observes it and tears itself down.
    private(set) var dismissPresentationsTick = 0

    /// Navigate from a surface that may be presented modally — the full-screen
    /// player, the expanded panel, the dashboard sheet — rather than from the
    /// navigation stack itself.
    ///
    /// A plain `open(_:)` pushes onto the stack BEHIND the presentation, so the
    /// user watches nothing happen. `@Environment(\.dismiss)` can't fix it
    /// either: on iOS the dashboard is a sheet presented from inside a sheet
    /// AND a sheet presented from inside a fullScreenCover, so a tap there has
    /// to unwind two layers, and dismiss reaches only the innermost.
    ///
    /// Deliberately does NOT touch `sidebarSelection` — its `didSet` resets
    /// `navPath`, which would wipe the push we are about to make. The
    /// destination lands on the current section's stack, same as a deep link.
    func navigate(to route: Route) {
        dismissPresentationsTick &+= 1
        navPath.append(route)
    }

    // --- clear queue (Playback ▸ Clear Queue) ----------------------------------

    /// Set by the macOS Playback menu's Clear Queue. A `Commands` builder has
    /// no view to present a confirmation from, so the menu raises this flag
    /// and the main window's root (`RootView`) hosts the dialog.
    var clearQueueConfirmationRequested = false

    // --- toasts (queue-op confirmations, same as the web layout) ---------------

    /// A transient message. `kind` only changes how Yeti draws it (a check or
    /// a warning mark); every other theme renders both kinds the same.
    struct Toast: Equatable {
        enum Kind: Equatable { case success, failure }
        let text: String
        let kind: Kind
    }

    private(set) var toast: Toast?
    private var toastTask: Task<Void, Never>?

    func showToast(_ text: String, kind: Toast.Kind = .success) {
        toast = Toast(text: text, kind: kind)
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            toast = nil
        }
    }
}

/// Ties a modal presentation flag to `UIState.navigate(to:)`.
///
/// Applied at each flag's OWNER, so nested presentations unwind together —
/// each observer clears its own flag independently, which `@Environment(\.dismiss)`
/// cannot do from two layers in.
extension View {
    func dismissesOnNavigation(_ flag: Binding<Bool>, ui: UIState) -> some View {
        onChange(of: ui.dismissPresentationsTick) { _, _ in
            if flag.wrappedValue { flag.wrappedValue = false }
        }
    }
}
