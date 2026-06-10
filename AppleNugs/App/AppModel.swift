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
    }

    let client: NugsClient
    let player: PlayerService

    private(set) var sessionState: SessionState = .unknown
    private(set) var isLoggingIn = false
    var loginError: String?

    private var cachedArtists: [ArtistEntry]?

    var isLoggedIn: Bool {
        if case .loggedIn = sessionState { return true }
        return false
    }

    init() {
        let store = SessionStore()
        client = NugsClient(store: store)
        player = PlayerService(client: client)
    }

    /// Resolve the persisted session at launch (refreshing the token if it
    /// has one but it's expired).
    func bootstrap() async {
        guard case .unknown = sessionState else { return }
        guard client.hasPersistedSession else {
            sessionState = .loggedOut
            return
        }
        do {
            let session = try await client.currentSession()
            sessionState = .loggedIn(plan: session.planDescription)
        } catch {
            sessionState = .loggedOut
        }
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

    func logout() {
        client.logout()
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
