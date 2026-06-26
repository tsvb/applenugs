import Foundation

/// Thin client for the unofficial nugs.net API — the Swift port of the C#
/// NugsClient. Owns an ephemeral URLSession (no cookies, no shared cache)
/// and the persisted token store. Token refresh happens automatically ~60s
/// before expiry, same as the original.
final class NugsClient {
    private let http: URLSession
    private let store: SessionStore

    /// Resolved stream picks per track. Signed CDN URLs rotate on session
    /// boundaries, so entries expire after the same 4h TTL the web port's
    /// StreamInspector used. Makes prev/next and gapless preloading cheap —
    /// without it every track change re-probes all four platform tiers.
    private var pickCache: [String: (picks: [StreamPick], expiresAt: Date)] = [:]
    private static let pickTTL: TimeInterval = 4 * 60 * 60

    init(store: SessionStore) {
        self.store = store
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        http = URLSession(configuration: config)
    }

    var hasPersistedSession: Bool { store.load() != nil }

    // --- auth ---------------------------------------------------------------

    /// Password grant (ROPC). Works only for accounts that have a nugs.net
    /// password — not for Apple/Google/Facebook/SiriusXM SSO accounts, which
    /// have no password to POST. Those use `loginWithBrowser()` instead.
    func login(email: String, password: String) async throws {
        let form = [
            "client_id": NugsConstants.clientId,
            "grant_type": "password",
            "scope": NugsConstants.oauthScope,
            "username": email,
            "password": password,
        ]
        let (data, status) = try await postForm(NugsConstants.authURL, form: form)
        guard (200..<300).contains(status) else {
            throw NugsError.authFailed(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
        try await completeLogin(with: try JSONDecoder().decode(TokenResponse.self, from: data))
    }

    /// Authorization Code + PKCE grant via a system browser window. Hands
    /// authentication to the real id.nugs.net login page, so SSO/MFA accounts
    /// the password grant can't reach work here. Uses the same public
    /// `clientId`, so the refresh token it yields refreshes through
    /// `currentSession()` unchanged.
    func loginWithBrowser() async throws {
        let (code, verifier) = try await BrowserAuthService.authorize()
        let form = [
            "client_id": NugsConstants.clientId,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": NugsConstants.oauthRedirectURI,
            "code_verifier": verifier,
        ]
        let (data, status) = try await postForm(NugsConstants.authURL, form: form)
        guard (200..<300).contains(status) else {
            throw NugsError.authFailed(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
        try await completeLogin(with: try JSONDecoder().decode(TokenResponse.self, from: data))
    }

    /// Shared tail of both login flows: resolve the user id and subscription,
    /// then persist. The two grants differ only in how the token is obtained.
    private func completeLogin(with token: TokenResponse) async throws {
        let userId = try await fetchUserId(accessToken: token.access_token)
        let sub = try await fetchSubInfo(accessToken: token.access_token)

        try store.save(PersistedSession(
            tokens: TokenSet(
                accessToken: token.access_token,
                refreshToken: token.refresh_token,
                expiresAt: Date().addingTimeInterval(TimeInterval(token.expires_in - 60))),
            userId: userId,
            sub: sub))
    }

    func logout() {
        store.clear()
    }

    /// Returns a session with a fresh access token, refreshing if needed.
    func currentSession() async throws -> Session {
        guard let state = store.load() else { throw NugsError.notLoggedIn }
        if Date() < state.tokens.expiresAt {
            return try Session(state)
        }

        let form = [
            "client_id": NugsConstants.clientId,
            "grant_type": "refresh_token",
            "refresh_token": state.tokens.refreshToken,
        ]
        let (data, status) = try await postForm(NugsConstants.authURL, form: form)
        guard (200..<300).contains(status) else { throw NugsError.http(status) }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)

        var refreshed = state
        refreshed.tokens = TokenSet(
            accessToken: token.access_token,
            refreshToken: token.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(token.expires_in - 60)))
        try store.save(refreshed)
        return try Session(refreshed)
    }

    private func fetchUserId(accessToken: String) async throws -> String {
        let json = try await getJSON(NugsConstants.userInfoURL, bearer: accessToken)
        guard let sub = json["sub"].string else {
            throw NugsError.badResponse("userinfo missing sub")
        }
        return sub
    }

    private func fetchSubInfo(accessToken: String) async throws -> SubInfo {
        var req = URLRequest(url: NugsConstants.subInfoURL)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(NugsConstants.mobileUserAgent, forHTTPHeaderField: "User-Agent")
        let (data, res) = try await http.data(for: req)
        let status = (res as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw NugsError.http(status) }
        return try JSONDecoder().decode(SubInfo.self, from: data)
    }

    // --- catalog ------------------------------------------------------------

    func search(_ query: String) async throws -> JSON {
        try await catalogGet([
            "method": "catalog.search",
            "searchStr": query,
        ])
    }

    func album(id: String) async throws -> JSON {
        try await catalogGet([
            "method": "catalog.container",
            "containerID": id,
            "vdisp": "1",
        ])
    }

    func allArtists() async throws -> JSON {
        try await catalogGet(["method": "catalog.artists"])
    }

    func artistShows(id: String, offset: Int = 1, limit: Int = 100) async throws -> JSON {
        try await catalogGet([
            "method": "catalog.containersAll",
            "artistList": id,
            "startOffset": String(offset),
            "limit": String(limit),
            "availType": "1",
            "vdisp": "1",
        ])
    }

    private func catalogGet(_ query: [String: String]) async throws -> JSON {
        let session = try await currentSession()
        let url = URL(string: "\(NugsConstants.streamAPIBase)/api.aspx?\(Self.encode(query))")!
        return try await getJSON(url, bearer: session.accessToken)
    }

    /// REST GET against the modern video catalog host (`catalogV1Base`). Same
    /// Bearer token and mobile UA as `catalogGet`; differs only in host, path
    /// shape (`/path?k=v`), and that an empty query yields a clean path.
    private func catalogV1Get(_ path: String, query: [String: String] = [:]) async throws -> JSON {
        let session = try await currentSession()
        let p = path.hasPrefix("/") ? path : "/" + path
        var s = "\(NugsConstants.catalogV1Base)\(p)"
        if !query.isEmpty { s += "?\(Self.encode(query))" }
        guard let url = URL(string: s) else { throw NugsError.badResponse("bad catalogV1 URL: \(s)") }
        return try await getJSON(url, bearer: session.accessToken)
    }

    // --- video catalog ------------------------------------------------------

    /// Recently-added VOD (the only artist-independent global video listing).
    func recentVideos(offset: Int = 0, limit: Int = 30) async throws -> [VideoSummary] {
        let json = try await catalogV1Get("/releases/recent", query: [
            "contentType": "video",
            "catalogFilterMode": "any",
            "offset": String(offset),
            "limit": String(limit),
        ])
        return Catalog.recentVideos(from: json)
    }

    /// Live & upcoming webcasts from `<upcomingFrom>` onward.
    func liveWebcasts(upcomingFrom: Date = Date(), limit: Int = 100) async throws -> [VideoSummary] {
        let start = ISO8601DateFormatter().string(from: upcomingFrom)
        let json = try await catalogV1Get("/livestreams", query: [
            "itemTypes": "sel",
            "startDate": start,
            "limit": String(limit),
        ])
        return Catalog.liveWebcasts(from: json)
    }

    /// Per-artist video list (legacy `containersAll` with the video discriminator).
    func artistVideos(id: String, offset: Int = 1, limit: Int = 100) async throws -> [VideoSummary] {
        let json = try await catalogGet([
            "method": "catalog.containersAll",
            "artistList": id,
            "videoReleaseType": "6",
            "startOffset": String(offset),
            "limit": String(limit),
            "availType": "1",
            "vdisp": "1",
        ])
        return Catalog.videoContainers(from: json)
    }

    /// One video container's full detail (legacy `catalog.container&vdisp=1`).
    func videoDetail(containerId: String) async throws -> VideoDetail {
        let json = try await catalogGet([
            "method": "catalog.container",
            "containerID": containerId,
            "vdisp": "1",
        ])
        return Catalog.videoDetail(from: json, id: containerId)
    }

    // --- streaming ----------------------------------------------------------

    /// Resolves the CDN URL for one platformID tier. Returns nil when nugs
    /// has no stream for that combination.
    func streamURL(trackId: String, platformId: Int, session: Session) async throws -> String? {
        let query = [
            "trackID": trackId,
            "platformID": String(platformId),
            "app": "1",
            "subscriptionID": session.subscriptionId,
            "subCostplanIDAccessList": session.planId,
            "nn_userID": session.userId,
            "startDateStamp": String(session.startStamp),
            "endDateStamp": String(session.endStamp),
        ]
        let url = URL(string: "\(NugsConstants.streamAPIBase)/bigriver/subPlayer.aspx?\(Self.encode(query))")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        // Legacy endpoints use a different UA than the JSON catalog ones.
        req.setValue(NugsConstants.legacyUserAgent, forHTTPHeaderField: "User-Agent")
        let (data, res) = try await http.data(for: req)
        guard let code = (res as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else {
            return nil
        }
        return JSON.parse(data).str("streamLink", "StreamLink")
    }

    /// A resolved video stream: a master `.m3u8` URL plus the access flags the
    /// subscription endpoint reports (used by the UI to show a "not in your
    /// plan" state without a second request). The bigriver endpoint returns
    /// these as integers (e.g. 2 / 1), not booleans — Phase 0 confirmed —
    /// so they're surfaced as `Int?` and a positive value means access granted.
    struct VideoStream {
        let url: String
        let subContentAccess: Int?
        let stashContentAccess: Int?
    }

    /// Resolves a video master `.m3u8` via the legacy bigriver path — the same
    /// DRM-free route the Phase 0 probe confirmed plays in a bare AVPlayer.
    /// Subscription VOD / sub livestream → `subPlayer.aspx` (read `streamLink`).
    /// Owned / PPV → `vidPlayer.aspx`; deferred to Phase 7 (returns nil here).
    func resolveVideoStream(containerId: String, sku: Int, isLive: Bool) async throws -> VideoStream? {
        let session = try await currentSession()
        let query = [
            "skuId": String(sku),
            "containerID": containerId,
            "chap": "1",
            "app": "1",
            "subscriptionID": session.subscriptionId,
            "subCostplanIDAccessList": session.planId,
            "nn_userID": session.userId,
            "startDateStamp": String(session.startStamp),
            "endDateStamp": String(session.endStamp),
        ]
        let url = URL(string: "\(NugsConstants.streamAPIBase)/bigriver/subPlayer.aspx?\(Self.encode(query))")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(NugsConstants.legacyUserAgent, forHTTPHeaderField: "User-Agent")
        let (data, res) = try await http.data(for: req)
        let status = (res as? HTTPURLResponse)?.statusCode ?? 0
        // Reserve a `nil` return for the PPV/owned seam (a 2xx with no
        // streamLink). A real HTTP failure (expired token, entitlement, server
        // error) must throw so the caller can distinguish it from "not in your
        // plan" instead of collapsing both into the same nil.
        guard (200..<300).contains(status) else { throw NugsError.http(status) }
        let json = JSON.parse(data)
        guard let link = json.str("streamLink", "StreamLink"), !link.isEmpty else {
            // PPV/owned playback (vidPlayer.aspx, reads "fileURL") is Phase 7.
            return nil
        }
        return VideoStream(
            url: link,
            subContentAccess: json.int("subContentAccess", "SubContentAccess"),
            stashContentAccess: json.int("stashContentAccess", "StashContentAccess"))
    }

    /// Probes every device tier concurrently, identifies the format of each
    /// returned URL, and returns the distinct picks ordered by native playback
    /// preference. The player tries them in order and falls through on
    /// AVPlayer failure, so a bad first choice self-heals.
    func resolveStreams(trackId: String) async throws -> [StreamPick] {
        if let cached = pickCache[trackId], Date() < cached.expiresAt {
            return cached.picks
        }
        let session = try await currentSession()
        var found: [StreamPick] = []
        await withTaskGroup(of: StreamPick?.self) { group in
            for platform in NugsConstants.probePlatforms {
                group.addTask { [self] in
                    guard let url = try? await streamURL(
                            trackId: trackId, platformId: platform, session: session),
                          !url.isEmpty
                    else { return nil }
                    return StreamPick(url: url, platformId: platform, format: .identify(url))
                }
            }
            for await pick in group {
                if let pick { found.append(pick) }
            }
        }

        // Dedup by format (keep the lowest tier that returned it), then order
        // by preference.
        var seen = Set<AudioFormat>()
        var unique: [StreamPick] = []
        for pick in found.sorted(by: { $0.platformId < $1.platformId }) {
            if seen.insert(pick.format).inserted { unique.append(pick) }
        }
        let ordered = unique.sorted { $0.format.preferenceRank < $1.format.preferenceRank }
        if !ordered.isEmpty {
            pickCache[trackId] = (ordered, Date().addingTimeInterval(Self.pickTTL))
        }
        return ordered
    }

    /// Drops a track's cached picks. The player calls this when an item
    /// fails — a stale signed URL is indistinguishable from an undecodable
    /// format, so the next attempt should re-probe from scratch.
    func invalidateStreams(for trackId: String) {
        pickCache[trackId] = nil
    }

    // --- helpers ------------------------------------------------------------

    private func getJSON(_ url: URL, bearer: String) async throws -> JSON {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        req.setValue(NugsConstants.mobileUserAgent, forHTTPHeaderField: "User-Agent")
        let (data, res) = try await http.data(for: req)
        let status = (res as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw NugsError.http(status) }
        return JSON.parse(data)
    }

    private func postForm(_ url: URL, form: [String: String]) async throws -> (Data, Int) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = Self.encode(form).data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(NugsConstants.mobileUserAgent, forHTTPHeaderField: "User-Agent")
        let (data, res) = try await http.data(for: req)
        return (data, (res as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private static func encode(_ pairs: [String: String]) -> String {
        pairs.map { "\(escape($0.key))=\(escape($0.value))" }.joined(separator: "&")
    }

    private static let unreserved = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: "-._~"))

    private static func escape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? s
    }
}

/// Wire format of id.nugs.net/connect/token.
private struct TokenResponse: Decodable {
    let access_token: String
    let refresh_token: String
    let expires_in: Int
}
