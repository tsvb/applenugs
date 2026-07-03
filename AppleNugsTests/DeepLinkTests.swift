import XCTest

// NOTE: DeepLink.swift is compiled directly into this (host-free) logic-test
// bundle — see project.yml — so DeepLink / DeepLinkMatch are same-module types
// here, referenced without importing the app module.

final class DeepLinkParseTests: XCTestCase {

    func testShowAudioDefaults() {
        let link = DeepLink.parse(URL(string: "applenugs://show/2024-04-20?artist=Goose")!)
        XCTAssertEqual(link, DeepLink(date: "2024-04-20", artist: "Goose", venue: nil,
                                      song: nil, setNumber: nil, position: nil, media: .audio))
    }

    func testTrackWithVenueAndPercentDecoding() {
        let link = DeepLink.parse(URL(string:
            "applenugs://show/2024-04-20?artist=Goose&song=Hot%20Tea&set=1&pos=2&venue=The%20Salt%20Shed")!)
        XCTAssertEqual(link?.song, "Hot Tea")          // %20 → space
        XCTAssertEqual(link?.venue, "The Salt Shed")
        XCTAssertEqual(link?.setNumber, "1")
        XCTAssertEqual(link?.position, 2)
        XCTAssertEqual(link?.media, .audio)
    }

    func testVideoMedia() {
        let link = DeepLink.parse(URL(string: "applenugs://show/2026-05-30?artist=Goose&media=video")!)
        XCTAssertEqual(link?.media, .video)
    }

    func testUnknownMediaFallsBackToAudio() {
        let link = DeepLink.parse(URL(string: "applenugs://show/2024-04-20?artist=Goose&media=hologram")!)
        XCTAssertEqual(link?.media, .audio)
    }

    func testRejectsWrongScheme() {
        XCTAssertNil(DeepLink.parse(URL(string: "nugsnet://show/2024-04-20?artist=Goose")!))
        XCTAssertNil(DeepLink.parse(URL(string: "https://show/2024-04-20?artist=Goose")!))
    }

    func testRejectsWrongHost() {
        XCTAssertNil(DeepLink.parse(URL(string: "applenugs://artist/2024-04-20?artist=Goose")!))
    }

    func testRejectsMissingDate() {
        XCTAssertNil(DeepLink.parse(URL(string: "applenugs://show?artist=Goose")!))
        XCTAssertNil(DeepLink.parse(URL(string: "applenugs://show/?artist=Goose")!))
    }

    func testRejectsMissingOrEmptyArtist() {
        XCTAssertNil(DeepLink.parse(URL(string: "applenugs://show/2024-04-20")!))
        XCTAssertNil(DeepLink.parse(URL(string: "applenugs://show/2024-04-20?artist=")!))
    }

    func testEmptyOptionalsBecomeNil() {
        let link = DeepLink.parse(URL(string:
            "applenugs://show/2024-04-20?artist=Goose&venue=&song=&set=")!)
        XCTAssertNil(link?.venue)
        XCTAssertNil(link?.song)
        XCTAssertNil(link?.setNumber)
    }

    func testNonNumericPositionIsNil() {
        let link = DeepLink.parse(URL(string: "applenugs://show/2024-04-20?artist=Goose&pos=abc")!)
        XCTAssertNil(link?.position)
    }

    func testNonPaddedDateIsZeroPadded() {
        // The contract emits zero-padded dates, but a non-padded but otherwise
        // valid date must still match the catalog's padded dateText.
        let link = DeepLink.parse(URL(string: "applenugs://show/2024-4-20?artist=Goose")!)
        XCTAssertEqual(link?.date, "2024-04-20")
    }
}

final class DeepLinkMatchTests: XCTestCase {

    func testNormalizeLowercasesStripsPunctuationAndDiacritics() {
        XCTAssertEqual(DeepLinkMatch.normalize("  Hót-Tea! (Reprise)  "), "hottea reprise")
        XCTAssertEqual(DeepLinkMatch.normalize("Madhuvan"), "madhuvan")
    }

    func testVenueMatchesIsBidirectionalContains() {
        XCTAssertTrue(DeepLinkMatch.venueMatches("The Salt Shed", "Salt Shed"))
        XCTAssertTrue(DeepLinkMatch.venueMatches("Salt Shed", "The Salt Shed, Chicago"))
        XCTAssertFalse(DeepLinkMatch.venueMatches("Red Rocks", "The Salt Shed"))
    }

    func testVenueMatchesNilIsFalse() {
        XCTAssertFalse(DeepLinkMatch.venueMatches(nil, "Salt Shed"))
    }

    func testBestTrackIndexPrefersExactNormalizedMatch() {
        let titles = ["Intro", "Hot Tea", "Hot Tea Reprise"]
        XCTAssertEqual(DeepLinkMatch.bestTrackIndex(matching: "hot tea", inTitles: titles), 1)
    }

    func testBestTrackIndexFallsBackToContains() {
        let titles = ["Intro", "Arcadia", "Madhuvan > Hot Tea"]
        XCTAssertEqual(DeepLinkMatch.bestTrackIndex(matching: "Hot Tea", inTitles: titles), 2)
    }

    func testBestTrackIndexReturnsNilWhenNoMatch() {
        let titles = ["Intro", "Arcadia"]
        XCTAssertNil(DeepLinkMatch.bestTrackIndex(matching: "Bouncing Around the Room", inTitles: titles))
    }

    func testBestTrackIndexSeguePrefersLongestContainedTitle() {
        // A segue link "Madhuvan > Hot Tea" where the show split it into separate
        // tracks: the most specific contained title ("Madhuvan") should win, NOT
        // the earlier-listed standalone "Hot Tea".
        let titles = ["Intro", "Hot Tea", "Drive", "Madhuvan", "Arcadia"]
        XCTAssertEqual(DeepLinkMatch.bestTrackIndex(matching: "Madhuvan > Hot Tea", inTitles: titles), 3)
    }

    func testBestTrackIndexStillPrefersWholeTitleContainingSong() {
        // Forward containment (title ⊇ song) must still win over the segue rule.
        let titles = ["Intro", "Arcadia", "Madhuvan > Hot Tea"]
        XCTAssertEqual(DeepLinkMatch.bestTrackIndex(matching: "Hot Tea", inTitles: titles), 2)
    }
}
