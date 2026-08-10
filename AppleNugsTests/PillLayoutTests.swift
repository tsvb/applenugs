import XCTest

final class PillLayoutTests: XCTestCase {

    // --- slot resolution ----------------------------------------------------

    /// `tabViewBottomAccessoryPlacement` is nil whenever the pill renders
    /// outside a tab accessory (the offline Downloads sheet does this on
    /// purpose). nil must behave like the roomy case, never crash.
    func testNilPlacementResolvesToExpanded() {
        XCTAssertEqual(PillLayout.slot(isInline: nil), .expanded)
    }

    func testInlineFlagResolvesToInline() {
        XCTAssertEqual(PillLayout.slot(isInline: true), .inline)
    }

    func testExpandedFlagResolvesToExpanded() {
        XCTAssertEqual(PillLayout.slot(isInline: false), .expanded)
    }

    // --- control sets -------------------------------------------------------

    func testExpandedCarriesAllFiveControlsInTransportOrder() {
        XCTAssertEqual(PillLayout.controls(for: .expanded),
                       [.previous, .back15, .playPause, .forward30, .next])
    }

    /// 284pt cannot seat five controls; the skip intervals are the ones that go.
    func testInlineKeepsOnlyPlayPauseAndNext() {
        XCTAssertEqual(PillLayout.controls(for: .inline), [.playPause, .next])
    }

    func testInlineDropsTheArtistLine() {
        XCTAssertTrue(PillLayout.showsArtistLine(for: .expanded))
        XCTAssertFalse(PillLayout.showsArtistLine(for: .inline))
    }

    // --- text budget --------------------------------------------------------

    /// Measured: 360pt accessory, 20pt padding, 156pt of controls, 40pt of
    /// leading slot + gap, 8pt trailing gap => 136pt for text.
    func testExpandedTextBudgetWithLeadingSlot() {
        XCTAssertEqual(PillLayout.textBudget(width: 360, slot: .expanded, hasLeadingSlot: true),
                       136, accuracy: 0.001)
    }

    /// Dropping the 32pt slot and its gap hands the 40pt back to the text.
    func testExpandedTextBudgetWithoutLeadingSlot() {
        XCTAssertEqual(PillLayout.textBudget(width: 360, slot: .expanded, hasLeadingSlot: false),
                       176, accuracy: 0.001)
    }

    /// Inline is 76pt narrower but sheds three controls, so text actually gains.
    func testInlineTextBudget() {
        XCTAssertEqual(PillLayout.textBudget(width: 284, slot: .inline, hasLeadingSlot: true),
                       156, accuracy: 0.001)
    }

    /// A pathologically narrow container must clamp at zero, never go negative.
    func testTextBudgetNeverGoesNegative() {
        XCTAssertEqual(PillLayout.textBudget(width: 40, slot: .expanded, hasLeadingSlot: true),
                       0, accuracy: 0.001)
    }

    // --- seek hit inset -------------------------------------------------------

    /// Expanded, chevron showing: 10pt padding + chevron lane (28+4) + five
    /// controls (5*28 + 4*4 = 156) = 198.
    func testControlsTrailingInsetExpandedWithChevron() {
        XCTAssertEqual(
            PillLayout.controlsTrailingInset(for: .expanded, includesChevron: true),
            198, accuracy: 0.001)
    }

    /// No chevron: drop its 32pt lane, keep the five controls.
    func testControlsTrailingInsetExpandedWithoutChevron() {
        XCTAssertEqual(
            PillLayout.controlsTrailingInset(for: .expanded, includesChevron: false),
            166, accuracy: 0.001)
    }

    /// Inline sheds three controls: 10 + 32 (chevron) + (2*28 + 4) = 102.
    func testControlsTrailingInsetInlineWithChevron() {
        XCTAssertEqual(
            PillLayout.controlsTrailingInset(for: .inline, includesChevron: true),
            102, accuracy: 0.001)
    }
}
