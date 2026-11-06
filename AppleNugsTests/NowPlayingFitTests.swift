import XCTest

final class NowPlayingFitTests: XCTestCase {

    private let pad = CGSize(width: 330, height: 260)

    func testRoomToSpareIsFullSize() {
        XCTAssertEqual(NowPlayingFit.scale(available: CGSize(width: 402, height: 800),
                                           natural: pad), 1)
    }

    /// A ~313pt Split View column is narrower than the 330pt control pad.
    func testNarrowColumnScalesByWidth() {
        XCTAssertEqual(NowPlayingFit.scale(available: CGSize(width: 313, height: CGFloat.infinity),
                                           natural: pad),
                       313.0 / 330.0, accuracy: 1e-9)
    }

    func testBothAxesConstrainedTakesTheSmallerRatio() {
        // width 300/330 ≈ 0.909, height 130/260 = 0.5 → height wins.
        XCTAssertEqual(NowPlayingFit.scale(available: CGSize(width: 300, height: 130),
                                           natural: pad),
                       0.5, accuracy: 1e-9)
        // width 165/330 = 0.5, height 234/260 = 0.9 → width wins.
        XCTAssertEqual(NowPlayingFit.scale(available: CGSize(width: 165, height: 234),
                                           natural: pad),
                       0.5, accuracy: 1e-9)
    }

    /// An unmeasured pass (zero, negative or NaN) must never shrink anything.
    func testUnmeasuredAvailableIsFullSize() {
        XCTAssertEqual(NowPlayingFit.scale(available: .zero, natural: pad), 1)
        XCTAssertEqual(NowPlayingFit.scale(available: CGSize(width: -10, height: -10),
                                           natural: pad), 1)
        XCTAssertEqual(NowPlayingFit.scale(available: CGSize(width: CGFloat.nan, height: 0),
                                           natural: pad), 1)
    }

    func testInfiniteHeightConstrainsByWidthOnly() {
        XCTAssertEqual(NowPlayingFit.scale(available: CGSize(width: 165, height: CGFloat.infinity),
                                           natural: pad),
                       0.5, accuracy: 1e-9)
        // A zero height is equally unconstrained (not yet measured).
        XCTAssertEqual(NowPlayingFit.scale(available: CGSize(width: 165, height: 0),
                                           natural: pad),
                       0.5, accuracy: 1e-9)
    }

    func testNeverEnlarges() {
        XCTAssertEqual(NowPlayingFit.scale(available: CGSize(width: 5000, height: 5000),
                                           natural: pad), 1)
        // A degenerate natural size can't divide by zero into a blow-up.
        XCTAssertEqual(NowPlayingFit.scale(available: CGSize(width: 100, height: 100),
                                           natural: .zero), 1)
    }
}
