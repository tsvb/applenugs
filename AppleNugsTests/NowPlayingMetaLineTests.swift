import XCTest

final class NowPlayingMetaLineTests: XCTestCase {

    private typealias Line = NowPlayingMetaLine
    private typealias Target = NowPlayingMetaLine.Target

    // MARK: - joined shape

    func testJoinedYieldsThreeRunsWithAnUnlinkedSeparator() {
        let s = Line.segments(artist: "Goose", show: "11/13/24 The Anthem", showId: "42")
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s[0].text, "Goose")
        XCTAssertEqual(s[0].target, .artist(name: "Goose"))
        XCTAssertEqual(s[1].text, " · ")
        XCTAssertNil(s[1].target, "the separator must never be clickable")
        XCTAssertEqual(s[2].text, "11/13/24 The Anthem")
        XCTAssertEqual(s[2].target, .show(id: "42", title: "11/13/24 The Anthem"))
    }

    func testSingleFieldYieldsOneRunAndNoDanglingSeparator() {
        let artistOnly = Line.segments(artist: "Goose", show: nil, showId: nil)
        XCTAssertEqual(artistOnly.map(\.text), ["Goose"])

        let showOnly = Line.segments(artist: nil, show: "The Anthem", showId: "42")
        XCTAssertEqual(showOnly.map(\.text), ["The Anthem"])
    }

    func testNeitherFieldYieldsNothing() {
        XCTAssertTrue(Line.segments(artist: nil, show: nil, showId: nil).isEmpty)
        XCTAssertTrue(Line.segments(artist: "", show: "  ", showId: "42").isEmpty)
    }

    /// The old flat join kept an empty-but-non-nil field, producing a leading
    /// " · ". Dropping it is a fix, not a regression.
    func testEmptyFieldIsDroppedRatherThanLeavingASeparator() {
        let s = Line.segments(artist: "", show: "The Anthem", showId: "42")
        XCTAssertEqual(s.map(\.text), ["The Anthem"])
    }

    // MARK: - linkability

    /// The show is linkable only when a real container id is in hand. Without
    /// one there is nothing to resolve a title against — the single-track Search
    /// play, and any queue restored from a nowplaying.json written before
    /// showId existed.
    func testShowIsNotLinkableWithoutAContainerId() {
        let s = Line.segments(artist: "Goose", show: "The Anthem", showId: nil)
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s[2].text, "The Anthem")
        XCTAssertNil(s[2].target)
        XCTAssertNotNil(s[0].target, "the artist stays linkable regardless")
    }

    func testBlankContainerIdIsTreatedAsAbsent() {
        let s = Line.segments(artist: nil, show: "The Anthem", showId: "   ")
        XCTAssertNil(s[0].target)
    }

    /// A whitespace-only name must not become an empty link.
    func testWhitespaceOnlyArtistIsDroppedEntirely() {
        let s = Line.segments(artist: "   ", show: "The Anthem", showId: "42")
        XCTAssertEqual(s.map(\.text), ["The Anthem"])
    }

    /// Catalog names occasionally carry stray whitespace; the link target must
    /// carry the trimmed name or the catalog lookup misses.
    func testFieldsAreTrimmedForBothDisplayAndTarget() {
        let s = Line.segments(artist: " Goose ", show: " The Anthem ", showId: " 42 ")
        XCTAssertEqual(s[0].text, "Goose")
        XCTAssertEqual(s[0].target, .artist(name: "Goose"))
        XCTAssertEqual(s[2].text, "The Anthem")
        XCTAssertEqual(s[2].target, .show(id: "42", title: "The Anthem"))
    }

    // MARK: - casing

    func testUpperCasesEachRunWithoutChangingRunBoundaries() {
        let plain = Line.segments(artist: "Goose", show: "The Anthem", showId: "42")
        let upper = Line.segments(artist: "Goose", show: "The Anthem", showId: "42",
                                  casing: .upper)
        XCTAssertEqual(upper.count, plain.count)
        XCTAssertEqual(upper.map(\.text), ["GOOSE", " · ", "THE ANTHEM"])
        // The target keeps the original casing — it is a lookup key, not display.
        XCTAssertEqual(upper[0].target, .artist(name: "Goose"))
        XCTAssertEqual(upper[2].target, .show(id: "42", title: "The Anthem"))
    }

    // MARK: - fields

    /// MiniPlayerFaceplate, MiniPlayerClickWheel and ClickWheelScreen render the
    /// artist alone; asking for one field must not leave a separator behind.
    func testRestrictingToASingleFieldDropsTheOther() {
        let s = Line.segments(artist: "Goose", show: "The Anthem", showId: "42",
                              fields: [.artist])
        XCTAssertEqual(s.map(\.text), ["Goose"])
    }

    // MARK: - firstAvailable

    func testFirstAvailablePrefersTheShowAndFallsBackToTheArtist() {
        let both = Line.segments(artist: "Goose", show: "The Anthem", showId: "42",
                                 mode: .firstAvailable)
        XCTAssertEqual(both.map(\.text), ["The Anthem"])

        let artistOnly = Line.segments(artist: "Goose", show: nil, showId: nil,
                                       mode: .firstAvailable)
        XCTAssertEqual(artistOnly.map(\.text), ["Goose"])
        XCTAssertEqual(artistOnly[0].target, .artist(name: "Goose"))

        XCTAssertTrue(Line.segments(artist: nil, show: nil, showId: nil,
                                    mode: .firstAvailable).isEmpty)
    }

    // MARK: - compatibility with the string it replaces

    /// The guard that none of the sixteen render sites changed what they paint.
    /// `NowPlayingMeta.line` was `[artist, show].compactMap { $0 }.joined(" · ")`;
    /// for well-formed data the concatenated runs must reproduce it exactly.
    func testConcatenatedRunsReproduceTheOldFlatJoin() {
        let cases: [(String?, String?)] = [
            ("Goose", "11/13/24 The Anthem, Washington, DC"),
            ("Billy Strings", "2024-03-14 Capitol Theatre, Port Chester, NY"),
            ("Goose", nil),
            (nil, "The Anthem"),
            (nil, nil),
        ]
        for (artist, show) in cases {
            let old = [artist, show].compactMap { $0 }.joined(separator: " · ")
            XCTAssertEqual(Line.text(artist: artist, show: show), old,
                           "artist=\(artist ?? "nil") show=\(show ?? "nil")")
        }
    }

    // MARK: - URL round trip

    func testArtistTargetRoundTripsThroughAURL() {
        for name in ["Goose", "Umphrey's McGee", "Béla Fleck", "Brothers & Sisters",
                     "AC/DC", "?uestlove", "Sam & Dave · Live"] {
            let target = Target.artist(name: name)
            XCTAssertEqual(Target(url: target.url), target, name)
        }
    }

    func testShowTargetRoundTripsThroughAURL() {
        let target = Target.show(id: "23847", title: "11/13/24 The Anthem, Washington, DC")
        XCTAssertEqual(Target(url: target.url), target)
    }

    func testForeignAndMalformedURLsAreRejected() {
        // Anything not ours must fall through to the system opener, or the
        // donation links in VideoDetailView's webcast notes stop working.
        XCTAssertNil(Target(url: URL(string: "https://nugs.net")!))
        XCTAssertNil(Target(url: URL(string: "applenugs://show/2024-03-14")!))
        XCTAssertNil(Target(url: URL(string: "x-applenugs-meta://elsewhere?name=Goose")!))
        XCTAssertNil(Target(url: URL(string: "x-applenugs-meta://artist")!))
        XCTAssertNil(Target(url: URL(string: "x-applenugs-meta://artist?name=")!))
        XCTAssertNil(Target(url: URL(string: "x-applenugs-meta://show?title=No%20Id")!))
    }

    /// A show link only needs its id to work; a missing title degrades to an
    /// empty title hint rather than dropping the navigation.
    func testShowURLSurvivesAMissingTitle() {
        XCTAssertEqual(Target(url: URL(string: "x-applenugs-meta://show?id=42")!),
                       .show(id: "42", title: ""))
    }
}
