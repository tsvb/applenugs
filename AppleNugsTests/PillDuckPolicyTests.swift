import XCTest

final class PillDuckPolicyTests: XCTestCase {

    private typealias P = PillDuckPolicy

    /// A long list: 2000pt of scrollable range.
    private func s(_ offset: CGFloat, max: CGFloat = 2000) -> P.Sample {
        P.Sample(offset: offset, maxOffset: max)
    }

    /// Feeds a run of offsets through the policy, pairing each with the last.
    private func run(_ offsets: [CGFloat], from state: P.State = .shown,
                     max: CGFloat = 2000) -> P.State {
        var state = state
        for (a, b) in zip(offsets, offsets.dropFirst()) {
            state = P.step(state, from: s(a, max: max), to: s(b, max: max))
        }
        return state
    }

    private let ducked = P.State(visibility: .ducked, travel: 0)

    // --- sample normalization ----------------------------------------------

    /// Under a navigation bar `contentOffset.y` rests at minus the top inset;
    /// the sample must read that as the top, or the top zone never engages.
    /// The real resting geometry of Home (a ScrollView under the nav bar) on
    /// iPhone Duo's outer display: it rests at the top and doesn't scroll.
    func testScrollViewSampleNormalizesTheTopInset() {
        let sample = P.Sample(contentOffsetY: -82, insetTop: 82, insetBottom: 72,
                              contentHeight: 434, frameHeight: 678)
        XCTAssertEqual(sample.offset, 0)
        XCTAssertEqual(sample.maxOffset, -90)
    }

    /// The real resting geometry of the Artists List (below its filter field,
    /// so no top inset) on the same display.
    func testListSampleCountsItsBottomInset() {
        let sample = P.Sample(contentOffsetY: 0, insetTop: 0, insetBottom: 34,
                              contentHeight: 363, frameHeight: 542)
        XCTAssertEqual(sample.offset, 0)
        XCTAssertEqual(sample.maxOffset, -145)
    }

    /// A long list scrolled 400pt: the range is content + insets − frame.
    func testScrolledSample() {
        let sample = P.Sample(contentOffsetY: 318, insetTop: 82, insetBottom: 72,
                              contentHeight: 1500, frameHeight: 678)
        XCTAssertEqual(sample.offset, 400)
        XCTAssertEqual(sample.maxOffset, 976)
    }

    func testInactiveSampleDoesNotScroll() {
        XCTAssertEqual(P.step(ducked, from: .inactive, to: .inactive), .shown)
    }

    /// The gate switching on (playback starts, or the Duo folds) over a list
    /// already scrolled down delivers `.inactive` → real sample. That jump is
    /// not travel; the pill must not duck the moment it appears.
    func testActivationFromInactiveIsNotTravel() {
        XCTAssertEqual(P.step(.shown, from: .inactive, to: s(500)), .shown)
    }

    /// Content that has only just become scrollable (a page arriving under a
    /// short list) carries no motion from the pass before.
    func testBecomingScrollableIsNotTravel() {
        XCTAssertEqual(P.step(.shown, from: s(0, max: 0), to: s(300)), .shown)
    }

    // --- ducking -------------------------------------------------------------

    func testStartsShown() {
        XCTAssertEqual(P.State.shown.visibility, .shown)
    }

    func testSmallDownwardTravelHolds() {
        let state = run([100, 110, 120])
        XCTAssertEqual(state.visibility, .shown)
        XCTAssertEqual(state.travel, 20)
    }

    func testDownwardTravelPastTheThresholdDucks() {
        XCTAssertEqual(run([100, 112, 124]).visibility, .ducked)
    }

    /// Travel accumulates across many small frames, as real scrolling delivers it.
    func testTravelAccumulatesAcrossFrames() {
        let offsets = stride(from: CGFloat(100), through: 124, by: 2).map { $0 }
        XCTAssertEqual(run(offsets).visibility, .ducked)
    }

    /// A jitter back up starts the count over — a settling finger never ducks.
    func testUpwardJitterResetsDownwardTravel() {
        let state = run([100, 120, 119, 139])
        XCTAssertEqual(state.visibility, .shown)
        XCTAssertEqual(state.travel, 20)
    }

    // --- returning -----------------------------------------------------------

    func testUpwardTravelReturnsADuckedPill() {
        XCTAssertEqual(run([500, 494, 488], from: ducked), .shown)
    }

    func testSmallUpwardTravelKeepsItDucked() {
        let state = run([500, 495], from: ducked)
        XCTAssertEqual(state.visibility, .ducked)
        XCTAssertEqual(state.travel, 5)
    }

    func testDownwardMovementResetsUpwardTravel() {
        let state = run([500, 490, 495, 487], from: ducked)
        XCTAssertEqual(state.visibility, .ducked)
        XCTAssertEqual(state.travel, 8)
    }

    func testReachingTheTopShowsEvenWithoutTravel() {
        XCTAssertEqual(P.step(ducked, from: s(9), to: s(8)), .shown)
    }

    /// The rubber band above the top is still the top.
    func testOverscrollAboveTheTopShows() {
        XCTAssertEqual(P.step(ducked, from: s(-30), to: s(-20)), .shown)
    }

    /// Scrolling down from the very top: the first 8pt are the top zone, and
    /// travel only counts once the content has left it.
    func testLeavingTheTopCountsOnlyTravelPastTheZone() {
        XCTAssertEqual(run([0, 8, 20]).visibility, .shown)
        XCTAssertEqual(run([0, 8, 20, 32]).visibility, .ducked)
    }

    // --- content that doesn't scroll ----------------------------------------

    func testContentThatFitsNeverDucks() {
        XCTAssertEqual(run([0, 30, 60, 90], max: 0), .shown)
        XCTAssertEqual(run([0, 30, 60, 90], max: -40), .shown)
    }

    /// A range shorter than the duck travel can never accumulate enough.
    func testBarelyScrollableContentNeverDucks() {
        XCTAssertEqual(run([0, 10, 20], max: 20).visibility, .shown)
    }

    // --- the bottom edge -----------------------------------------------------

    /// The rubber band past the bottom and its spring back are not travel:
    /// the spring back must not read as "scrolling up" and return the pill.
    func testBottomRubberBandIsNotTravel() {
        XCTAssertEqual(run([2000, 2040, 2060, 2030, 2000], from: ducked), ducked)
    }

    /// A page of results landing under a resting offset grows the range but
    /// moves nothing.
    func testContentGrowingAtTheBottomIsNotTravel() {
        let state = P.step(ducked, from: s(2000, max: 2000), to: s(2000, max: 3000))
        XCTAssertEqual(state, ducked)
    }

    func testNoMovementHoldsState() {
        let partial = P.State(visibility: .shown, travel: 10)
        XCTAssertEqual(P.step(partial, from: s(300), to: s(300)), partial)
    }
}
