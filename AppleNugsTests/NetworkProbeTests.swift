#if DEBUG
import XCTest

final class NetworkProbeTests: XCTestCase {

    private let honest = NugsIdentity.honest(version: "1.5", platform: "iOS 26.5")

    // MARK: - Plan

    func testPlanIsFourAPIEightResolveFourCDN() {
        let all = ProbePlan.allSteps(platforms: [1, 4, 7, 10])
        XCTAssertEqual(all.count, 16)
        XCTAssertEqual(all.filter { $0.group == .api }.count, 4)
        XCTAssertEqual(all.filter { $0.group == .resolve }.count, 8)
        XCTAssertEqual(all.filter { $0.group == .cdn }.count, 4)
        XCTAssertEqual(Set(all).count, all.count, "every step is distinct")
    }

    func testPlanDefaultsToTheProductionTiers() {
        XCTAssertEqual(ProbePlan.resolveSteps().count, NugsConstants.probePlatforms.count * 2)
    }

    func testControlRunsFirstInEveryGroup() {
        XCTAssertEqual(ProbePlan.apiSteps,
                       [.api(.spoofed), .api(.honest), .catalog(.spoofed), .catalog(.honest)])
        XCTAssertEqual(ProbePlan.resolveSteps(platforms: [1, 4, 7, 10]).prefix(4),
                       [.resolve(.spoofed, platformId: 1), .resolve(.spoofed, platformId: 4),
                        .resolve(.spoofed, platformId: 7), .resolve(.spoofed, platformId: 10)])
        XCTAssertEqual(ProbePlan.cdnSteps.first, .cdn(.spoofed, referer: true))
    }

    /// The control CDN step must be exactly today's playback request.
    func testControlCDNStepSendsTodaysHeaders() {
        let identity = ProbeStep.cdn(.spoofed, referer: true).identity(honest: honest)
        XCTAssertEqual(identity.cdnHeaders, NugsIdentity.current.cdnHeaders)
    }

    func testRefererIsIndependentOfTheUA() {
        let spoofedBare = ProbeStep.cdn(.spoofed, referer: false).identity(honest: honest)
        XCTAssertEqual(spoofedBare.cdnHeaders, ["User-Agent": NugsConstants.mobileUserAgent])
        let honestReferer = ProbeStep.cdn(.honest, referer: true).identity(honest: honest)
        XCTAssertEqual(honestReferer.cdnHeaders, [
            "User-Agent": honest.userAgentCDN, "Referer": NugsConstants.playerReferer,
        ])
    }

    func testResolveStepsUseTheLegacyUA() {
        XCTAssertEqual(ProbeStep.resolve(.spoofed, platformId: 1).identity(honest: honest).userAgentLegacy,
                       "nugsnetAndroid")
        XCTAssertEqual(ProbeStep.resolve(.honest, platformId: 1).identity(honest: honest).userAgentLegacy,
                       honest.userAgentAPI)
    }

    // MARK: - CDN target

    private func resolved(_ ua: ProbeUA, _ tier: Int, _ path: String?) -> ProbeResult {
        let body = path.map { #"{"streamLink":"https://cdn.example/\#($0)?sig=x"}"# } ?? #"{"streamLink":""}"#
        return ProbeParse.resolve(step: .resolve(ua, platformId: tier), status: 200,
                                  body: Data(body.utf8))
    }

    func testCDNTargetPrefersTheBestControlFormat() {
        let results = [
            resolved(.spoofed, 1, "a.aac150/t.m4a"),
            resolved(.spoofed, 4, "a.flac16/t.flac"),
            resolved(.spoofed, 7, "a.alac16/t.m4a"),
            resolved(.honest, 1, "a.alac16/t.m4a"),
        ]
        let target = ProbePlan.cdnTarget(from: results)
        XCTAssertEqual(target?.step, .resolve(.spoofed, platformId: 7))
        XCTAssertEqual(target?.format, .alac16)
    }

    func testCDNTargetBreaksATieOnTheLowestTier() {
        let results = [resolved(.spoofed, 10, "a.flac16/t.flac"), resolved(.spoofed, 4, "b.flac16/t.flac")]
        XCTAssertEqual(ProbePlan.cdnTarget(from: results)?.platformId, 4)
    }

    func testCDNTargetFallsBackToAnHonestResolve() {
        let results = [resolved(.spoofed, 1, nil), resolved(.honest, 4, "a.flac16/t.flac")]
        XCTAssertEqual(ProbePlan.cdnTarget(from: results)?.step, .resolve(.honest, platformId: 4))
    }

    func testCDNTargetIsNilWithoutAnyURL() {
        XCTAssertNil(ProbePlan.cdnTarget(from: [resolved(.spoofed, 1, nil), resolved(.honest, 1, nil)]))
        XCTAssertNil(ProbePlan.cdnTarget(from: []))
    }

    // MARK: - Parsing

    func testResolveWithLinkReportsFormatAndFields() {
        let body = #"{"streamLink":"https://cdn.example/x.flac16/1.flac","bitrate":"1411","Codec":"flac","userID":"9"}"#
        let r = ProbeParse.resolve(step: .resolve(.honest, platformId: 1), status: 200, body: Data(body.utf8))
        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.format, .flac16)
        XCTAssertEqual(r.summary, "FLAC 16-bit lossless · Codec=flac · bitrate=1411")
        XCTAssertEqual(r.detail, ["keys: Codec, bitrate, streamLink, userID"])
    }

    func testResolveNon2xxFailsWithStatusAndSnippet() {
        let r = ProbeParse.resolve(step: .resolve(.honest, platformId: 4), status: 403,
                                   body: Data("Forbidden\n  client".utf8))
        XCTAssertFalse(r.ok)
        XCTAssertEqual(r.status, 403)
        XCTAssertEqual(r.summary, "HTTP 403")
        XCTAssertEqual(r.detail, ["body: Forbidden client"])
        XCTAssertNil(r.streamURL)
    }

    func testResolve2xxWithoutLinkIsAFailure() {
        let r = ProbeParse.resolve(step: .resolve(.spoofed, platformId: 10), status: 200,
                                   body: Data(#"{"streamLink":""}"#.utf8))
        XCTAssertFalse(r.ok)
        XCTAssertEqual(r.summary, "No stream link")
    }

    func testSnippetTruncates() {
        let s = ProbeParse.snippet(Data(String(repeating: "a", count: 300).utf8), limit: 10)
        XCTAssertEqual(s, "aaaaaaaaaa…")
    }

    func testCDNRangeHonored() {
        let r = ProbeParse.cdn(step: .cdn(.honest, referer: false), status: 206,
                               contentType: "audio/flac", contentLength: "1024",
                               contentRange: "bytes 0-1023/38200000")
        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.summary, "audio/flac · 1024 B of 38.2 MB")
    }

    func testCDNRangeIgnoredStillPasses() {
        let r = ProbeParse.cdn(step: .cdn(.honest, referer: false), status: 200,
                               contentType: "audio/flac", contentLength: "38200000", contentRange: nil)
        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.summary, "audio/flac · 38200000 B · Range ignored")
    }

    func testCDNForbidden() {
        let r = ProbeParse.cdn(step: .cdn(.honest, referer: false), status: 403,
                               contentType: "text/html", contentLength: nil, contentRange: nil)
        XCTAssertFalse(r.ok)
        XCTAssertEqual(r.summary, "HTTP 403 · text/html")
    }

    func testContentRangeTotal() {
        XCTAssertEqual(ProbeParse.totalBytes(fromContentRange: "bytes 0-1023/40000000"), 40_000_000)
        XCTAssertNil(ProbeParse.totalBytes(fromContentRange: "bytes 0-1023/*"))
        XCTAssertNil(ProbeParse.totalBytes(fromContentRange: "garbage"))
    }

    func testCatalogStepsUseTheAPIUA() {
        XCTAssertEqual(ProbeStep.catalog(.spoofed).identity(honest: honest).userAgentAPI,
                       NugsConstants.mobileUserAgent)
        XCTAssertEqual(ProbeStep.catalog(.honest).identity(honest: honest).userAgentAPI,
                       honest.userAgentAPI)
        XCTAssertEqual(ProbeStep.catalog(.honest).group, .api)
    }

    func testCatalogParsesThroughTheProductionParser() {
        let body = #"{"Response":{"containerInfo":"Live","tracks":[{"trackID":"t1","songTitle":"A"},{"trackID":"t2","songTitle":"B"}]}}"#
        let r = ProbeParse.catalog(step: .catalog(.honest), status: 200, body: Data(body.utf8),
                                   showId: "s1", trackId: "t1")
        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.summary, "Show parsed · 2 tracks · current track listed")
        let other = ProbeParse.catalog(step: .catalog(.honest), status: 200, body: Data(body.utf8),
                                       showId: "s1", trackId: "t9")
        XCTAssertEqual(other.summary, "Show parsed · 2 tracks · current track not listed")
    }

    func testCatalogWithoutTracksFails() {
        let r = ProbeParse.catalog(step: .catalog(.honest), status: 200,
                                   body: Data(#"{"Response":{"error":"x"}}"#.utf8),
                                   showId: "s1", trackId: "t1")
        XCTAssertFalse(r.ok)
        XCTAssertEqual(r.summary, "Show didn't parse")
        XCTAssertEqual(r.detail, ["keys: error"])
        let denied = ProbeParse.catalog(step: .catalog(.honest), status: 403, body: Data(),
                                        showId: "s1", trackId: "t1")
        XCTAssertFalse(denied.ok)
        XCTAssertEqual(denied.summary, "HTTP 403")
    }

    func testAPIResult() {
        XCTAssertEqual(ProbeParse.api(step: .api(.honest), status: 200, body: Data()).summary, "Accepted")
        let denied = ProbeParse.api(step: .api(.honest), status: 401, body: Data("nope".utf8))
        XCTAssertFalse(denied.ok)
        XCTAssertEqual(denied.detail, ["body: nope"])
    }

    // MARK: - Report

    func testReportLineAlignment() {
        let r = ProbeResult(step: .api(.honest), ok: true, status: 200, summary: "Accepted")
        XCTAssertEqual(ProbeReport.line(r), "✓ 200  Subscriptions · Yeti UA         Accepted")
        let none = ProbeParse.failure(step: .cdn(.honest, referer: false), error: "Timed out")
        XCTAssertTrue(ProbeReport.line(none).hasPrefix("✗   —  Yeti UA · no Referer"))
    }

    func testReportNeverPrintsTheSignedURL() {
        let results = [resolved(.spoofed, 1, "a.flac16/t.flac")]
        let text = ProbeReport.text(header: header(), results: results,
                                    cdnTarget: ProbePlan.cdnTarget(from: results))
        XCTAssertFalse(text.contains("sig=x"))
        XCTAssertFalse(text.contains("cdn.example"))
        XCTAssertTrue(text.contains("target: FLAC 16-bit lossless from Android UA · tier 1"))
    }

    func testReportLayout() {
        let results = [
            ProbeResult(step: .api(.spoofed), ok: true, status: 200, summary: "Accepted"),
            ProbeResult(step: .api(.honest), ok: false, status: 403, summary: "HTTP 403",
                        detail: ["body: denied"]),
        ]
        let text = ProbeReport.text(header: header(), results: results, cdnTarget: nil,
                                    note: "CDN checks skipped — no resolve returned a stream URL.")
        XCTAssertEqual(text, """
            Yeti network probe — 2026-11-06T12:00:00Z
            App: Yeti 1.5 · iOS 26.5
            Track: Away From the Mire — Billy Strings (trackID t1, show s1)
            Yeti UA: Yeti/1.5 (unofficial; +https://github.com/tsvb/applenugs; iOS 26.5)
            Android UA (API, CDN): NugsNet/3.26.724 (Android; 7.1.2; Asus; ASUS_Z01QD; Scale/2.0; en)
            Android UA (resolve): nugsnetAndroid
            Referer (CDN): https://play.nugs.net/
            Note: CDN checks skipped — no resolve returned a stream URL.

            [API identity]
            ✓ 200  Subscriptions · Android UA      Accepted
            ✗ 403  Subscriptions · Yeti UA         HTTP 403
                  body: denied

            [Resolve (UA × tier)]

            [CDN (UA × Referer)]
              skipped — no resolve returned a stream URL

            """)
    }

    private func header() -> ProbeReport.Header {
        ProbeReport.Header(
            date: Date(timeIntervalSince1970: 1_793_966_400), // 2026-11-06T12:00:00Z
            appVersion: "1.5", platform: "iOS 26.5",
            trackTitle: "Away From the Mire", trackArtist: "Billy Strings", trackId: "t1",
            showId: "s1", honest: honest)
    }
}
#endif
