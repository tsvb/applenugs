import Foundation

/// Thin client for the unofficial nugs.net API. An `actor`: it owns the
/// persisted token store and the stream-pick cache, both of which are mutated
/// from concurrent tasks (the foreground resolve and the gapless preload), so
/// isolating them here removes the data race and serializes token refresh.
/// Tokens refresh automatically ~60s before expiry.
actor NugsClient {
    /// `URLSession` is `Sendable` and immutable here, so it stays non-isolated
    /// for the DEBUG probe's `probeCDN`, which runs off the actor.
    private nonisolated let http: URLSession
    private let store = SessionStore()

    /// Every tier answer per track (`StreamTierPlan.Outcome`, failures
    /// excluded), each with its own expiry. Signed CDN URLs rotate on session
    /// boundaries, so entries expire after 4h. Makes prev/next and gapless
    /// preloading cheap — a cached track needs no resolve at all, and a tier
    /// known to have no stream isn't asked again.
    private var pickCache: [String: [Int: (outcome: StreamTierPlan.Outcome, expiresAt: Date)]] = [:]
    private static let pickTTL: TimeInterval = 4 * 60 * 60

    /// One walk per (track, purpose, skipped tiers) at a time: the foreground
    /// load and the gapless preload asking for the same track share it rather
    /// than both requesting tier 7.
    private var resolving: [String: Task<[StreamPick], Error>] = [:]

    /// Paces every nugs API and stream-resolver request (≈4/s, bursts of 8).
    /// CDN media fetches and artwork are not counted — they never come here.
    private var bucket = TokenBucket.nugsAPI

    /// A single in-flight token refresh shared by all callers, so concurrent
    /// expired-token requests await one refresh instead of stampeding the token
    /// endpoint and racing to overwrite session.json.
    private var refreshTask: Task<Session, Error>?

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        // Default is 60s/7d; tighten so a hung catalog/auth request — or a
        // stalled stream-tier resolve — fails in 30s instead of leaving the
        // user on a frozen load.
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        http = URLSession(configuration: config)
    }

    var hasPersistedSession: Bool { store.load() != nil }

    // --- auth ---------------------------------------------------------------

    /// Authorization Code + PKCE grant via a system browser window — the only
    /// way to sign in. Credentials are typed into nugs.net's own id.nugs.net
    /// page, never into this app, and SSO/MFA accounts work the same as
    /// password ones. The refresh token it yields refreshes through
    /// `currentSession()`; sessions created by the old in-app password grant
    /// (same `clientId`) keep refreshing there unchanged.
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

    /// Tail of the sign-in: resolve the user id and subscription, then persist.
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
        // The sign-in's own subscription answer is fresh.
        if SubscriptionRecheck.decide(sub.isContentAccessible ? .active : .inactive,
                                      currentlyAccessible: sub.isContentAccessible).stamp {
            OfflineVerification.record(Date())
        }
    }

    func logout() {
        store.clear()
    }

    /// Returns a session with a fresh access token, refreshing if needed.
    /// Concurrent callers whose token is expired share one refresh via
    /// `refreshTask` rather than each POSTing their own.
    func currentSession() async throws -> Session {
        guard let state = store.load() else { throw NugsError.notLoggedIn }
        if Date() < state.tokens.expiresAt {
            return try Session(state)
        }
        if let refreshTask {
            return try await refreshTask.value
        }
        let task = Task<Session, Error> { [self] in try await performRefresh(from: state) }
        refreshTask = task
        do {
            let session = try await task.value
            refreshTask = nil
            return session
        } catch {
            refreshTask = nil
            throw error
        }
    }

    private func performRefresh(from state: PersistedSession) async throws -> Session {
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
        // Persist the rotated refresh token before anything else can fail.
        try store.save(refreshed)
        return try Session(await recheckSubscription(refreshed))
    }

    /// Ask the subscriptions endpoint again (one extra request per access-
    /// token refresh — no timer of its own) and apply the answer per
    /// `SubscriptionRecheck`: active renews the offline-play stamp, inactive
    /// marks the session inaccessible, and a failed request changes nothing
    /// (and never fails the refresh). Only `isContentAccessible` is taken
    /// from the answer; the plan and dates the stream resolver sends stay as
    /// sign-in recorded them.
    private func recheckSubscription(_ state: PersistedSession) async -> PersistedSession {
        let outcome: SubscriptionRecheck.Outcome
        if let sub = try? await fetchSubInfo(accessToken: state.tokens.accessToken) {
            outcome = sub.isContentAccessible ? .active : .inactive
        } else {
            outcome = .failed
        }
        let decision = SubscriptionRecheck.decide(
            outcome, currentlyAccessible: state.sub.isContentAccessible)
        var updated = state
        if decision.isContentAccessible != state.sub.isContentAccessible {
            updated.sub.isContentAccessible = decision.isContentAccessible
            // Best-effort like the rest of the store; the tokens are saved.
            try? store.save(updated)
        }
        if decision.stamp { OfflineVerification.record(Date()) }
        return updated
    }

    private func fetchUserId(accessToken: String) async throws -> String {
        let json = try await getJSON(NugsConstants.userInfoURL, bearer: accessToken)
        guard let sub = json["sub"].string else {
            throw NugsError.badResponse("userinfo missing sub")
        }
        return sub
    }

    private func fetchSubInfo(accessToken: String) async throws -> SubInfo {
        let req = Self.subInfoRequest(accessToken: accessToken, identity: .current)
        try await throttle()
        let (data, res) = try await http.data(for: req)
        let status = (res as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw NugsError.http(status) }
        return try JSONDecoder().decode(SubInfo.self, from: data)
    }

    /// The subscriptions request. Shared with the DEBUG network probe so it
    /// tests exactly the request production sends, with only the identity varied.
    static func subInfoRequest(accessToken: String, identity: NugsIdentity) -> URLRequest {
        var req = URLRequest(url: NugsConstants.subInfoURL)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(identity.userAgentAPI, forHTTPHeaderField: "User-Agent")
        return req
    }

    // --- catalog ------------------------------------------------------------

    func search(_ query: String) async throws -> JSON {
        try await catalogGet([
            "method": "catalog.search",
            "searchStr": query,
        ])
    }

    func album(id: String) async throws -> JSON {
        try await catalogGet(Self.albumQuery(id: id))
    }

    /// `catalog.container` for one show. Shared with the DEBUG network probe.
    static func albumQuery(id: String) -> [String: String] {
        [
            "method": "catalog.container",
            "containerID": id,
            "vdisp": "1",
        ]
    }

    func allArtists() async throws -> JSON {
        try await catalogGet(["method": "catalog.artists"])
    }

    /// Fetch + parse on this actor's executor — the catalog runs to hundreds
    /// of entries and the parse has no business on the main actor.
    func allArtistsParsed() async throws -> [ArtistEntry] {
        Catalog.artists(from: try await allArtists())
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
        return try await getJSON(Self.catalogURL(query), bearer: session.accessToken)
    }

    /// The legacy streamapi catalog endpoint (`api.aspx`) for a query. Shared
    /// with the DEBUG network probe.
    static func catalogURL(_ query: [String: String]) -> URL {
        URL(string: "\(NugsConstants.streamAPIBase)/api.aspx?\(Self.encode(query))")!
    }

    /// REST GET against the modern video catalog host (`catalogV1Base`). Same
    /// Bearer token and UA as `catalogGet`; differs only in host, path
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

    /// Live & upcoming webcasts from `<upcomingFrom>` onward. `itemTypes`
    /// defaults to unfiltered (all categories: exclusive/free/ppv, audio+video);
    /// pass "sel" for the old subscription-exclusive-only view.
    func liveWebcasts(upcomingFrom: Date = Date(), itemTypes: String = "",
                      limit: Int = 100) async throws -> [VideoSummary] {
        let start = ISO8601DateFormatter().string(from: upcomingFrom)
        let json = try await catalogV1Get("/livestreams", query: [
            "itemTypes": itemTypes,
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

    /// Asks the resolver for one platformID tier. Never throws: a transport
    /// error or non-2xx is `.failed` (not cached, may be transient), a 2xx
    /// without a link is `.noStream`.
    private func requestTier(trackId: String, platformId: Int,
                             session: Session) async -> StreamTierPlan.Outcome {
        let req = Self.streamRequest(trackId: trackId, platformId: platformId,
                                     session: session, identity: .current)
        do {
            try await throttle()
            let (data, res) = try await http.data(for: req)
            guard let code = (res as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else {
                return .failed
            }
            return StreamTierPlan.outcome(link: JSON.parse(data).str("streamLink", "StreamLink"),
                                          platformId: platformId)
        } catch {
            return .failed
        }
    }

    /// One tier's `subPlayer.aspx` request. Shared with the DEBUG network
    /// probe, which needs the status and body that `streamURL` swallows.
    static func streamRequest(trackId: String, platformId: Int,
                                          session: Session, identity: NugsIdentity) -> URLRequest {
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
        req.setValue(identity.userAgentLegacy, forHTTPHeaderField: "User-Agent")
        return req
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
        req.setValue(NugsIdentity.current.userAgentLegacy, forHTTPHeaderField: "User-Agent")
        try await throttle()
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

    /// Resolves a track's stream one tier at a time (`StreamTierPlan`): tier 7
    /// first, and only when it has nothing usable for `purpose` the remaining
    /// tiers in order, stopping at the first usable one. Typically ONE request
    /// per track, and none when the answer is cached. Returns one pick, or —
    /// when no tier had a usable one — whatever the walk found, best first
    /// (possibly empty). `skipping` excludes tiers the player has watched fail.
    func resolveStreams(trackId: String,
                        purpose: StreamTierPlan.Purpose = .playback,
                        skipping: Set<Int> = []) async throws -> [StreamPick] {
        let key = "\(trackId)|\(purpose)|\(skipping.sorted())"
        if let inFlight = resolving[key] { return try await inFlight.value }
        let task = Task { try await self.walkTiers(trackId: trackId, purpose: purpose,
                                                   skipping: skipping) }
        resolving[key] = task
        defer { resolving[key] = nil }
        return try await task.value
    }

    private func walkTiers(trackId: String, purpose: StreamTierPlan.Purpose,
                           skipping: Set<Int>) async throws -> [StreamPick] {
        let now = Date()
        var known: [Int: StreamTierPlan.Outcome] = [:]
        for (tier, entry) in pickCache[trackId] ?? [:] where now < entry.expiresAt {
            known[tier] = entry.outcome
        }
        var session: Session?
        while true {
            switch StreamTierPlan.next(known: known, skipping: skipping, purpose: purpose) {
            case .done(let picks):
                return picks
            case .request(let tier):
                // Only fetched once a request is actually needed: a fully cached
                // track costs no token refresh either.
                let s: Session
                if let session { s = session } else { s = try await currentSession(); session = s }
                let outcome = await requestTier(trackId: trackId, platformId: tier, session: s)
                known[tier] = outcome
                if outcome.isCacheable {
                    pickCache[trackId, default: [:]][tier] =
                        (outcome, Date().addingTimeInterval(Self.pickTTL))
                }
            }
        }
    }

    /// Drops a track's cached tier answers. The player calls this when an item
    /// fails — a stale signed URL is indistinguishable from an undecodable
    /// format, so the next attempt resolves afresh.
    func invalidateStreams(for trackId: String) {
        pickCache[trackId] = nil
    }

    /// Waits for a token from `bucket`. The token is taken before the wait,
    /// so concurrent callers queue behind each other rather than racing for
    /// the refill. Throws only `CancellationError`.
    private func throttle() async throws {
        let wait = bucket.reserve(at: ProcessInfo.processInfo.systemUptime)
        if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
    }

    // --- helpers ------------------------------------------------------------

    private func getJSON(_ url: URL, bearer: String) async throws -> JSON {
        let req = Self.apiRequest(url, bearer: bearer, identity: .current)
        try await throttle()
        let (data, res) = try await http.data(for: req)
        let status = (res as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw NugsError.http(status) }
        return JSON.parse(data)
    }

    /// An authenticated GET against a JSON host (catalog, catalogV1, userinfo).
    /// Shared with the DEBUG network probe.
    static func apiRequest(_ url: URL, bearer: String, identity: NugsIdentity) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        req.setValue(identity.userAgentAPI, forHTTPHeaderField: "User-Agent")
        return req
    }

    private func postForm(_ url: URL, form: [String: String]) async throws -> (Data, Int) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = Self.encode(form).data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(NugsIdentity.current.userAgentAPI, forHTTPHeaderField: "User-Agent")
        try await throttle()
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

#if DEBUG
// --- network probe (DEBUG only) ----------------------------------------------

/// Single requests for the Network Probe screen (see NetworkProbe.swift). Each
/// performs exactly ONE request with an explicit identity and reports what came
/// back — status, body shape, headers — instead of the production paths'
/// swallow-and-fall-through. They build their requests with the same builders
/// production uses (`subInfoRequest`, `apiRequest` + `catalogURL` + `albumQuery`,
/// `streamRequest`, `NugsIdentity.applyCDN`),
/// so only the identity differs. None of them read or write `pickCache`.
///
/// Session problems (not logged in, a refresh the server rejects) THROW, so the
/// caller can stop the run; anything after the session is in hand comes back
/// as a result row.
extension NugsClient {
    func probeSubscriptions(step: ProbeStep, identity: NugsIdentity) async throws -> ProbeResult {
        let session = try await currentSession()
        let req = Self.subInfoRequest(accessToken: session.accessToken, identity: identity)
        do {
            let (data, res) = try await http.data(for: req)
            return ProbeParse.api(step: step, status: (res as? HTTPURLResponse)?.statusCode ?? 0,
                                  body: data)
        } catch {
            return ProbeParse.failure(step: step, error: error.localizedDescription)
        }
    }

    /// `catalog.container` for the current track's show — the same request
    /// `album(id:)` sends from every show page, on the busy browse host.
    func probeCatalog(step: ProbeStep, showId: String, trackId: String,
                      identity: NugsIdentity) async throws -> ProbeResult {
        let session = try await currentSession()
        let req = Self.apiRequest(Self.catalogURL(Self.albumQuery(id: showId)),
                                  bearer: session.accessToken, identity: identity)
        do {
            let (data, res) = try await http.data(for: req)
            return ProbeParse.catalog(step: step, status: (res as? HTTPURLResponse)?.statusCode ?? 0,
                                      body: data, showId: showId, trackId: trackId)
        } catch {
            return ProbeParse.failure(step: step, error: error.localizedDescription)
        }
    }

    func probeResolve(step: ProbeStep, trackId: String, platformId: Int,
                      identity: NugsIdentity) async throws -> ProbeResult {
        let session = try await currentSession()
        let req = Self.streamRequest(trackId: trackId, platformId: platformId,
                                     session: session, identity: identity)
        do {
            let (data, res) = try await http.data(for: req)
            return ProbeParse.resolve(step: step, status: (res as? HTTPURLResponse)?.statusCode ?? 0,
                                      body: data)
        } catch {
            return ProbeParse.failure(step: step, error: error.localizedDescription)
        }
    }

    /// A ranged GET (`bytes=0-1023`) cancelled the moment headers arrive — not
    /// HEAD, which a CDN may refuse outright, and not `data(for:)`, which would
    /// pull a whole FLAC if the Range were ignored.
    nonisolated func probeCDN(step: ProbeStep, url: String, identity: NugsIdentity) async -> ProbeResult {
        guard let target = URL(string: url) else {
            return ProbeParse.failure(step: step, error: "Unparseable stream URL")
        }
        var req = URLRequest(url: target)
        identity.applyCDN(to: &req)
        req.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
        do {
            let (bytes, res) = try await http.bytes(for: req)
            bytes.task.cancel()
            guard let res = res as? HTTPURLResponse else {
                return ProbeParse.failure(step: step, error: "Not an HTTP response")
            }
            return ProbeParse.cdn(step: step, status: res.statusCode,
                                  contentType: res.value(forHTTPHeaderField: "Content-Type"),
                                  contentLength: res.value(forHTTPHeaderField: "Content-Length"),
                                  contentRange: res.value(forHTTPHeaderField: "Content-Range"))
        } catch {
            return ProbeParse.failure(step: step, error: error.localizedDescription)
        }
    }
}
#endif
