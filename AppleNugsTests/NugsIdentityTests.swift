import XCTest

final class NugsIdentityTests: XCTestCase {

    /// The seam must not change a byte of what goes out today.
    func testCurrentIsTodaysIdentity() {
        let current = NugsIdentity.current
        XCTAssertEqual(current.userAgentAPI,
                       "NugsNet/3.26.724 (Android; 7.1.2; Asus; ASUS_Z01QD; Scale/2.0; en)")
        XCTAssertEqual(current.userAgentLegacy, "nugsnetAndroid")
        XCTAssertEqual(current.userAgentCDN, current.userAgentAPI)
        XCTAssertEqual(current.refererCDN, "https://play.nugs.net/")
    }

    func testCurrentCDNHeadersMatchTheOldLiteral() {
        XCTAssertEqual(NugsIdentity.current.cdnHeaders, [
            "Referer": NugsConstants.playerReferer,
            "User-Agent": NugsConstants.mobileUserAgent,
        ])
    }

    /// No Referer means no header at all, not an empty one.
    func testNilRefererOmitsTheHeader() {
        var identity = NugsIdentity.current
        identity.refererCDN = nil
        XCTAssertEqual(identity.cdnHeaders, ["User-Agent": NugsConstants.mobileUserAgent])
        var request = URLRequest(url: URL(string: "https://example.com/a.flac")!)
        identity.applyCDN(to: &request)
        XCTAssertNil(request.value(forHTTPHeaderField: "Referer"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), NugsConstants.mobileUserAgent)
    }

    func testApplyCDNSetsBothHeadersForCurrent() {
        var request = URLRequest(url: URL(string: "https://example.com/a.flac")!)
        NugsIdentity.current.applyCDN(to: &request)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://play.nugs.net/")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), NugsConstants.mobileUserAgent)
    }

    func testHonestUserAgentShape() {
        XCTAssertEqual(
            NugsIdentity.honestUserAgent(version: "1.5", platform: "iOS 26.5"),
            "Yeti/1.5 (unofficial; +https://github.com/tsvb/applenugs; iOS 26.5)")
    }

    func testHonestUserAgentDropsAnEmptyPlatform() {
        XCTAssertEqual(
            NugsIdentity.honestUserAgent(version: "1.5", platform: "  "),
            "Yeti/1.5 (unofficial; +https://github.com/tsvb/applenugs)")
    }

    func testHonestUserAgentNeverHasAnEmptyVersion() {
        XCTAssertTrue(NugsIdentity.honestUserAgent(version: "", platform: "").hasPrefix("Yeti/0 ("))
    }

    func testPlatformDescriptionOmitsAZeroPatch() {
        XCTAssertEqual(NugsIdentity.platformDescription(
            os: "macOS", version: OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)),
            "macOS 27.0")
        XCTAssertEqual(NugsIdentity.platformDescription(
            os: "iOS", version: OperatingSystemVersion(majorVersion: 26, minorVersion: 5, patchVersion: 1)),
            "iOS 26.5.1")
    }

    func testHonestIdentityUsesOneUAEverywhereAndNoReferer() {
        let honest = NugsIdentity.honest(version: "1.5", platform: "iOS 26.5")
        XCTAssertEqual(honest.userAgentAPI, honest.userAgentLegacy)
        XCTAssertEqual(honest.userAgentAPI, honest.userAgentCDN)
        XCTAssertNil(honest.refererCDN)
        XCTAssertFalse(honest.userAgentAPI.contains("Android"))
    }
}
