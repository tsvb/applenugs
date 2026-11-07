import XCTest

final class StreamTierPlanTests: XCTestCase {

    private func pick(_ tier: Int, _ url: String) -> StreamPick {
        StreamPick(url: url, platformId: tier, format: .identify(url))
    }

    /// Drives the walk the way `NugsClient.walkTiers` does, against a fake
    /// resolver, and records every request in the order it was made.
    private func walk(_ answers: [Int: StreamTierPlan.Outcome],
                      known: [Int: StreamTierPlan.Outcome] = [:],
                      skipping: Set<Int> = [],
                      purpose: StreamTierPlan.Purpose = .playback)
        -> (picks: [StreamPick], requests: [Int]) {
        var known = known
        var requests: [Int] = []
        while true {
            switch StreamTierPlan.next(known: known, skipping: skipping, purpose: purpose) {
            case .done(let picks):
                return (picks, requests)
            case .request(let tier):
                XCTAssertFalse(requests.contains(tier), "tier \(tier) asked twice")
                requests.append(tier)
                known[tier] = answers[tier] ?? .failed
            }
        }
    }

    func testOrderIsTierSevenThenTheOldPreferenceOrder() {
        XCTAssertEqual(StreamTierPlan.order, [7, 1, 4, 10])
        XCTAssertEqual(Set(StreamTierPlan.order), Set(NugsConstants.probePlatforms))
    }

    /// The probe's track: tier 7 has ALAC, so that is the one and only request.
    func testAUsableTierSevenIsTheOnlyRequest() {
        let alac = pick(7, "https://cdn/x.alac16/t.m4a")
        let result = walk([7: .stream(alac), 1: .stream(pick(1, "https://cdn/x.flac16/t.flac"))])
        XCTAssertEqual(result.requests, [7])
        XCTAssertEqual(result.picks, [alac])
    }

    func testNoLinkOnTierSevenFallsThroughOneTierAtATime() {
        let flac = pick(1, "https://cdn/x.flac16/t.flac")
        let result = walk([7: .noStream, 1: .stream(flac), 4: .stream(pick(4, "https://cdn/x.mqa24/t.flac"))])
        XCTAssertEqual(result.requests, [7, 1])
        XCTAssertEqual(result.picks, [flac])
    }

    func testAFailedRequestIsTreatedAsNoStreamForThisWalk() {
        let mqa = pick(4, "https://cdn/x.mqa24/t.flac")
        let result = walk([7: .failed, 1: .failed, 4: .stream(mqa)])
        XCTAssertEqual(result.requests, [7, 1, 4])
        XCTAssertEqual(result.picks, [mqa])
    }

    /// A format the player can't use doesn't end the walk — but it isn't
    /// thrown away either: with nothing better it comes back as a last resort.
    func testAnUnplayableFormatKeepsWalkingAndSurvivesAsALastResort() {
        let s360 = pick(7, "https://cdn/x.s360/t.mp4")
        let flac = pick(1, "https://cdn/x.flac16/t.flac")
        XCTAssertEqual(walk([7: .stream(s360), 1: .stream(flac)]).picks, [flac])

        let unknown = pick(1, "https://cdn/mystery/t.ogg")
        let lastResort = walk([7: .stream(s360), 1: .stream(unknown), 4: .noStream, 10: .noStream])
        XCTAssertEqual(lastResort.requests, [7, 1, 4, 10])
        XCTAssertEqual(lastResort.picks, [s360, unknown])   // preferenceRank: 360RA before unknown
    }

    func testNothingAnywhereIsEmpty() {
        let result = walk([7: .noStream, 1: .noStream, 4: .failed, 10: .noStream])
        XCTAssertEqual(result.requests, [7, 1, 4, 10])
        XCTAssertEqual(result.picks, [])
    }

    func testCachedAnswersMakeNoRequests() {
        let alac = pick(7, "https://cdn/x.alac16/t.m4a")
        let result = walk([:], known: [7: .stream(alac)])
        XCTAssertEqual(result.requests, [])
        XCTAssertEqual(result.picks, [alac])
    }

    /// A cached "no stream" isn't asked again; the walk resumes after it.
    func testACachedNoStreamIsSkippedWithoutARequest() {
        let flac = pick(1, "https://cdn/x.flac16/t.flac")
        let result = walk([1: .stream(flac)], known: [7: .noStream])
        XCTAssertEqual(result.requests, [1])
        XCTAssertEqual(result.picks, [flac])
    }

    /// After the player watched tier 7 fail, the retry must not be handed it.
    func testSkippedTiersAreNeitherAskedNorReturned() {
        let alac = pick(7, "https://cdn/x.alac16/t.m4a")
        let flac = pick(1, "https://cdn/x.flac16/t.flac")
        let result = walk([7: .stream(alac), 1: .stream(flac)], known: [7: .stream(alac)],
                          skipping: [7])
        XCTAssertEqual(result.requests, [1])
        XCTAssertEqual(result.picks, [flac])
    }

    /// HLS plays, but a download needs a file: it falls through for downloads.
    func testHLSSatisfiesPlaybackButNotDownload() {
        let hls = pick(7, "https://cdn/x/master.m3u8")
        let flac = pick(1, "https://cdn/x.flac16/t.flac")
        let answers: [Int: StreamTierPlan.Outcome] = [7: .stream(hls), 1: .stream(flac)]
        XCTAssertEqual(walk(answers, purpose: .playback).picks, [hls])
        let download = walk(answers, purpose: .download)
        XCTAssertEqual(download.requests, [7, 1])
        XCTAssertEqual(download.picks, [flac])
    }

    func testOutcomeClassifiesTheLink() {
        XCTAssertEqual(StreamTierPlan.outcome(link: nil, platformId: 7), .noStream)
        XCTAssertEqual(StreamTierPlan.outcome(link: "", platformId: 7), .noStream)
        XCTAssertEqual(StreamTierPlan.outcome(link: "https://cdn/x.alac16/t.m4a", platformId: 7),
                       .stream(StreamPick(url: "https://cdn/x.alac16/t.m4a", platformId: 7, format: .alac16)))
        XCTAssertTrue(StreamTierPlan.Outcome.noStream.isCacheable)
        XCTAssertFalse(StreamTierPlan.Outcome.failed.isCacheable)
    }

    func testLastResortDedupsByFormatKeepingWalkOrder() {
        let a = pick(7, "https://cdn/a.s360/t.mp4")
        let b = pick(1, "https://cdn/b.s360/t.mp4")
        XCTAssertEqual(StreamTierPlan.lastResort([a, b]), [a])
    }
}
