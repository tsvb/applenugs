import XCTest

final class WebcastPartitionTests: XCTestCase {

    private struct Cast: WebcastLike, Equatable {
        let name: String
        let isLive: Bool
        let eventStart: Date?
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func days(_ d: Double) -> Date { now.addingTimeInterval(d * 86_400) }

    func testFutureEventsAreUpcomingSoonestFirst() {
        let items = [
            Cast(name: "later", isLive: false, eventStart: days(5)),
            Cast(name: "sooner", isLive: false, eventStart: days(1)),
        ]
        let split = partitionWebcasts(items, now: now)
        XCTAssertEqual(split.upcoming.map(\.name), ["sooner", "later"])
        XCTAssertTrue(split.recent.isEmpty)
    }

    func testPastEventsAreRecentNewestFirst() {
        let items = [
            Cast(name: "older", isLive: false, eventStart: days(-10)),
            Cast(name: "newer", isLive: false, eventStart: days(-1)),
        ]
        let split = partitionWebcasts(items, now: now)
        XCTAssertTrue(split.upcoming.isEmpty)
        XCTAssertEqual(split.recent.map(\.name), ["newer", "older"])
    }

    func testCurrentlyLiveStaysUpcomingEvenWithPastStart() {
        let items = [Cast(name: "live-now", isLive: true, eventStart: days(-0.1))]
        let split = partitionWebcasts(items, now: now)
        XCTAssertEqual(split.upcoming.map(\.name), ["live-now"])
        XCTAssertTrue(split.recent.isEmpty)
    }

    func testNilStartDateStaysUpcoming() {
        // Odd feed items without a schedule keep the pre-partition behavior
        // (they were always shown under Live & Upcoming).
        let items = [Cast(name: "undated", isLive: false, eventStart: nil)]
        let split = partitionWebcasts(items, now: now)
        XCTAssertEqual(split.upcoming.map(\.name), ["undated"])
        XCTAssertTrue(split.recent.isEmpty)
    }

    func testLiveItemsSortAheadOfScheduledInUpcoming() {
        let items = [
            Cast(name: "tonight", isLive: false, eventStart: days(0.5)),
            Cast(name: "live-now", isLive: true, eventStart: days(-0.1)),
        ]
        let split = partitionWebcasts(items, now: now)
        XCTAssertEqual(split.upcoming.map(\.name), ["live-now", "tonight"])
    }
}
