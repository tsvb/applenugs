import Foundation

// Pure policies that keep the app's traffic to nugs.net modest (Phase A item 5
// of docs/superpowers/specs/2026-11-06-yeti-compliance-design.md): a token
// bucket for API/resolver requests, playback retry backoff, the artist catalog
// cache and its paging cap. Pure Foundation, compiled into AppleNugsTests —
// every clock is a parameter.

/// A token bucket in reservation form: `reserve` always takes a token, going
/// into debt when the bucket is empty, and returns how long the caller must
/// wait before sending. Taking the token BEFORE the wait means callers that
/// interleave across their sleeps are spaced out instead of all seeing a
/// refilled bucket at once.
struct TokenBucket: Sendable, Equatable {
    let capacity: Double
    let refillPerSecond: Double
    private(set) var tokens: Double
    private var lastRefill: TimeInterval?

    /// Starts full: the first `capacity` requests go out at once.
    init(capacity: Double, refillPerSecond: Double) {
        precondition(capacity >= 1 && refillPerSecond > 0)
        self.capacity = capacity
        self.refillPerSecond = refillPerSecond
        self.tokens = capacity
    }

    /// ≈4 requests a second sustained, bursts of 8.
    static let nugsAPI = TokenBucket(capacity: 8, refillPerSecond: 4)

    /// Takes one token at monotonic time `now` (seconds); returns the delay
    /// in seconds before the request may go out (0 when a token was free).
    mutating func reserve(at now: TimeInterval) -> TimeInterval {
        if let lastRefill {
            let elapsed = max(0, now - lastRefill)
            tokens = min(capacity, tokens + elapsed * refillPerSecond)
        }
        lastRefill = now
        tokens -= 1
        return tokens >= 0 ? 0 : -tokens / refillPerSecond
    }
}

/// How long the player waits before its next try after an AVPlayerItem
/// fails: 0.5s, 1s, 2s, then it gives up. Without it a dead stream walks
/// every tier (and re-resolves) as fast as the round trips allow.
enum PlaybackRetryPolicy {
    static let delays: [TimeInterval] = [0.5, 1, 2]

    /// The wait before retrying after the `failures`-th failure (1-based) of
    /// the same track, or nil once the retries are spent.
    static func delay(afterFailure failures: Int) -> TimeInterval? {
        guard failures >= 1, failures <= delays.count else { return nil }
        return delays[failures - 1]
    }
}

/// A small time-to-live cache. Expired entries read as misses.
struct TTLCache<Key: Hashable, Value> {
    let ttl: TimeInterval
    private var entries: [Key: (value: Value, storedAt: Date)] = [:]

    init(ttl: TimeInterval) { self.ttl = ttl }

    func value(for key: Key, now: Date) -> Value? {
        guard let entry = entries[key], now.timeIntervalSince(entry.storedAt) < ttl else {
            return nil
        }
        return entry.value
    }

    mutating func insert(_ value: Value, for key: Key, now: Date) {
        entries[key] = (value, now)
    }

    mutating func removeAll() { entries = [:] }
}

/// Artist catalog paging (`catalog.containersAll`, 100 a page): the artist
/// page fetches every page up front, but no more than `maxPages`, and a short
/// page means the catalog has ended.
enum ArtistCatalogPaging {
    static let pageSize = 100
    static let maxPages = 30
    /// How long a fully loaded artist catalog is reused before a revisit
    /// fetches it again.
    static let cacheTTL: TimeInterval = 30 * 60

    static func shouldFetchAnother(lastPageCount: Int, pagesFetched: Int,
                                   pageSize: Int = pageSize, maxPages: Int = maxPages) -> Bool {
        lastPageCount >= pageSize && pagesFetched < maxPages
    }
}

/// Pacing for a show download: the gap between one track's stream resolve and
/// the next. Transfers themselves are capped per host by the download session.
enum DownloadPacing {
    static let resolveGap: Duration = .milliseconds(300)
    static let maxConnectionsPerHost = 2
}
