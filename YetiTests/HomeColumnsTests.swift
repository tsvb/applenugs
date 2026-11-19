import XCTest

final class HomeColumnsTests: XCTestCase {

    /// Unmeasured widths answer today's Home, never a guess.
    func testUnmeasuredWidthsAreSingle() {
        for width: CGFloat in [0, -10, .nan, .infinity] {
            XCTAssertEqual(HomeColumns.columns(width: width, hasHero: true), .single, "\(width)")
        }
    }

    /// Portrait iPhones (Home content ≈ 335–400pt) stay one column.
    func testPortraitIPhoneIsSingle() {
        XCTAssertEqual(HomeColumns.columns(width: 335, hasHero: true), .single)
        XCTAssertEqual(HomeColumns.columns(width: 400, hasHero: true), .single)
    }

    /// Nothing loaded means nothing to put in the leading column.
    func testNoHeroIsSingleAtAnyWidth() {
        XCTAssertEqual(HomeColumns.columns(width: 870, hasHero: false), .single)
    }

    func testThresholdEdges() {
        XCTAssertEqual(HomeColumns.columns(width: 559.5, hasHero: true), .single)
        XCTAssertEqual(HomeColumns.columns(width: 560, hasHero: true), .split(leading: 280))
    }

    /// Upright inner display: 629pt → 280 + 24 + 325, about a portrait phone.
    func testDuoUprightLeadingClampsToFloor() {
        XCTAssertEqual(HomeColumns.columns(width: 629, hasHero: true), .split(leading: 280))
    }

    /// Flat inner display: 870pt → a third, inside the range.
    func testDuoFlatLeadingIsAThird() {
        guard case .split(let leading) = HomeColumns.columns(width: 870, hasHero: true) else {
            return XCTFail("expected a split")
        }
        XCTAssertEqual(leading, 870 * 0.36, accuracy: 0.001)
    }

    /// Wider still (Home caps its content at 880, but the policy shouldn't
    /// care), the pack never grows past the range.
    func testLeadingCapsAtCeiling() {
        XCTAssertEqual(HomeColumns.columns(width: 1200, hasHero: true), .split(leading: 320))
    }
}
