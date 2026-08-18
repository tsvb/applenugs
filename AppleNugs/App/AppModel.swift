import Foundation
import Observation

/// Root object graph: the nugs client, the player, the login state, and the
/// in-memory catalog cache (the artist list is expensive to re-fetch on
/// every navigation — port of the web CatalogCache).
@MainActor
@Observable
final class AppModel {
    enum SessionState {
        case unknown        // checking the persisted session at launch
        case loggedOut
        case loggedIn(plan: String?)
        case connectionFailed(String)  // have a session but couldn't reach nugs to validate it
    }

    let client: NugsClient
    let player: PlayerService
    let favorites = FavoritesStore()
    let videoProgress = VideoProgressStore()
    let video: VideoPlayerService
    let downloads: DownloadStore

    private(set) var sessionState: SessionState = .unknown
    private(set) var isLoggingIn = false
    var loginError: String?

    /// A deep link received while logged out / still booting — replayed once
    /// logged in (drained by RootView's main layout). Single slot: if two links
    /// arrive before login the most recent wins (newest user intent). See
    /// `receiveDeepLink` / `handleDeepLink` and DeepLinkRouter.
    var pendingDeepLink: DeepLink?

    /// Serializes deep-link handling. handle() has many awaits (catalog fetches),
    /// each releasing the MainActor; without serialization two links — or a link
    /// racing the post-login drain — could interleave their navigate+play steps
    /// and leave the nav stack and the player queue showing different shows.
    private var deepLinkTask: Task<Void, Never>?

    private var cachedArtists: [ArtistEntry]?

    var isLoggedIn: Bool {
        if case .loggedIn = sessionState { return true }
        return false
    }

    init() {
        client = NugsClient()
        player = PlayerService(client: client)
        video = VideoPlayerService(audio: player, client: client,
                                   progress: videoProgress)
        downloads = DownloadStore(client: client)
        // Local files take precedence over network stream resolution.
        player.downloads = downloads
    }

    /// Resolve the persisted session at launch (refreshing the token if it
    /// has one but it's expired).
    func bootstrap() async {
        guard case .unknown = sessionState else { return }
        #if DEBUG
        if AppModel.isUITestRun {
            loadUITestHarness()
            return
        }
        #endif
        guard await client.hasPersistedSession else {
            sessionState = .loggedOut
            return
        }
        do {
            let session = try await client.currentSession()
            sessionState = .loggedIn(plan: session.planDescription)
        } catch NugsError.http(let status) where (400..<500).contains(status) {
            // The stored refresh token was rejected (revoked/expired) — really
            // log out so the user re-authenticates.
            await client.logout()
            sessionState = .loggedOut
        } catch {
            // Offline / server / transient error: keep the session and let the
            // user retry rather than silently dumping them to a login screen.
            sessionState = .connectionFailed(error.localizedDescription)
        }
    }

    #if DEBUG
    /// True only when the app is launched by an XCUITest passing `-UITEST`.
    /// `ProcessInfo.arguments` never contains this in a normal or release
    /// launch, so every production code path is byte-identical; the whole hook
    /// is also compiled out of release builds by the surrounding `#if DEBUG`.
    static let isUITestRun = ProcessInfo.processInfo.arguments.contains("-UITEST")

    /// Land directly in `.loggedIn` with a deterministic stub catalog and NO
    /// network or Keychain access, so the main layout (the sidebar) renders for
    /// UI layout tests that cannot perform a real OAuth login.
    private func loadUITestHarness() {
        cachedArtists = [
            ArtistEntry(id: "1", name: "Billy Strings"),
            ArtistEntry(id: "2", name: "Goose"),
            ArtistEntry(id: "3", name: "Umphrey's McGee"),
        ]
        sessionState = .loggedIn(plan: "UITest")
        // Opt-in stub queue (separate flag so existing tests see no transport
        // content change): parks tracks without network or playback, making
        // the transport bar render for layout tests/screenshots.
        if ProcessInfo.processInfo.arguments.contains("-UITestSeedQueue") {
            player.seedUITestQueue([
                QueueTrack(trackId: "t1", title: "Away From the Mire",
                           artist: "Billy Strings", show: "2024-03-14 Capitol Theatre, Port Chester, NY",
                           artworkPath: nil, showId: "s1"),
                QueueTrack(trackId: "t2", title: "Dust in a Baggie",
                           artist: "Billy Strings", show: "2024-03-14 Capitol Theatre, Port Chester, NY",
                           artworkPath: nil, showId: "s1"),
            ])
        }
    }
    #endif

    /// Re-attempt the launch session resolution after a connection failure.
    func retryBootstrap() async {
        sessionState = .unknown
        await bootstrap()
    }

    func login(email: String, password: String) async {
        isLoggingIn = true
        loginError = nil
        defer { isLoggingIn = false }
        do {
            try await client.login(email: email, password: password)
            let session = try await client.currentSession()
            sessionState = .loggedIn(plan: session.planDescription)
        } catch {
            loginError = error.localizedDescription
        }
    }

    /// Browser-based OAuth login for SSO/MFA accounts. Mirrors `login` but
    /// drives the system browser; a user-cancelled sheet is not surfaced as an
    /// error.
    func loginWithBrowser() async {
        isLoggingIn = true
        loginError = nil
        defer { isLoggingIn = false }
        do {
            try await client.loginWithBrowser()
            let session = try await client.currentSession()
            sessionState = .loggedIn(plan: session.planDescription)
        } catch NugsError.loginCancelled {
            // user dismissed the browser sheet — nothing to report
        } catch {
            loginError = error.localizedDescription
        }
    }

    func logout() {
        Task { await client.logout() }
        video.stop()
        player.clear()
        cachedArtists = nil
        sessionState = .loggedOut
    }

    /// Full artist list, cached for the app lifetime (cleared on logout).
    /// Parsing happens on the client actor — hundreds of entries plus a
    /// locale-aware sort have no business on the main actor.
    func artists() async throws -> [ArtistEntry] {
        if let cachedArtists { return cachedArtists }
        let parsed = try await client.allArtistsParsed()
        cachedArtists = parsed
        return parsed
    }

    /// Resolve a display name to the catalog's own entry.
    ///
    /// The player only ever knows an artist's NAME — `QueueTrack` carries no
    /// artist id, and neither does the album feed it is built from — so every
    /// "go to this artist" path (deep links, the now-playing meta line) has to
    /// come through here.
    ///
    /// Both sides are trimmed: catalog names occasionally carry stray
    /// whitespace (see `ArtistListView`, which trims for the same reason), and
    /// an untrimmed comparison silently fails to match those artists at all.
    func artist(named name: String) async throws -> ArtistEntry? {
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return nil }
        return try await artists().first { matches($0, target) }
    }

    /// Synchronous fast path: the answer when the catalog is already cached,
    /// `nil` when it isn't. Only ever used to SKIP the await — never to decide
    /// whether to offer an affordance, which would make the same name clickable
    /// on one launch and not the next.
    func cachedArtist(named name: String) -> ArtistEntry? {
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, let cachedArtists else { return nil }
        return cachedArtists.first { matches($0, target) }
    }

    private func matches(_ entry: ArtistEntry, _ trimmedName: String) -> Bool {
        entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(trimmedName) == .orderedSame
    }

    // MARK: - deep links

    /// Entry point from `.onOpenURL`: act now if logged in, else stash for the
    /// post-login drain (RootView's main layout).
    func receiveDeepLink(_ link: DeepLink, ui: UIState) {
        guard isLoggedIn else { pendingDeepLink = link; return }
        handleDeepLink(link, ui: ui)
    }

    /// Run the router for one link, chained after any in-flight link so the
    /// previous link's navigation + playback finish before the next begins.
    /// Re-checks login at the last moment (a logout can land between receipt and
    /// execution) and re-stashes rather than running against a logged-out client.
    func handleDeepLink(_ link: DeepLink, ui: UIState) {
        let previous = deepLinkTask
        deepLinkTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            guard self.isLoggedIn else { self.pendingDeepLink = link; return }
            await DeepLinkRouter.handle(link, app: self, ui: ui)
        }
    }
}
