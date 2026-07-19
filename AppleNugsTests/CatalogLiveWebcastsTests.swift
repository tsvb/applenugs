import XCTest

final class CatalogLiveWebcastsTests: XCTestCase {

    private func parse(_ items: String) -> [VideoSummary] {
        let data = #"{"items":["# .appending(items).appending("]}").data(using: .utf8)!
        return Catalog.liveWebcasts(from: JSON.parse(data))
    }

    func testExclusiveVideoWebcast() {
        let v = parse(#"""
        {"skuId":921842,"eventType":"exclusive","contentType":"video","has4KOption":false,
         "startDate":"2026-07-21T23:30:00+00:00",
         "release":{"id":"46811","title":"7-21-2026 Agganis Arena Boston, MA",
                    "performanceDate":"2026-07-21T00:00:00",
                    "artist":{"name":"Billy Strings"},
                    "image":{"url":"https://cdn/x.jpg"}}}
        """#)[0]
        XCTAssertEqual(v.access, .exclusive)
        XCTAssertFalse(v.isAudio)
        XCTAssertNil(v.externalURL)
        XCTAssertEqual(v.skuId, 921842)
        XCTAssertEqual(v.artistName, "Billy Strings")
        XCTAssertEqual(v.imagePath, "https://cdn/x.jpg")
    }

    func testFreeVideoCarriesNormalizedYouTubeURLAndNotes() {
        let v = parse(#"""
        {"skuId":900001,"eventType":"free","contentType":"video",
         "release":{"id":"1","title":"Benefit","artist":{"id":"0","name":""}},
         "freeVideo":{"showUrl":"https://www.youtube.com/embed/7pRya78tAAo",
                      "coverImage":"https://s3/cover.jpg",
                      "notes":"<p>Watch free on nugs</p>",
                      "artist":{"name":"Bruce Springsteen"}}}
        """#)[0]
        XCTAssertEqual(v.access, .free)
        XCTAssertEqual(v.externalURL?.absoluteString,
                       "https://www.youtube.com/watch?v=7pRya78tAAo")
        XCTAssertEqual(v.imagePath, "https://s3/cover.jpg")   // release image absent → S3 cover
        XCTAssertEqual(v.artistName, "Bruce Springsteen")     // fell back to freeVideo.artist
        XCTAssertEqual(v.benefitNotes, "<p>Watch free on nugs</p>")
    }

    func testFreeAudioWebcastHasNoExternalURL() {
        let v = parse(#"""
        {"skuId":923149,"eventType":"free","contentType":"audio",
         "release":{"id":"48000","title":"7-18-2026 Fox Theater Oakland, CA",
                    "artist":{"name":"Widespread Panic"}}}
        """#)[0]
        XCTAssertEqual(v.access, .free)
        XCTAssertTrue(v.isAudio)
        XCTAssertNil(v.externalURL)
        XCTAssertEqual(v.skuId, 923149)
    }

    func testPPVWebcast() {
        let v = parse(#"""
        {"skuId":916858,"eventType":"ppv","contentType":"video","has4KOption":true,
         "release":{"id":"33000","title":"7-8-2026 Red Rocks","artist":{"name":"Eric Church"}}}
        """#)[0]
        XCTAssertEqual(v.access, .ppv)
        XCTAssertTrue(v.has4K)
        XCTAssertNil(v.externalURL)
    }

    func testUnknownEventTypeDefaultsToExclusive() {
        let v = parse(#"""
        {"skuId":1,"eventType":"mystery","contentType":"video",
         "release":{"id":"9","title":"X","artist":{"name":"Y"}}}
        """#)[0]
        XCTAssertEqual(v.access, .exclusive)
    }

    func testFreeVideoTitleFallsBackToVenueName() {
        let v = parse(#"""
        {"skuId":5,"eventType":"free","contentType":"video",
         "release":{"id":"77","artist":{"name":"Various"}},
         "freeVideo":{"venue":{"name":"FREE STREAM: Civic Center Plaza"}}}
        """#)[0]
        XCTAssertEqual(v.title, "FREE STREAM: Civic Center Plaza")
    }

    func testEmbedURLQueryParamsAreStripped() {
        let v = parse(#"""
        {"skuId":6,"eventType":"free","contentType":"video",
         "release":{"id":"78","title":"X","artist":{"name":"Y"}},
         "freeVideo":{"showUrl":"https://www.youtube.com/embed/7pRya78tAAo?rel=0&foo=bar"}}
        """#)[0]
        XCTAssertEqual(v.externalURL?.absoluteString, "https://www.youtube.com/watch?v=7pRya78tAAo")
    }

    func testEmbedURLFragmentIsStripped() {
        let v = parse(#"""
        {"skuId":7,"eventType":"free","contentType":"video",
         "release":{"id":"79","title":"X","artist":{"name":"Y"}},
         "freeVideo":{"showUrl":"https://www.youtube.com/embed/abc123#t=30s"}}
        """#)[0]
        XCTAssertEqual(v.externalURL?.absoluteString, "https://www.youtube.com/watch?v=abc123")
    }

    func testFreeVideoWithNullReleaseIsNotDropped() {
        // Real free-video items: release:null, skuId:null, id only via freeVideo.
        // They must NOT be dropped — this is the headline free-stream feature.
        let list = parse(#"""
        {"skuId":null,"eventType":"free","contentType":"video","has4KOption":false,
         "release":null,
         "freeVideo":{"showUrl":"https://www.youtube.com/embed/KlZgj1u1bAE",
                      "coverImage":"https://s3.amazonaws.com/static.nugs.net/assets/webcasts/uuid.jpg",
                      "notes":"<p>Watch free</p>",
                      "venue":{"name":"Pasadena Civic Auditorium"},
                      "artist":{"id":"0","name":"A Concert For Altadena"}}}
        """#)
        XCTAssertEqual(list.count, 1, "free-video with null release must not be dropped")
        let v = list[0]
        XCTAssertEqual(v.access, .free)
        XCTAssertFalse(v.isAudio)
        XCTAssertEqual(v.externalURL?.absoluteString, "https://www.youtube.com/watch?v=KlZgj1u1bAE")
        XCTAssertEqual(v.benefitNotes, "<p>Watch free</p>")
        XCTAssertEqual(v.artistName, "A Concert For Altadena")
        XCTAssertEqual(v.imagePath, "https://s3.amazonaws.com/static.nugs.net/assets/webcasts/uuid.jpg")
        XCTAssertFalse(v.id.isEmpty, "must have a stable synthetic id")
    }
}
