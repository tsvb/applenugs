import XCTest

final class DownloadManifestTests: XCTestCase {

    private func sampleShow(id: String = "s1") -> DownloadedShow {
        DownloadedShow(
            containerID: id,
            title: "2024-03-14 Capitol Theatre",
            artist: "Billy Strings",
            artworkPath: "/images/art.jpg",
            tracks: [
                DownloadedTrack(trackId: "t1", title: "Away From the Mire",
                                artist: "Billy Strings", durationText: "9:12",
                                fileName: "t1.flac", formatRaw: "flac16", bytes: 100),
                DownloadedTrack(trackId: "t2", title: "Dust in a Baggie",
                                artist: "Billy Strings", durationText: "4:01",
                                fileName: "t2.flac", formatRaw: "flac16", bytes: 50),
            ])
    }

    func testRoundTripsThroughJSON() throws {
        var manifest = DownloadManifest()
        manifest.upsert(sampleShow())

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(DownloadManifest.self, from: data)

        XCTAssertEqual(decoded, manifest)
        XCTAssertEqual(decoded.shows.count, 1)
        XCTAssertEqual(decoded.shows[0].tracks.map(\.trackId), ["t1", "t2"])
    }

    func testUpsertReplacesShowWithSameID() {
        var manifest = DownloadManifest()
        manifest.upsert(sampleShow())

        var updated = sampleShow()
        updated.title = "Renamed"
        manifest.upsert(updated)

        XCTAssertEqual(manifest.shows.count, 1)
        XCTAssertEqual(manifest.shows[0].title, "Renamed")
    }

    func testRemoveShowDeletesOnlyThatShow() {
        var manifest = DownloadManifest()
        manifest.upsert(sampleShow(id: "s1"))
        manifest.upsert(sampleShow(id: "s2"))

        manifest.removeShow(id: "s1")

        XCTAssertNil(manifest.show(id: "s1"))
        XCTAssertNotNil(manifest.show(id: "s2"))
        XCTAssertEqual(manifest.shows.count, 1)
    }

    func testTrackLookupFindsTrackAcrossShows() {
        var manifest = DownloadManifest()
        manifest.upsert(sampleShow(id: "s1"))

        XCTAssertEqual(manifest.track(id: "t2")?.fileName, "t2.flac")
        XCTAssertNil(manifest.track(id: "missing"))
    }

    func testShowTotalBytesSumsTracks() {
        XCTAssertEqual(sampleShow().totalBytes, 150)
    }

    func testManifestTotalBytesSumsAllShows() {
        var manifest = DownloadManifest()
        XCTAssertEqual(manifest.totalBytes, 0)
        manifest.upsert(sampleShow(id: "s1"))
        manifest.upsert(sampleShow(id: "s2"))
        XCTAssertEqual(manifest.totalBytes, 300)
    }
}
