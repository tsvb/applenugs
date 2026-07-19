import XCTest

final class WebcastRoutingTests: XCTestCase {

    private func summary(access: WebcastAccess, isAudio: Bool = false,
                         external: URL? = nil, sku: Int? = 42) -> VideoSummary {
        VideoSummary(id: "1", title: "T", artistName: "A", performanceDate: nil,
                     imagePath: nil, isLive: true, eventStart: nil, has4K: false,
                     access: access, isAudio: isAudio, externalURL: external, skuId: sku)
    }

    func testFreeVideoWithLinkOpensExternally() {
        let url = URL(string: "https://www.youtube.com/watch?v=abc")!
        let tap = webcastTap(for: summary(access: .free, external: url))
        XCTAssertEqual(tap, .openExternal(url))
    }

    func testFreeAudioWithoutLinkOpensWebcastToPlay() {
        let tap = webcastTap(for: summary(access: .free, isAudio: true, external: nil, sku: 900))
        guard case let .openWebcast(ctx) = tap else { return XCTFail("expected webcast") }
        XCTAssertEqual(ctx.access, .free)
        XCTAssertTrue(ctx.isAudio)
        XCTAssertEqual(ctx.sku, 900)
    }

    func testPPVOpensWebcastForBuyState() {
        let tap = webcastTap(for: summary(access: .ppv, external: nil))
        guard case let .openWebcast(ctx) = tap else { return XCTFail("expected webcast") }
        XCTAssertEqual(ctx.access, .ppv)
    }

    func testExclusiveOpensWebcastToPlay() {
        let tap = webcastTap(for: summary(access: .exclusive))
        guard case .openWebcast = tap else { return XCTFail("expected webcast") }
    }

    func testWatchURLIsThePlayNugsRoute() {
        XCTAssertEqual(nugsWatchURL(access: .ppv, skuId: 916858)?.absoluteString,
                       "https://play.nugs.net/watch/livestreams/ppv/916858")
    }

    func testWatchURLFallsBackToHomeWithoutSku() {
        XCTAssertEqual(nugsWatchURL(access: .free, skuId: 0)?.absoluteString,
                       "https://www.nugs.net/")
    }
}
