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

    // --- sealed downloads + migration --------------------------------------------

    func testPreEncryptionManifestStillDecodes() throws {
        // A manifest written before sealing existed: no contentType key.
        let json = """
        {"shows":[{"containerID":"s1","tracks":[{"trackId":"t1","fileName":"t1.flac",
        "formatRaw":"flac16","bytes":100}]}]}
        """
        let manifest = try JSONDecoder().decode(DownloadManifest.self, from: Data(json.utf8))
        let track = try XCTUnwrap(manifest.track(id: "t1"))
        XCTAssertNil(track.contentType)
        XCTAssertFalse(track.isSealed)
        XCTAssertEqual(manifest.unsealedTracks.map(\.track.trackId), ["t1"])
    }

    func testOnlyYetiFilesCountAsSealed() {
        var track = sampleShow().tracks[0]
        XCTAssertFalse(track.isSealed)
        track.fileName = "0f4c1e0a-8d1b-4c39-9a52-2c3b5d6e7f80.yeti"
        XCTAssertTrue(track.isSealed)
        track.fileName = "t1.flac.yeti.flac"
        XCTAssertFalse(track.isSealed)
    }

    func testMigrationCommitRepointsOnlyTheMatchingEntry() {
        var manifest = DownloadManifest()
        manifest.upsert(sampleShow(id: "s1"))
        XCTAssertEqual(manifest.unsealedTracks.count, 2)

        XCTAssertTrue(manifest.replaceFile(trackId: "t1", containerID: "s1", oldFileName: "t1.flac",
                                           newFileName: "a.yeti", bytes: 132,
                                           contentType: "org.xiph.flac"))
        let t1 = manifest.track(id: "t1")
        XCTAssertEqual(t1?.fileName, "a.yeti")
        XCTAssertEqual(t1?.bytes, 132)
        XCTAssertEqual(t1?.contentType, "org.xiph.flac")
        XCTAssertEqual(manifest.unsealedTracks.map(\.track.trackId), ["t2"])
        XCTAssertEqual(manifest.fileNames(containerID: "s1"), ["a.yeti", "t2.flac"])

        // A stale step (the entry already moved on) changes nothing.
        XCTAssertFalse(manifest.replaceFile(trackId: "t1", containerID: "s1", oldFileName: "t1.flac",
                                            newFileName: "b.yeti", bytes: 1, contentType: "x"))
        XCTAssertEqual(manifest.track(id: "t1")?.fileName, "a.yeti")
        // Unknown show or track: nothing.
        XCTAssertFalse(manifest.replaceFile(trackId: "t2", containerID: "nope", oldFileName: "t2.flac",
                                            newFileName: "c.yeti", bytes: 1, contentType: "x"))
        XCTAssertEqual(manifest.fileNames(containerID: "nope"), [])
    }
}
