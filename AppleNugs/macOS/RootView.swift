import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var ui
    @Environment(ThemeManager.self) private var themes
    @Environment(\.theme) private var theme

    @State private var offlineShown = false
    #if DEBUG
    /// The DEBUG Network Probe sheet (account menu). Starts presented under
    /// -UITestShowNetworkProbe so it can be screenshotted without a tap.
    @State private var probeShown =
        ProcessInfo.processInfo.arguments.contains("-UITestShowNetworkProbe")
    #endif

    /// Guards the listening-stats reset. There is no event log behind those
    /// tallies, so the wipe is unrecoverable — it does not happen on one click.
    @State private var confirmingStatsReset = false

    var body: some View {
        Group {
            switch app.sessionState {
            case .unknown:
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loggedOut:
                LoginView()
            case .loggedIn:
                mainLayout
            case .connectionFailed(let message):
                connectionFailedView(message)
            }
        }
        .providesArtColor(app: app, theme: theme)
        .nowPlayingMetaLinks(app: app, ui: ui)
        .task { await app.bootstrap() }
        .onAppear { KeyboardShortcuts.install(app: app, ui: ui) }
    }

    private func connectionFailedView(_ message: String) -> some View {
        let hasDownloads = !app.downloads.manifest.shows.isEmpty
        return ConnectionFailedView(
            message: message,
            hasDownloads: hasDownloads,
            canPlayOffline: hasDownloads && OfflineAccessPolicy.allowsOfflinePlay(
                lastVerifiedAt: OfflineVerification.lastVerifiedAt(), now: Date()),
            onRetry: { Task { await app.retryBootstrap() } },
            onListenOffline: { offlineShown = true },
            onSignOut: { app.logout() })
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $offlineShown) {
            NavigationStack {
                DownloadsView()
                    .navigationTitle("Downloads")
                    .compactNavigationTitle()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { offlineShown = false }
                        }
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if app.player.current != nil {
                            VStack(spacing: 0) {
                                Divider()
                                TransportBar()
                            }
                        }
                    }
            }
            .frame(minWidth: 520, minHeight: 420)
            .presentationBackground(theme.palette.base)
        }
    }

    private var mainLayout: some View {
        @Bindable var ui = ui
        // NavigationSplitView is the top-level content (not nested in a VStack)
        // so its toolbar is hosted at the window level: trailing items anchor to
        // the window's right edge and don't fold into the ⋯ overflow when the
        // sidebar slides in and narrows the detail column. The transport bar is
        // pinned with safeAreaInset — the idiomatic persistent bottom bar.
        return NavigationSplitView {
            List(selection: $ui.sidebarSelection) {
                Text("Home")
                    .tag(UIState.SidebarItem.home)
                    .accessibilityIdentifier("sidebar.item.home")
                Text("Artists")
                    .tag(UIState.SidebarItem.artists)
                    .accessibilityIdentifier("sidebar.item.artists")
                Text("Videos")
                    .tag(UIState.SidebarItem.videos)
                    .accessibilityIdentifier("sidebar.item.videos")
                Text("Favorites")
                    .tag(UIState.SidebarItem.favorites)
                    .accessibilityIdentifier("sidebar.item.favorites")
                Text("Downloads")
                    .tag(UIState.SidebarItem.downloads)
                    .accessibilityIdentifier("sidebar.item.downloads")
                Text("Search")
                    .tag(UIState.SidebarItem.search)
                    .accessibilityIdentifier("sidebar.item.search")
            }
            .accessibilityIdentifier("sidebar.list")
            .scrollContentBackground(.hidden)
            .background(theme.palette.base)
            .navigationSplitViewColumnWidth(min: 150, ideal: 180, max: 240)
        } detail: {
            NavigationStack(path: $ui.navPath) {
                detailRoot
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .artist(let artist):
                            ArtistDetailView(artist: artist)
                        case .album(let id, let title):
                            AlbumDetailView(albumId: id, titleHint: title)
                        case .video(let id, let title):
                            VideoDetailView(videoId: id, titleHint: title)
                        case .webcast(let ctx):
                            VideoDetailView(videoId: ctx.id, titleHint: ctx.title, webcast: ctx)
                        }
                    }
            }
            // The detail column must declare an honest minimum so it participates
            // in the window's enforced minimum: the window floor is the SUM of the
            // visible columns' minimums, so a detail reporting ~0 would let the
            // window squeeze the detail and overflow/clip the sidebar. 480 is the
            // narrowest width the editorial detail content stays usable at.
            .frame(minWidth: 480, idealWidth: 760, maxWidth: .infinity)
        }
        .inspector(isPresented: $ui.inspectorOpen) {
            DashboardPanel()
                // Pinned at 340: measured against real catalog strings, a 44-char
                // venue line ("2024-03-14 Capitol Theatre, Port Chester, NY") fits
                // whole at 340 pt and clips at 300. Type is a fixed point size, so
                // narrowing is the only thing that can squeeze it. The floor costs
                // 90 pt of window minimum while the inspector is open.
                .inspectorColumnWidth(min: 340, ideal: 340, max: 380)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    ui.inspectorOpen.toggle()
                } label: {
                    Label("Dashboard", systemImage: "sidebar.right")
                }
                .help("Toggle the dashboard panel (⌥⌘I)")
            }
            ToolbarItem(placement: .primaryAction) {
                accountMenu
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                TransportBar()
            }
        }
        .overlay(alignment: .bottom) { toastOverlay }
        // WindowMinSizeUpdater keeps NSWindow.minSize in sync with the visible
        // columns. .windowResizability(.contentMinSize) alone does not include
        // the inspector's 250pt minimum, so the window could be dragged narrower
        // than sidebar+detail+inspector, clipping the sidebar off the left edge.
        .background(WindowMinSizeUpdater(inspectorOpen: ui.inspectorOpen))
        #if DEBUG
        .sheet(isPresented: $probeShown) { NetworkProbeView() }
        #endif
        // Replay a deep link that arrived before login/bootstrap finished. This
        // layout only exists once `.loggedIn`, so the task fires exactly when the
        // app is ready. Goes through the serialized channel so it can't interleave
        // with a link that arrives at almost the same moment.
        .task(id: app.isLoggedIn) {
            if app.isLoggedIn, let link = app.pendingDeepLink {
                app.pendingDeepLink = nil
                app.handleDeepLink(link, ui: ui)
            }
        }
    }

    @ViewBuilder
    private var detailRoot: some View {
        switch ui.sidebarSelection {
        case .home:
            HomeView()
        case .videos:
            VideosView()
        case .favorites:
            FavoritesView()
        case .downloads:
            DownloadsView()
        case .search:
            SearchView()
        default:
            ArtistListView()
        }
    }

    private var accountMenu: some View {
        Menu {
            if case .loggedIn(let plan) = app.sessionState, let plan {
                Text(plan)
            }
            Picker("Theme", selection: Binding(
                get: { themes.selected },
                set: { newValue in
                    withAnimation(.easeInOut(duration: 0.35)) { themes.selected = newValue }
                }
            )) {
                ForEach(ThemeID.allCases) { id in
                    Text(id.displayName).tag(id)
                }
            }
            .pickerStyle(.menu)
            #if DEBUG
            Divider()
            Button("Network Probe (Debug)") { probeShown = true }
            #endif
            Divider()
            Button("Reset Listening Stats…", role: .destructive) {
                confirmingStatsReset = true
            }
            Divider()
            Button("Sign Out") { app.logout() }
        } label: {
            Label("Account", systemImage: "person.circle")
        }
        .confirmationDialog("Reset listening stats?",
                            isPresented: $confirmingStatsReset,
                            titleVisibility: .visible) {
            Button("Reset Stats", role: .destructive) { app.listening.reset() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This erases your artist totals permanently. There's no history to restore them from.")
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = ui.toast {
            ToastCapsule(text: toast.text, kind: toast.kind)
                .padding(.bottom, 78)  // float above the transport bar
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Window minimum size

/// Keeps `NSWindow.minSize` in sync with the visible columns so the user
/// cannot drag the window narrower than its content requires — the real fix
/// for the sidebar-clip bug.
///
/// `.windowResizability(.contentMinSize)` alone does not include the
/// Dashboard inspector's 250pt minimum in its calculation, so the window
/// could be dragged to a width where the inspector pushes the detail column
/// (and ultimately the sidebar) off the left edge. This struct reaches into
/// AppKit directly and updates `minSize` whenever the inspector toggles.
private struct WindowMinSizeUpdater: NSViewRepresentable {
    var inspectorOpen: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        // sidebar min (150) + detail min (480) + inspector min (250 when open)
        // + 1pt per visible column divider
        let width: CGFloat = 150 + 480 + (inspectorOpen ? 250 + 1 : 0) + 1
        window.minSize = CGSize(width: width, height: 600)
        // Stamp the main window so NowPlayingMetaRouter can raise it when a
        // meta link is tapped from the separate Now Playing window scene.
        // NSApp.mainWindow is whichever window is key — which is precisely the
        // Now Playing window in the case that needs handling.
        if window.identifier == nil {
            window.identifier = NSUserInterfaceItemIdentifier(
                NowPlayingMetaRouter.mainWindowIdentifier)
        }
    }
}
