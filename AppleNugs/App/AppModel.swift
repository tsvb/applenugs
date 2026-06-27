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

    private(set) var sessionState: SessionState = .unknown
    private(set) var isLoggingIn = false
    var loginError: String?

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
    }

    /// Resolve the persisted session at launch (refreshing the token if it
    /// has one but it's expired).
    func bootstrap() async {
        guard case .unknown = sessionState else { return }
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
    func artists() async throws -> [ArtistEntry] {
        if let cachedArtists { return cachedArtists }
        let parsed = Catalog.artists(from: try await client.allArtists())
        cachedArtists = parsed
        return parsed
    }
}
