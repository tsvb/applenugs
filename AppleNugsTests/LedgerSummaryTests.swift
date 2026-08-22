import XCTest

final class LedgerSummaryTests: XCTestCase {

    private func tally(_ name: String, plays: Int, hours: Double) -> LedgerSummary.Tally {
        LedgerSummary.Tally(key: name.lowercased(), displayName: name,
                            plays: plays, seconds: hours * 3600)
    }

    private var sample: [LedgerSummary.Tally] {
        [tally("Goose", plays: 41, hours: 63),
         tally("Billy Strings", plays: 28, hours: 44),
         tally("Umphrey's McGee", plays: 19, hours: 31),
         tally("Phish", plays: 9, hours: 14),
         tally("Khruangbin", plays: 6, hours: 9),
         tally("Dopapod", plays: 2, hours: 3)]
    }

    func testTotalsReportHoursAndDistinctArtistCount() {
        let totals = LedgerSummary.totals(sample)

        XCTAssertEqual(totals.hoursText, "164")        // 63+44+31+14+9+3
        XCTAssertEqual(totals.artistCount, 6)
        XCTAssertEqual(totals.artistCountText, "6")
    }

    func testTotalHoursBelowOneHourReadsLessThanOne() {
        XCTAssertEqual(LedgerSummary.totalHoursText(seconds: 0), "0")
        XCTAssertEqual(LedgerSummary.totalHoursText(seconds: 1_800), "<1")
        XCTAssertEqual(LedgerSummary.totalHoursText(seconds: 3_600), "1")
        XCTAssertEqual(LedgerSummary.totalHoursText(seconds: 7_199), "1")
        XCTAssertEqual(LedgerSummary.totalHoursText(seconds: .nan), "0")
    }

    func testTopFiveAreRankedBySeconds() {
        let rows = LedgerSummary.top(sample)

        XCTAssertEqual(LedgerSummary.topCount, 5)
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows.map(\.displayName),
                       ["Goose", "Billy Strings", "Umphrey's McGee", "Phish", "Khruangbin"])
        XCTAssertEqual(rows.map(\.rank), [1, 2, 3, 4, 5])
        XCTAssertEqual(rows[0].playsText, "41 plays")
        XCTAssertEqual(rows[0].hoursText, "63h")
        XCTAssertEqual(rows[0].id, rows[0].key)
    }

    /// The order must never flicker between renders on equal seconds.
    func testTiesBreakDeterministicallyByPlaysThenName() {
        let tied = [tally("Zeta", plays: 3, hours: 10),
                    tally("Alpha", plays: 3, hours: 10),
                    tally("Mu", plays: 9, hours: 10)]

        let names = LedgerSummary.top(tied).map(\.displayName)
        XCTAssertEqual(names, ["Mu", "Alpha", "Zeta"])
        XCTAssertEqual(LedgerSummary.top(tied.reversed()).map(\.displayName), names)
    }

    func testFewerThanFiveArtistsRenderOnlyWhatExists() {
        let two = [tally("Goose", plays: 4, hours: 5), tally("Phish", plays: 2, hours: 2)]

        XCTAssertEqual(LedgerSummary.top(two).count, 2)
        XCTAssertTrue(LedgerSummary.top([]).isEmpty)
        XCTAssertEqual(LedgerSummary.totals([]).artistCountText, "0")
    }

    /// The whole section is absent until a play has been credited — an empty
    /// ledger on Home is noise.
    func testIsEmptyUntilAPlayIsCredited() {
        XCTAssertTrue(LedgerSummary.isEmpty([]))
        XCTAssertTrue(LedgerSummary.isEmpty([tally("Goose", plays: 0, hours: 0.2)]))
        XCTAssertFalse(LedgerSummary.isEmpty([tally("Goose", plays: 1, hours: 0.2)]))
    }

    func testRowDurationFallsBackToMinutesAndPlaysTextSingularizes() {
        XCTAssertEqual(LedgerSummary.hoursText(seconds: 63 * 3600), "63h")
        XCTAssertEqual(LedgerSummary.hoursText(seconds: 3_600), "1h")
        XCTAssertEqual(LedgerSummary.hoursText(seconds: 2_460), "41m")
        XCTAssertEqual(LedgerSummary.hoursText(seconds: 5), "1m")
        XCTAssertEqual(LedgerSummary.hoursText(seconds: 0), "0m")
        XCTAssertEqual(LedgerSummary.hoursText(seconds: .infinity), "0m")

        XCTAssertEqual(LedgerSummary.playsText(0), "0 plays")
        XCTAssertEqual(LedgerSummary.playsText(1), "1 play")
        XCTAssertEqual(LedgerSummary.playsText(2), "2 plays")
    }
}
