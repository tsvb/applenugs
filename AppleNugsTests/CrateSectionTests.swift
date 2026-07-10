import XCTest

// NOTE: CrateSection.swift is compiled directly into this (host-free) logic-test
// bundle — see project.yml — so CrateSection / CrateSectionable are same-module
// types here, referenced without importing the app module.

private struct Stub: CrateSectionable {
    let date: Date?
    let searchText: String

    init(_ iso: String?, _ text: String = "") {
        self.date = iso.flatMap { Stub.parse($0) }
        self.searchText = text
    }

    static func parse(_ s: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }
}

// The catalog's own calendar: UTC, matching Catalog.parseDate. Using
// Calendar.current here would slide month starts across the boundary.
private let utc = CrateSection.catalogCalendar

final class CrateSectionTests: XCTestCase {

    // --- searchText ---------------------------------------------------------

    func testSearchTextFoldsCaseAndIncludesVenueAndDates() {
        let date = Stub.parse("2026-06-28")
        let text = CrateSection.searchText(
            title: "Merriweather Post Pavilion",
            venue: "Merriweather Post Pavilion, Columbia, MD",
            artistName: "Goose",
            dateText: "2026-06-28",
            date: date)
        XCTAssertTrue(text.contains("columbia"))       // city, from the venue string
        XCTAssertTrue(text.contains("md"))             // state
        XCTAssertTrue(text.contains("2026-06-28"))     // ISO form, as displayed
        XCTAssertTrue(text.contains("06/28/26"))       // short slashed form
        XCTAssertTrue(text.contains("6/28/2026"))      // long slashed form
        XCTAssertEqual(text, text.lowercased())
    }

    func testNormalizedFoldsDiacriticsAndTrims() {
        XCTAssertEqual(CrateSection.normalized("  CafÉ  "), "cafe")
    }

    // --- filtering ----------------------------------------------------------

    func testEmptyFilterReturnsEverything() {
        let items = [Stub("2026-06-28", "a"), Stub("2026-05-30", "b")]
        let s = CrateSection.sections(items, filter: "", calendar: utc)
        XCTAssertEqual(s.flatMap(\.items).count, 2)
    }

    func testFilterMatchesSubstringCaseInsensitively() {
        let items = [Stub("2026-06-21", "the salt shed, chicago il"),
                     Stub("2026-06-28", "merriweather post pavilion, columbia, md")]
        XCTAssertEqual(CrateSection.sections(items, filter: "Chicago", calendar: utc)
            .flatMap(\.items).count, 1)
        XCTAssertEqual(CrateSection.sections(items, filter: "salt shed", calendar: utc)
            .flatMap(\.items).count, 1)
        XCTAssertEqual(CrateSection.sections(items, filter: "zzz", calendar: utc)
            .flatMap(\.items).count, 0)
    }

    // --- sectioning ---------------------------------------------------------

    func testSectionsAreNewestMonthFirstAndItemsNewestFirst() {
        let items = [Stub("2026-05-30"), Stub("2026-06-21"), Stub("2026-06-28")]
        let s = CrateSection.sections(items, filter: "", calendar: utc)
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s[0].items.count, 2)                       // June
        XCTAssertEqual(s[0].items.first?.date, Stub.parse("2026-06-28"))
        XCTAssertEqual(s[0].items.last?.date, Stub.parse("2026-06-21"))
        XCTAssertEqual(s[1].items.count, 1)                       // May
    }

    func testMonthBoundarySplitsSections() {
        let items = [Stub("2026-06-30"), Stub("2026-07-01")]
        let s = CrateSection.sections(items, filter: "", calendar: utc)
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s[0].items.first?.date, Stub.parse("2026-07-01"))
    }

    func testUndatedItemsSortLastInTheirOwnSection() {
        let items = [Stub(nil), Stub("2026-06-28")]
        let s = CrateSection.sections(items, filter: "", calendar: utc)
        XCTAssertEqual(s.count, 2)
        XCTAssertNotNil(s[0].month)
        XCTAssertNil(s[1].month)
        XCTAssertEqual(s[1].items.count, 1)
    }

    // --- titles -------------------------------------------------------------

    func testMonthTitle() {
        let june = CrateSection.monthStart(Stub.parse("2026-06-28")!, calendar: utc)
        XCTAssertEqual(CrateSection.monthTitle(june, calendar: utc, locale: Locale(identifier: "en_US")), "June 2026")
        XCTAssertEqual(CrateSection.monthTitle(nil, calendar: utc, locale: Locale(identifier: "en_US")), "Unknown date")
    }
}
