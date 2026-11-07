import XCTest

final class TokenBucketTests: XCTestCase {

    func testTheConfiguredRateIsFourPerSecondBurstEight() {
        XCTAssertEqual(TokenBucket.nugsAPI.capacity, 8)
        XCTAssertEqual(TokenBucket.nugsAPI.refillPerSecond, 4)
    }

    func testABurstOfEightGoesOutAtOnce() {
        var bucket = TokenBucket(capacity: 8, refillPerSecond: 4)
        for _ in 0..<8 { XCTAssertEqual(bucket.reserve(at: 100), 0) }
    }

    /// Past the burst, each further caller queues a quarter second behind
    /// the last — the debt is taken up front, so concurrent callers spread out.
    func testPastTheBurstCallersQueueAtTheSustainedRate() {
        var bucket = TokenBucket(capacity: 8, refillPerSecond: 4)
        for _ in 0..<8 { _ = bucket.reserve(at: 100) }
        XCTAssertEqual(bucket.reserve(at: 100), 0.25, accuracy: 1e-9)
        XCTAssertEqual(bucket.reserve(at: 100), 0.5, accuracy: 1e-9)
        XCTAssertEqual(bucket.reserve(at: 100), 0.75, accuracy: 1e-9)
    }

    func testTokensRefillWithTimeUpToCapacity() {
        var bucket = TokenBucket(capacity: 8, refillPerSecond: 4)
        for _ in 0..<8 { _ = bucket.reserve(at: 100) }
        // 0.5s later two tokens are back.
        XCTAssertEqual(bucket.reserve(at: 100.5), 0)
        XCTAssertEqual(bucket.reserve(at: 100.5), 0)
        XCTAssertEqual(bucket.reserve(at: 100.5), 0.25, accuracy: 1e-9)
        // A long idle refills to the cap, not beyond it.
        for _ in 0..<8 { XCTAssertEqual(bucket.reserve(at: 1_000), 0) }
        XCTAssertGreaterThan(bucket.reserve(at: 1_000), 0)
    }

    func testSustainedFourPerSecondNeverWaits() {
        var bucket = TokenBucket(capacity: 8, refillPerSecond: 4)
        for i in 0..<100 { XCTAssertEqual(bucket.reserve(at: 100 + Double(i) * 0.25), 0) }
    }

    func testDebtIsRepaidByElapsedTime() {
        var bucket = TokenBucket(capacity: 8, refillPerSecond: 4)
        for _ in 0..<12 { _ = bucket.reserve(at: 100) }   // 4 in debt → last waits 1s
        // 1s later the debt is cleared but nothing is banked yet.
        XCTAssertEqual(bucket.reserve(at: 101), 0.25, accuracy: 1e-9)
    }

    func testAClockGoingBackwardsAddsNoTokens() {
        var bucket = TokenBucket(capacity: 1, refillPerSecond: 4)
        XCTAssertEqual(bucket.reserve(at: 100), 0)
        XCTAssertEqual(bucket.reserve(at: 50), 0.25, accuracy: 1e-9)
    }
}

final class PlaybackRetryPolicyTests: XCTestCase {
    func testBackoffDoublesThenGivesUpAfterThree() {
        XCTAssertEqual(PlaybackRetryPolicy.delay(afterFailure: 1), 0.5)
        XCTAssertEqual(PlaybackRetryPolicy.delay(afterFailure: 2), 1)
        XCTAssertEqual(PlaybackRetryPolicy.delay(afterFailure: 3), 2)
        XCTAssertNil(PlaybackRetryPolicy.delay(afterFailure: 4))
        XCTAssertNil(PlaybackRetryPolicy.delay(afterFailure: 0))
    }

    /// Three retries are enough to reach every tier after the first fails.
    func testRetriesCoverEveryRemainingTier() {
        XCTAssertEqual(PlaybackRetryPolicy.delays.count, StreamTierPlan.order.count - 1)
    }
}

final class TTLCacheTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func testHitWithinTTLMissAfter() {
        var cache = TTLCache<String, [Int]>(ttl: 30 * 60)
        cache.insert([1, 2], for: "goose", now: t0)
        XCTAssertEqual(cache.value(for: "goose", now: t0.addingTimeInterval(29 * 60)), [1, 2])
        XCTAssertNil(cache.value(for: "goose", now: t0.addingTimeInterval(30 * 60)))
        XCTAssertNil(cache.value(for: "billy", now: t0))
    }

    func testReinsertRestartsTheClockAndRemoveAllEmpties() {
        var cache = TTLCache<String, Int>(ttl: 60)
        cache.insert(1, for: "a", now: t0)
        cache.insert(2, for: "a", now: t0.addingTimeInterval(50))
        XCTAssertEqual(cache.value(for: "a", now: t0.addingTimeInterval(100)), 2)
        cache.removeAll()
        XCTAssertNil(cache.value(for: "a", now: t0.addingTimeInterval(100)))
    }
}

final class ArtistCatalogPagingTests: XCTestCase {
    func testAFullPageFetchesAnotherAShortPageStops() {
        XCTAssertTrue(ArtistCatalogPaging.shouldFetchAnother(lastPageCount: 100, pagesFetched: 1))
        XCTAssertFalse(ArtistCatalogPaging.shouldFetchAnother(lastPageCount: 99, pagesFetched: 1))
        XCTAssertFalse(ArtistCatalogPaging.shouldFetchAnother(lastPageCount: 0, pagesFetched: 1))
    }

    func testTheFirstPageAlwaysGoesOut() {
        // The view seeds lastPageCount with a full page before the first fetch.
        XCTAssertTrue(ArtistCatalogPaging.shouldFetchAnother(
            lastPageCount: ArtistCatalogPaging.pageSize, pagesFetched: 0))
    }

    func testPagingStopsAtTheCap() {
        XCTAssertEqual(ArtistCatalogPaging.maxPages, 30)
        XCTAssertTrue(ArtistCatalogPaging.shouldFetchAnother(lastPageCount: 100, pagesFetched: 29))
        XCTAssertFalse(ArtistCatalogPaging.shouldFetchAnother(lastPageCount: 100, pagesFetched: 30))
    }

    func testTheCacheLivesThirtyMinutes() {
        XCTAssertEqual(ArtistCatalogPaging.cacheTTL, 30 * 60)
    }
}
