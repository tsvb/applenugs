import XCTest

final class NugsIdentityTests: XCTestCase {

    /// What every production request says: the honest UA on all three
    /// surfaces and no Referer. The version is not pinned — in the host-free
    /// test bundle `Bundle.main` is xctest, not the app.
    func testCurrentIsTheHonestIdentity() {
        let current = NugsIdentity.current
        XCTAssertTrue(current.userAgentAPI.hasPrefix("Yeti/"), current.userAgentAPI)
        XCTAssertTrue(current.userAgentAPI.contains(
            " (unofficial; +https://github.com/tsvb/applenugs; macOS "), current.userAgentAPI)
        XCTAssertTrue(current.userAgentAPI.hasSuffix(")"), current.userAgentAPI)
        XCTAssertEqual(current.userAgentLegacy, current.userAgentAPI)
        XCTAssertEqual(current.userAgentCDN, current.userAgentAPI)
        XCTAssertNil(current.refererCDN)
        XCTAssertFalse(current.userAgentAPI.contains("Android"))
        XCTAssertFalse(current.userAgentAPI.contains("NugsNet"))
    }

    /// The CDN gets the UA and nothing else — no Referer header at all.
    func testCurrentCDNHeadersAreJustTheUA() {
        XCTAssertEqual(NugsIdentity.current.cdnHeaders,
                       ["User-Agent": NugsIdentity.current.userAgentCDN])
    }

    /// No Referer means no header at all, not an empty one.
    func testNilRefererOmitsTheHeader() {
        var request = URLRequest(url: URL(string: "https://example.com/a.flac")!)
        NugsIdentity.current.applyCDN(to: &request)
        XCTAssertNil(request.value(forHTTPHeaderField: "Referer"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"),
                       NugsIdentity.current.userAgentCDN)
    }

    func testApplyCDNSetsTheRefererWhenAnIdentityHasOne() {
        var request = URLRequest(url: URL(string: "https://example.com/a.flac")!)
        NugsIdentity.legacyAndroidForProbe.applyCDN(to: &request)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://play.nugs.net/")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"),
                       NugsIdentity.legacyAndroidForProbe.userAgentCDN)
    }

    /// The probe's control keeps the old strings byte for byte, so its rows
    /// stay comparable with the run that decided Phase B.
    func testLegacyProbeIdentityIsTheOldAndroidOne() {
        let legacy = NugsIdentity.legacyAndroidForProbe
        XCTAssertEqual(legacy.userAgentAPI,
                       "NugsNet/3.26.724 (Android; 7.1.2; Asus; ASUS_Z01QD; Scale/2.0; en)")
        XCTAssertEqual(legacy.userAgentLegacy, "nugsnetAndroid")
        XCTAssertEqual(legacy.userAgentCDN, legacy.userAgentAPI)
        XCTAssertEqual(legacy.refererCDN, "https://play.nugs.net/")
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
