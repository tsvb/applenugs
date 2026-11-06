import XCTest

final class NowPlayingColumnsTests: XCTestCase {

    private typealias Columns = NowPlayingColumns

    /// Compact is always the player alone, whatever the aspect.
    func testCompactIsAlwaysSingle() {
        for size in [CGSize(width: 402, height: 874),   // iPhone 17 Pro
                     CGSize(width: 874, height: 402),
                     CGSize(width: 433, height: 635)] { // a Duo Split View half
            for arrange in [true, false] {
                XCTAssertEqual(Columns.layout(size: size, regular: false, supportsArrangement: arrange),
                               .single, "\(size) arrange=\(arrange)")
            }
        }
    }

    /// The Duo's inner display unfolded flat keeps the fold-aware arrangement.
    func testRegularWideIsArrangement() {
        XCTAssertEqual(Columns.layout(size: CGSize(width: 867, height: 635),
                                      regular: true, supportsArrangement: true),
                       .arrangement)
    }

    /// Without `ArrangementView` (pre-27.1) a wide regular canvas takes columns.
    func testRegularWideWithoutArrangementIsColumns() {
        XCTAssertEqual(Columns.layout(size: CGSize(width: 867, height: 635),
                                      regular: true, supportsArrangement: false),
                       .columns(queueWidth: Columns.maxQueueWidth))
    }

    /// The Duo's inner display held upright: ~535pt wide.
    func testRegularTallIsColumnsWithThePlayerAtItsMinimum() {
        let size = CGSize(width: 535, height: 760)
        XCTAssertEqual(Columns.layout(size: size, regular: true, supportsArrangement: true),
                       .columns(queueWidth: 235))
        guard case .columns(let queue) = Columns.layout(size: size, regular: true,
                                                        supportsArrangement: true) else {
            return XCTFail("expected columns")
        }
        XCTAssertGreaterThanOrEqual(size.width - queue, Columns.minPlayerWidth)
    }

    /// A square canvas can't split horizontally in the arrangement either.
    func testSquareIsColumns() {
        XCTAssertEqual(Columns.layout(size: CGSize(width: 600, height: 600),
                                      regular: true, supportsArrangement: true),
                       .columns(queueWidth: 260))
    }

    func testTooNarrowRegularIsSingle() {
        XCTAssertEqual(Columns.layout(size: CGSize(width: 519, height: 800),
                                      regular: true, supportsArrangement: true),
                       .single)
        XCTAssertEqual(Columns.layout(size: CGSize(width: 520, height: 800),
                                      regular: true, supportsArrangement: true),
                       .columns(queueWidth: 220))
    }

    /// Wider canvases give the extra width to the player once the queue is at its cap.
    func testQueueWidthClampsAndThePlayerTakesTheRest() {
        XCTAssertNil(Columns.queueWidth(forWidth: 400))
        XCTAssertEqual(Columns.queueWidth(forWidth: 520), 220)
        XCTAssertEqual(Columns.queueWidth(forWidth: 545), 245)
        XCTAssertEqual(Columns.queueWidth(forWidth: 560), 260)
        XCTAssertEqual(Columns.queueWidth(forWidth: 1000), 260)
    }

    /// An unmeasured or degenerate size never splits.
    func testUnmeasuredIsSingle() {
        for size in [CGSize.zero,
                     CGSize(width: CGFloat.nan, height: 800),
                     CGSize(width: CGFloat.infinity, height: 800),
                     CGSize(width: -535, height: 760)] {
            XCTAssertEqual(Columns.layout(size: size, regular: true, supportsArrangement: true),
                           .single, "\(size)")
        }
    }
}
