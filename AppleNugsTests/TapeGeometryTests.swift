import XCTest

final class TapeGeometryTests: XCTestCase {

    // --- packRadius ---------------------------------------------------------

    func testPackRadiusOnEmptyReelIsTheHubRadius() {
        XCTAssertEqual(TapeGeometry.packRadius(fraction: 0, hub: 7.5, full: 21),
                       7.5, accuracy: 0.0001)
    }

    func testPackRadiusOnFullReelIsTheFullRadius() {
        XCTAssertEqual(TapeGeometry.packRadius(fraction: 1, hub: 7.5, full: 21),
                       21, accuracy: 0.0001)
    }

    /// Tape winds in a flat spiral, so pack AREA is proportional to tape length
    /// and the radius goes as the square root — a half-full reel is noticeably
    /// fatter than the linear midpoint.
    func testPackRadiusAtHalfIsAreaWeightedNotLinear() {
        let r = TapeGeometry.packRadius(fraction: 0.5, hub: 7.5, full: 21)
        XCTAssertEqual(r, 15.7679, accuracy: 0.001)
        XCTAssertGreaterThan(r, 14.25)   // the linear midpoint
    }

    func testPackRadiusClampsFractionsOutsideUnitRange() {
        XCTAssertEqual(TapeGeometry.packRadius(fraction: -3, hub: 7.5, full: 21),
                       7.5, accuracy: 0.0001)
        XCTAssertEqual(TapeGeometry.packRadius(fraction: 9, hub: 7.5, full: 21),
                       21, accuracy: 0.0001)
    }

    func testPackRadiusTreatsNonFiniteFractionAsEmpty() {
        XCTAssertEqual(TapeGeometry.packRadius(fraction: .nan, hub: 7.5, full: 21),
                       7.5, accuracy: 0.0001)
        XCTAssertEqual(TapeGeometry.packRadius(fraction: .infinity, hub: 7.5, full: 21),
                       7.5, accuracy: 0.0001)
    }

    func testPackRadiusIncreasesMonotonically() {
        var previous = -1.0
        for i in 0...10 {
            let r = TapeGeometry.packRadius(fraction: Double(i) / 10, hub: 7.5, full: 21)
            XCTAssertGreaterThan(r, previous)
            previous = r
        }
    }

    // --- progress -----------------------------------------------------------

    func testProgressIsZeroWhenDurationIsNotPositive() {
        XCTAssertEqual(TapeGeometry.progress(currentTime: 30, duration: 0), 0)
        XCTAssertEqual(TapeGeometry.progress(currentTime: 30, duration: -5), 0)
    }

    func testProgressIsZeroWhenDurationIsNotFinite() {
        XCTAssertEqual(TapeGeometry.progress(currentTime: 30, duration: .infinity), 0)
        XCTAssertEqual(TapeGeometry.progress(currentTime: 30, duration: .nan), 0)
    }

    func testProgressIsZeroWhenCurrentTimeIsNotFinite() {
        XCTAssertEqual(TapeGeometry.progress(currentTime: .nan, duration: 100), 0)
        XCTAssertEqual(TapeGeometry.progress(currentTime: .infinity, duration: 100), 0)
    }

    func testProgressClampsToUnitRange() {
        XCTAssertEqual(TapeGeometry.progress(currentTime: -10, duration: 100), 0)
        XCTAssertEqual(TapeGeometry.progress(currentTime: 250, duration: 100), 1)
    }

    func testProgressReportsTheOrdinaryFraction() {
        XCTAssertEqual(TapeGeometry.progress(currentTime: 25, duration: 100),
                       0.25, accuracy: 0.0001)
    }
}
