import XCTest

final class OfflineAccessPolicyTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    func testNeverVerifiedNeverPlaysOffline() {
        XCTAssertFalse(OfflineAccessPolicy.allowsOfflinePlay(lastVerifiedAt: nil, now: now))
    }

    func testWithinThirtyDaysPlays() {
        for age in [0, 1, 29, 30] {
            XCTAssertTrue(OfflineAccessPolicy.allowsOfflinePlay(
                lastVerifiedAt: now.addingTimeInterval(-Double(age) * day), now: now), "age \(age)d")
        }
    }

    func testPastThirtyDaysDoesNot() {
        XCTAssertFalse(OfflineAccessPolicy.allowsOfflinePlay(
            lastVerifiedAt: now.addingTimeInterval(-30 * day - 1), now: now))
        XCTAssertFalse(OfflineAccessPolicy.allowsOfflinePlay(
            lastVerifiedAt: now.addingTimeInterval(-400 * day), now: now))
    }

    func testAStampFromAMovedClockDoesNotCount() {
        // Small skew is tolerated…
        XCTAssertTrue(OfflineAccessPolicy.allowsOfflinePlay(
            lastVerifiedAt: now.addingTimeInterval(3600), now: now))
        // …a stamp from a clock set years ahead is not a verification.
        XCTAssertFalse(OfflineAccessPolicy.allowsOfflinePlay(
            lastVerifiedAt: now.addingTimeInterval(365 * day), now: now))
    }

    // --- subscription recheck on token refresh ------------------------------------

    func testFreshActiveAnswerStamps() {
        for current in [true, false] {
            XCTAssertEqual(SubscriptionRecheck.decide(.active, currentlyAccessible: current),
                           .init(stamp: true, isContentAccessible: true), "current \(current)")
        }
    }

    func testFreshInactiveAnswerDoesNotStampAndMarksInaccessible() {
        for current in [true, false] {
            XCTAssertEqual(SubscriptionRecheck.decide(.inactive, currentlyAccessible: current),
                           .init(stamp: false, isContentAccessible: false), "current \(current)")
        }
    }

    func testFailedRecheckDoesNotStampAndChangesNothing() {
        // No lockout on a transient failure — and no renewal either.
        XCTAssertEqual(SubscriptionRecheck.decide(.failed, currentlyAccessible: true),
                       .init(stamp: false, isContentAccessible: true))
        XCTAssertEqual(SubscriptionRecheck.decide(.failed, currentlyAccessible: false),
                       .init(stamp: false, isContentAccessible: false))
    }

    func testVerificationStampRoundTripsAndClears() throws {
        let suite = "OfflineAccessPolicyTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertNil(OfflineVerification.lastVerifiedAt(in: defaults))
        OfflineVerification.record(now, in: defaults)
        XCTAssertEqual(OfflineVerification.lastVerifiedAt(in: defaults), now)
        OfflineVerification.clear(in: defaults)
        XCTAssertNil(OfflineVerification.lastVerifiedAt(in: defaults))
    }
}

final class OfflineExpiryDetailTests: XCTestCase {

    func testTheExpiryErrorExplainsItself() {
        XCTAssertEqual(OfflineAccessPolicy.detail(forError: OfflineAccessPolicy.expiredMessage),
                       "Offline play needs nugs.net to confirm your subscription at least once every 30 days.")
    }

    func testOtherErrorsStandAlone() {
        XCTAssertNil(OfflineAccessPolicy.detail(forError: "nugs has no stream for this track."))
        XCTAssertNil(OfflineAccessPolicy.detail(forError: ""))
    }
}
