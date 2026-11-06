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

    // --- width-driven control shedding ---------------------------------------

    /// The 32pt chevron lane the pill reserves when it can expand into the panel.
    private let chevronReserve: CGFloat = PillLayout.controlWidth + PillLayout.controlSpacing

    /// iPhone 17 Pro, expanded: 360 - 20 - 156 - 40 - 8 - 32 = 104pt of text,
    /// above the 90pt floor, so nothing is shed.
    func testRoomyExpandedKeepsAllFiveControls() {
        XCTAssertEqual(PillLayout.controls(slot: .expanded, width: 360,
                                           hasLeadingSlot: true, trailingReserve: chevronReserve),
                       [.previous, .back15, .playPause, .forward30, .next])
    }

    /// iPhone Duo's outer display: the vertical tab bar leaves ~290pt while the
    /// placement still reads `.expanded`. Five controls would leave 34pt
    /// ("Aw…"); dropping the skip intervals leaves 98pt.
    func testNarrowExpandedShedsTheSkipIntervals() {
        XCTAssertEqual(PillLayout.controls(slot: .expanded, width: 290,
                                           hasLeadingSlot: true, trailingReserve: chevronReserve),
                       [.previous, .playPause, .next])
    }

    /// At 200pt even three controls leave only 8pt, so previous goes too —
    /// but play/pause and next are the floor and always survive (40pt).
    func testVeryNarrowExpandedFallsBackToPlayPauseAndNext() {
        XCTAssertEqual(PillLayout.controls(slot: .expanded, width: 200,
                                           hasLeadingSlot: true, trailingReserve: chevronReserve),
                       [.playPause, .next])
    }

    /// The floor holds even when nothing fits at all.
    func testPlayPauseAndNextAreNeverShed() {
        XCTAssertEqual(PillLayout.controls(slot: .expanded, width: 40,
                                           hasLeadingSlot: true, trailingReserve: chevronReserve),
                       [.playPause, .next])
    }

    /// Inline is already at the floor; width changes nothing there.
    func testInlineIsUnchangedAtAnyWidth() {
        for width: CGFloat in [0, 150, 284, 600] {
            XCTAssertEqual(PillLayout.controls(slot: .inline, width: width,
                                               hasLeadingSlot: true, trailingReserve: chevronReserve),
                           [.playPause, .next], "width \(width)")
        }
    }

    /// The first layout pass reports 0 before the pill has been measured.
    /// That must NOT read as "no room" and shed everything — render the
    /// slot's full set and let the real width decide on the next pass.
    func testUnmeasuredWidthKeepsTheSlotsFullSet() {
        XCTAssertEqual(PillLayout.controls(slot: .expanded, width: 0,
                                           hasLeadingSlot: true, trailingReserve: chevronReserve),
                       PillLayout.controls(for: .expanded))
    }

    func testNegativeWidthKeepsTheSlotsFullSet() {
        XCTAssertEqual(PillLayout.controls(slot: .expanded, width: -10,
                                           hasLeadingSlot: true, trailingReserve: chevronReserve),
                       PillLayout.controls(for: .expanded))
    }

    func testNaNWidthKeepsTheSlotsFullSet() {
        XCTAssertEqual(PillLayout.controls(slot: .expanded, width: .nan,
                                           hasLeadingSlot: true, trailingReserve: chevronReserve),
                       PillLayout.controls(for: .expanded))
    }

    /// Without the chevron lane (the offline Downloads sheet) the same 290pt
    /// still sheds: 290 - 20 - 156 - 48 = 66pt, under the floor.
    func testNarrowWithoutChevronStillSheds() {
        XCTAssertEqual(PillLayout.controls(slot: .expanded, width: 290,
                                           hasLeadingSlot: true, trailingReserve: 0),
                       [.previous, .playPause, .next])
    }

    // --- progress ring --------------------------------------------------------

    /// The ring is drawn INSIDE the 32pt slot so the slot's footprint — and
    /// therefore `textBudget` — is unchanged. 32 - 2*(2 + 1) = 26.
    func testArtChipShrinksToLeaveRoomForTheRing() {
        XCTAssertEqual(PillLayout.artChipSize(slot: PillLayout.leadingSlotSize),
                       26, accuracy: 0.001)
    }

    /// A slot too small to hold the ring's band must clamp at zero rather
    /// than hand SwiftUI a negative frame.
    func testArtChipSizeNeverGoesNegative() {
        XCTAssertEqual(PillLayout.artChipSize(slot: 4), 0, accuracy: 0.001)
    }

    /// The whole point of the ring's guard: a stream that reports no duration
    /// gets an EMPTY ring, never a full one. A full ring would read as
    /// "finished" — the same defect 11dae49 fixed on the scrub sliders.
    func testProgressIsEmptyWhenDurationIsUnknown() {
        XCTAssertEqual(PillLayout.progressFraction(currentTime: 240, duration: 0),
                       0, accuracy: 0.001)
    }

    func testProgressIsEmptyWhenDurationIsNegative() {
        XCTAssertEqual(PillLayout.progressFraction(currentTime: 240, duration: -1),
                       0, accuracy: 0.001)
    }

    func testProgressTracksPositionThroughTheTrack() {
        XCTAssertEqual(PillLayout.progressFraction(currentTime: 150, duration: 600),
                       0.25, accuracy: 0.001)
    }

    /// A position past the end (a stream whose reported duration lags) clamps
    /// at a full ring instead of overdrawing the arc.
    func testProgressClampsAtOne() {
        XCTAssertEqual(PillLayout.progressFraction(currentTime: 900, duration: 600),
                       1, accuracy: 0.001)
    }

    func testProgressClampsAtZeroForNegativePosition() {
        XCTAssertEqual(PillLayout.progressFraction(currentTime: -5, duration: 600),
                       0, accuracy: 0.001)
    }
}
