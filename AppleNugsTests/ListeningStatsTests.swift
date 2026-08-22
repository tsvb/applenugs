import XCTest

// NOTE: ListeningStats.swift and DeepLink.swift are both compiled directly into
// this (host-free) logic-test bundle — see project.yml — so ListeningStats and
// DeepLinkMatch are same-module types here, referenced without importing the
// app module.

final class ListeningStatsTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_700_003_600)

    func testCreditCreatesATallyWithBothTimestamps() throws {
        var stats = ListeningStats.empty
        stats.credit(artistName: "Goose", seconds: 120, completedPlay: true, now: t0)

        XCTAssertEqual(stats.artists.count, 1)
        let tally = try XCTUnwrap(stats.artists["goose"])
        XCTAssertEqual(tally.displayName, "Goose")
        XCTAssertEqual(tally.plays, 1)
        XCTAssertEqual(tally.seconds, 120)
        XCTAssertEqual(tally.firstPlayedAt, t0)
        XCTAssertEqual(tally.lastPlayedAt, t0)
    }

    func testCreditAccumulatesSecondsAndPlaysAndMovesOnlyLastPlayed() {
        var stats = ListeningStats.empty
        stats.credit(artistName: "Goose", seconds: 120, completedPlay: true, now: t0)
        stats.credit(artistName: "Goose", seconds: 30, completedPlay: false, now: t1)
        stats.credit(artistName: "Goose", seconds: 90, completedPlay: true, now: t1)

        let tally = stats.artists["goose"]
        XCTAssertEqual(tally?.plays, 2)
        XCTAssertEqual(tally?.seconds, 240)
        XCTAssertEqual(tally?.firstPlayedAt, t0)
        XCTAssertEqual(tally?.lastPlayedAt, t1)
    }

    /// The whole reason the key is folded: the same artist typed two ways is
    /// one row, not two. This is `DeepLinkMatch.normalize`'s venue rule reused.
    func testFoldedKeyMergesPunctuationVariantsIntoOneTally() {
        var stats = ListeningStats.empty
        stats.credit(artistName: "Umphrey's McGee", seconds: 100, completedPlay: true, now: t0)
        stats.credit(artistName: "Umphreys McGee", seconds: 100, completedPlay: true, now: t1)
        stats.credit(artistName: "Umphrey\u{2019}s  McGee", seconds: 100, completedPlay: true, now: t1)

        XCTAssertEqual(stats.artists.count, 1)
        XCTAssertEqual(stats.artists.values.first?.plays, 3)
        XCTAssertEqual(stats.artists.values.first?.seconds, 300)
    }

    func testDisplayNameFollowsTheLastSeenSpelling() {
        var stats = ListeningStats.empty
        stats.credit(artistName: "Umphreys McGee", seconds: 10, completedPlay: false, now: t0)
        stats.credit(artistName: "Umphrey's McGee", seconds: 10, completedPlay: false, now: t1)

        XCTAssertEqual(stats.artists.values.first?.displayName, "Umphrey's McGee")
    }

    func testBlankOrUnfoldableArtistIsDroppedSilently() {
        var stats = ListeningStats.empty
        stats.credit(artistName: nil, seconds: 60, completedPlay: true, now: t0)
        stats.credit(artistName: "", seconds: 60, completedPlay: true, now: t0)
        stats.credit(artistName: "   ", seconds: 60, completedPlay: true, now: t0)
        stats.credit(artistName: "!!! ---", seconds: 60, completedPlay: true, now: t0)

        XCTAssertTrue(stats.artists.isEmpty)
        XCTAssertNil(ListeningStats.key(for: "  "))
        XCTAssertEqual(ListeningStats.key(for: " Goose "), "goose")
    }

    /// A NaN must never reach the file: it encodes as an error and would make
    /// listening.json undecodable on the next launch.
    func testNonFiniteOrNegativeSecondsContributeZeroAndAnEmptyCreditIsANoOp() {
        var stats = ListeningStats.empty
        stats.credit(artistName: "Goose", seconds: .nan, completedPlay: true, now: t0)
        stats.credit(artistName: "Goose", seconds: -50, completedPlay: false, now: t0)
        stats.credit(artistName: "Goose", seconds: .infinity, completedPlay: false, now: t0)

        XCTAssertEqual(stats.artists["goose"]?.seconds, 0)
        XCTAssertEqual(stats.artists["goose"]?.plays, 1)

        var untouched = ListeningStats.empty
        untouched.credit(artistName: "Goose", seconds: 0, completedPlay: false, now: t0)
        XCTAssertTrue(untouched.artists.isEmpty)
    }
}
