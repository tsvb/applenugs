import XCTest

final class NowPlayingDismissDragTests: XCTestCase {

    private typealias Drag = NowPlayingDismissDrag

    // MARK: tracks

    func testStraightDownTracks() {
        XCTAssertTrue(Drag.tracks(translation: CGSize(width: 0, height: 40)))
        XCTAssertTrue(Drag.tracks(translation: CGSize(width: -20, height: 40)))
    }

    func testHorizontalDragNeverTracks() {
        XCTAssertFalse(Drag.tracks(translation: CGSize(width: 200, height: 0)))
        // A scrub that drifts a little downward still isn't a dismiss.
        XCTAssertFalse(Drag.tracks(translation: CGSize(width: 200, height: 10)))
        // Just under 1.5× dominance.
        XCTAssertFalse(Drag.tracks(translation: CGSize(width: 40, height: 59)))
    }

    func testUpwardDragNeverTracks() {
        XCTAssertFalse(Drag.tracks(translation: CGSize(width: 0, height: -80)))
    }

    func testZeroAndNonFiniteNeverTrack() {
        XCTAssertFalse(Drag.tracks(translation: .zero))
        XCTAssertFalse(Drag.tracks(translation: CGSize(width: CGFloat.nan, height: 80)))
        XCTAssertFalse(Drag.tracks(translation: CGSize(width: 0, height: CGFloat.nan)))
        XCTAssertFalse(Drag.tracks(translation: CGSize(width: 0, height: CGFloat.infinity)))
    }

    // MARK: offset

    func testOffsetFollowsFingerDownOneToOne() {
        XCTAssertEqual(Drag.offset(for: CGSize(width: 0, height: 73)), 73)
        XCTAssertEqual(Drag.offset(for: CGSize(width: 10, height: 200)), 200)
    }

    func testHorizontalAndUpwardOffsetIsZero() {
        XCTAssertEqual(Drag.offset(for: CGSize(width: 200, height: 10)), 0)
        XCTAssertEqual(Drag.offset(for: CGSize(width: 0, height: -80)), 0)
    }

    func testOffsetIsNaNAndZeroSafe() {
        XCTAssertEqual(Drag.offset(for: .zero), 0)
        XCTAssertEqual(Drag.offset(for: CGSize(width: CGFloat.nan, height: CGFloat.nan)), 0)
        XCTAssertEqual(Drag.offset(for: CGSize(width: 0, height: 50), phase: .tracking), 50)
        XCTAssertEqual(Drag.offset(for: CGSize(width: 0, height: CGFloat.nan), phase: .tracking), 0)
    }

    // MARK: the latch

    func testFirstSampleDecidesAndTheDecisionSticks() {
        let down = Drag.phase(after: .undecided, translation: CGSize(width: 0, height: 20))
        XCTAssertEqual(down, .tracking)
        // Drifting sideways later keeps tracking — and keeps following.
        let drifted = CGSize(width: 150, height: 90)
        XCTAssertEqual(Drag.phase(after: down, translation: drifted), .tracking)
        XCTAssertEqual(Drag.offset(for: drifted, phase: .tracking), 90)
        // Dragging back up past the start clamps at the resting place.
        XCTAssertEqual(Drag.offset(for: CGSize(width: 0, height: -30), phase: .tracking), 0)

        let sideways = Drag.phase(after: .undecided, translation: CGSize(width: 20, height: 2))
        XCTAssertEqual(sideways, .ignored)
        // A scrub that later curls downward never moves the player.
        let curled = CGSize(width: 30, height: 250)
        XCTAssertEqual(Drag.phase(after: sideways, translation: curled), .ignored)
        XCTAssertEqual(Drag.offset(for: curled, phase: .ignored), 0)
        XCTAssertFalse(Drag.shouldDismiss(translation: curled,
                                          predictedEnd: CGSize(width: 30, height: 600),
                                          phase: .ignored))
    }

    func testZeroOrNonFiniteFirstSampleLeavesItUndecided() {
        XCTAssertEqual(Drag.phase(after: .undecided, translation: .zero), .undecided)
        XCTAssertEqual(Drag.phase(after: .undecided,
                                  translation: CGSize(width: CGFloat.nan, height: 40)), .undecided)
        XCTAssertEqual(Drag.offset(for: CGSize(width: 0, height: 40), phase: .undecided), 0)
    }

    // MARK: shouldDismiss

    func testSmallDragSpringsBack() {
        XCTAssertFalse(Drag.shouldDismiss(translation: CGSize(width: 0, height: 60),
                                          predictedEnd: CGSize(width: 0, height: 80)))
    }

    func testLongDragDismisses() {
        XCTAssertTrue(Drag.shouldDismiss(translation: CGSize(width: 0, height: 140),
                                         predictedEnd: CGSize(width: 0, height: 150)))
    }

    func testFastShortFlickDismisses() {
        XCTAssertTrue(Drag.shouldDismiss(translation: CGSize(width: 0, height: 40),
                                         predictedEnd: CGSize(width: 0, height: 420)))
    }

    func testLongDragFlungBackUpSpringsBack() {
        XCTAssertFalse(Drag.shouldDismiss(translation: CGSize(width: 0, height: 160),
                                          predictedEnd: CGSize(width: 0, height: 20)))
    }

    func testHorizontalDragNeverDismisses() {
        XCTAssertFalse(Drag.shouldDismiss(translation: CGSize(width: 300, height: 130),
                                          predictedEnd: CGSize(width: 600, height: 400)))
    }

    func testUpwardDragNeverDismisses() {
        XCTAssertFalse(Drag.shouldDismiss(translation: CGSize(width: 0, height: -200),
                                          predictedEnd: CGSize(width: 0, height: -500)))
    }

    func testDismissIsNaNAndZeroSafe() {
        XCTAssertFalse(Drag.shouldDismiss(translation: .zero, predictedEnd: .zero))
        XCTAssertFalse(Drag.shouldDismiss(translation: CGSize(width: 0, height: 200),
                                          predictedEnd: CGSize(width: 0, height: CGFloat.nan),
                                          phase: .tracking))
        XCTAssertFalse(Drag.shouldDismiss(translation: CGSize(width: 0, height: CGFloat.nan),
                                          predictedEnd: CGSize(width: 0, height: 500),
                                          phase: .tracking))
    }
}
