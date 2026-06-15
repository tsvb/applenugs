import Observation
import SwiftUI

/// Navigation targets pushed onto the detail stack.
enum Route: Hashable {
    case artist(ArtistEntry)
    case album(id: String, title: String?)
    case video(id: String, title: String?)
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

    // --- toasts (queue-op confirmations, same as the web layout) ---------------

    private(set) var toast: String?
    private var toastTask: Task<Void, Never>?

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            toast = nil
        }
    }
}
