import XCTest

final class StreamPickDownloadTests: XCTestCase {

    private func pick(_ url: String, format: AudioFormat) -> StreamPick {
        StreamPick(url: url, platformId: 1, format: format)
    }

    func testHLSPicksAreNotDownloadable() {
        XCTAssertFalse(pick("https://cdn/x/master.m3u8", format: .hls).isDownloadable)
        // Even a mislabeled format is caught by the URL.
        XCTAssertFalse(pick("https://cdn/x/master.m3u8", format: .flac16).isDownloadable)
        XCTAssertTrue(pick("https://cdn/x.flac16/track.flac", format: .flac16).isDownloadable)
    }

    func testBestDownloadablePickHonorsPreferenceRankAndSkipsHLS() {
        let picks = [
            pick("https://cdn/a/master.m3u8", format: .hls),
            pick("https://cdn/b.aac150/t.m4a", format: .aac150),
            pick("https://cdn/c.flac16/t.flac", format: .flac16),
            pick("https://cdn/d.alac16/t.m4a", format: .alac16),
        ]
        // alac16 has the best (lowest) preferenceRank among downloadables.
        XCTAssertEqual(bestDownloadablePick(picks)?.format, .alac16)
    }

    func testBestDownloadablePickIsNilWhenOnlyHLSOffered() {
        let picks = [pick("https://cdn/a/master.m3u8", format: .hls)]
        XCTAssertNil(bestDownloadablePick(picks))
    }

    func testDownloadFileExtensionFollowsFormat() {
        XCTAssertEqual(pick("https://cdn/c.flac16/t.flac", format: .flac16).downloadFileExtension, "flac")
        XCTAssertEqual(pick("https://cdn/c.mqa24/t.flac", format: .mqa24).downloadFileExtension, "flac")
        XCTAssertEqual(pick("https://cdn/d.alac16/t.m4a", format: .alac16).downloadFileExtension, "m4a")
        XCTAssertEqual(pick("https://cdn/b.aac150/t.m4a", format: .aac150).downloadFileExtension, "m4a")
    }

    func testDownloadFileExtensionFallsBackToURLPathExtension() {
        XCTAssertEqual(pick("https://cdn/mystery/t.ogg", format: .unknown).downloadFileExtension, "ogg")
        // No usable extension anywhere → a neutral default.
        XCTAssertEqual(pick("https://cdn/mystery/track", format: .unknown).downloadFileExtension, "bin")
    }
}
