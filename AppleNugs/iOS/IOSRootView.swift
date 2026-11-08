import SwiftUI
import UIKit

/// The iPhone shell: a tab per Mac sidebar section, each with its own
/// NavigationStack over the shared UIState routing, and the now-playing pill
/// hosted in the TabView's bottom accessory.
///
/// The pill lives in the accessory rather than in a per-tab `safeAreaInset`
/// because the accessory belongs to the TabView: it rides above pushed detail
/// screens for free. The old inset decorated each stack's *root* view, so the
/// bar vanished the moment anything was pushed.
struct IOSRootView: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var ui
    @Environment(\.theme) private var theme

    // Starts presented under -UITestShowNowPlaying so layout screenshots can
    // reach the full-screen player without a tap (simctl cannot tap).
    @State private var nowPlayingPresented =
        ProcessInfo.processInfo.arguments.contains("-UITestShowNowPlaying")
    /// Offline library sheet reachable from the connection-failed screen.
    @State private var offlineShown = false
    /// The pill's expanded panel. Owned here, not by the pill — see the sheet.
    @State private var panelShown = false
    #if DEBUG
    /// The DEBUG Network Probe sheet (account menu). Starts presented under
    /// -UITestShowNetworkProbe so it can be screenshotted without a tap.
    @State private var probeShown =
        ProcessInfo.processInfo.arguments.contains("-UITestShowNetworkProbe")
    #endif
    /// Guards the listening-stats reset. There is no event log behind those
    /// tallies, so the wipe is unrecoverable — it does not happen on one tap.
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
        .themed(theme)
        // One scene, so one install point; the cover, the panel and the
        // dashboard sheet nested inside them all inherit it.
        .nowPlayingMetaLinks(app: app, ui: ui)
        .task { await app.bootstrap() }
        // Deep links (applenugs://show/…). Parse here; AppModel acts now if the
        // session is up, or stashes for the drain below. The now-playing cover
        // still has to come down before the push lands — a video's playback only
        // starts once VideoDetailView is on screen, so behind an opaque cover it
        // would play blind — but that is no longer done by hand here: the router
        // navigates through UIState.navigate(to:), and every presentation owner
        // observes it via dismissesOnNavigation. None of the Mac's NSApp
        // plumbing: iOS foregrounds us on open, and there is one scene.
        .onOpenURL { url in
            guard let link = DeepLink.parse(url) else { return }
            app.receiveDeepLink(link, ui: ui)
        }
        // Replay a link that arrived before login/bootstrap finished — which is
        // every cold-launch link, since bootstrap awaits the session before
        // flipping isLoggedIn. The iOS analog of RootView's drain: same
        // serialized channel, nil'd first so a duplicate fire can't double-open.
        .task(id: app.isLoggedIn) {
            if app.isLoggedIn, let link = app.pendingDeepLink {
                app.pendingDeepLink = nil
                app.handleDeepLink(link, ui: ui)
            }
        }
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
                            // Sheets cannot host a tab accessory, so this is the
                            // one legitimate place the pill is mounted by hand.
                            // `tabViewBottomAccessoryPlacement` is nil here and
                            // PillLayout treats nil as .expanded. There is no
                            // full-screen player or panel to open from a
                            // connection-failed sheet, so both are no-ops/nil.
                            NowPlayingPill(onTap: { }, onExpand: nil)
                                .frame(height: 48)
                                .background(.thinMaterial, in: Capsule())
                                .padding(.horizontal, 12)
                                .padding(.bottom, 8)
                        }
                    }
            }
            .presentationBackground(theme.palette.base)
        }
    }

    private var mainLayout: some View {
        @Bindable var ui = ui
        // One tab per Mac sidebar section. All tabs share the single
        // UIState.navPath (only the visible tab's stack is live, and UIState
        // resets the path whenever the section changes, so a background
        // tab can never hold stale path entries).
        return TabView(selection: $ui.sidebarSelection) {
            Tab("Home", systemImage: "house",
                value: UIState.SidebarItem?.some(.home)) {
                tabStack { HomeView() }
            }
            Tab("Artists", systemImage: "music.mic",
                value: UIState.SidebarItem?.some(.artists)) {
                tabStack { ArtistListView() }
            }
            Tab("Search", systemImage: "magnifyingglass",
                value: UIState.SidebarItem?.some(.search)) {
                tabStack { SearchView() }
            }
            Tab("Library", systemImage: "star",
                value: UIState.SidebarItem?.some(.favorites)) {
                tabStack { LibraryView() }
            }
            Tab("Videos", systemImage: "play.rectangle",
                value: UIState.SidebarItem?.some(.videos)) {
                tabStack { VideosView() }
            }
        }
        // The accessory belongs to the TabView, so it rides above every screen
        // — including pushed detail views — instead of decorating each stack's
        // root the way the old safeAreaInset did.
        .modifier(NowPlayingAccessory(
            app: app,
            onTap: { nowPlayingPresented = true },
            onExpand: { panelShown = true }))
        // The Home hero (Yeti) opens the same cover the pill's tap does —
        // one presentation, one owner.
        .environment(\.openNowPlaying, OpenNowPlayingAction { [presented = $nowPlayingPresented] in
            presented.wrappedValue = true
        })
        .dismissesOnNavigation($nowPlayingPresented, ui: ui)
        .fullScreenCover(isPresented: $nowPlayingPresented) {
            // On iPhone Duo's inner display the player sits beside its queue;
            // everywhere else this is the bare NowPlayingScreen.
            // Clear so the app shows through while the player is swiped down;
            // at rest the arrangement paints its own opaque backgrounds.
            NowPlayingArrangement()
                .presentationBackground(.clear)
        }
        // Presented here rather than from inside the pill: a sheet attached
        // within `tabViewBottomAccessory` runs its content's body but never
        // appears, because the accessory is a system-hosted container rather
        // than a normal presentation context.
        .dismissesOnNavigation($panelShown, ui: ui)
        .sheet(isPresented: $panelShown) {
            ExpandedPlayerPanel()
                .presentationDetents([.height(250)])
                .presentationCornerRadius(26)
                .presentationBackground(.thinMaterial)
                .presentationDragIndicator(.visible)
        }
        #if DEBUG
        .sheet(isPresented: $probeShown) { NetworkProbeView() }
        #endif
        .background(KeyCommandsHost(app: app, ui: ui))
        // A text field in the tab you just left keeps first responder across a
        // tab switch (switching tabs doesn't end its editing), which would
        // swallow the hardware-keyboard shortcuts — keys keep flowing into the
        // hidden field. Resign it on leave so KeyCommandsHost reclaims focus.
        // Skip when arriving at Search: the "/" shortcut switches here and then
        // focuses the field, and resigning would fight that.
        .onChange(of: ui.sidebarSelection) { _, newValue in
            if newValue != .search {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
    }

    /// One tab's stack: its own NavigationStack over the shared navPath, the
    /// shared Route destinations (so in-content pushes via UIState.open(_:)
    /// work exactly as in the Mac shell's detail column), and the account menu.
    @ViewBuilder
    private func tabStack<Content: View>(
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        @Bindable var ui = ui
        // The toast overlay is attached to the NavigationStack itself, not
        // to `content()` (the stack's root view): the root is covered the
        // moment a destination is pushed, and its overlay along with it, so
        // a toast fired from a pushed screen — AlbumDetailView's "Playing
        // next" / "Added to queue" — would silently vanish. One level out,
        // the overlay stays visible across every push in this stack.
        NavigationStack(path: $ui.navPath) {
            content()
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
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { accountMenu }
                }
                // System API, not custom chrome: the default (`.automatic`)
                // drew no bottom edge effect under the accessory where the tab
                // bar is vertical (iPhone Duo, folded), so content ran crisp
                // through and below the pill. `.soft` is what horizontal-bar
                // iPhones already get; they render unchanged.
                .scrollEdgeEffectStyle(.soft, for: .bottom)
        }
        .overlay(alignment: .bottom) { toastOverlay }
    }

    private var accountMenu: some View {
        Menu {
            if case .loggedIn(let plan) = app.sessionState, let plan {
                Text(plan)
            }
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
            // iOS has no About panel, so the disclaimer the Mac carries in
            // Credits.rtf lives here: non-interactive rows, like the plan above.
            // Two short lines rather than one long one — menu rows truncate.
            Divider()
            Text(Self.aboutLine)
            Text("Unofficial. Not affiliated with nugs.net or Apple.")
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

    /// "Yeti 1.5 (6)", from the bundle so it can't drift from project.yml.
    private static var aboutLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Yeti \(version) (\(build))"
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = ui.toast {
            ToastCapsule(text: toast.text, kind: toast.kind)
                // This overlay is attached to the NavigationStack itself, one
                // level above `content()` (see `tabStack` above) — but the
                // NavigationStack is still a Tab's content, and it's *being*
                // a Tab's content that gets the accessory pill and the tab
                // bar excluded from the safe area, not specifically being
                // `content()`. So the exclusion still applies here, and a
                // plain 8pt still clears the pill by construction at any
                // chrome height. Confirmed live at the stack root (a deep
                // link's failure toast, screenshot in the branch's
                // final-review report); a pushed destination sits under the
                // same overlay by construction, so the same safe area and
                // padding apply there too, but that specific case wasn't
                // exercised with a live tap (see the report for why).
                .padding(.bottom, 8)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }
}

/// Hosts `NowPlayingPill` in the `TabView`'s bottom accessory — on every
/// iPhone, including iPhone Duo where the tab bar runs down the side. Tim's
/// call (2026-11-07): follow the system, not a custom overlay. The system's
/// scroll edge effect handles content under the bars, and `PillLayout` sheds
/// controls by measured width for the Duo's narrow (~290pt, still
/// `.expanded`) accessory. Don't fork the mount on `\.toolbarVerticalEdge`
/// again — see CLAUDE.md.
///
/// `tabViewBottomAccessory(isEnabled:content:)` is the overload that hides the
/// accessory entirely when nothing is playing; it is iOS 26.1+, which is why
/// the deployment target is 26.1 rather than 26.0. The content-only overload
/// (26.0) has no way to reclaim the slot, so an idle player would leave a 48pt
/// gap above the tab bar.
private struct NowPlayingAccessory: ViewModifier {
    let app: AppModel
    let onTap: () -> Void
    let onExpand: () -> Void

    func body(content: Content) -> some View {
        content
            .tabViewBottomAccessory(isEnabled: app.player.current != nil) {
                NowPlayingPill(onTap: onTap, onExpand: onExpand)
            }
            .tabBarMinimizeBehavior(.onScrollDown)
    }
}
