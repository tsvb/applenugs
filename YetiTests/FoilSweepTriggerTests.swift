import XCTest

final class FoilSweepTriggerTests: XCTestCase {

    // MARK: - a new track while playing fires once

    func testNewTrackWhilePlayingFiresOnce() {
        var trigger = FoilSweepTrigger()
        XCTAssertTrue(trigger.observe(identity: "a", isPlaying: true))
        // Any further report of the same state is not a second sweep.
        XCTAssertFalse(trigger.observe(identity: "a", isPlaying: true))
        XCTAssertFalse(trigger.observe(identity: "a", isPlaying: true))
    }

    func testTrackChangeWhilePlayingFiresForEachNewTrack() {
        var trigger = FoilSweepTrigger()
        XCTAssertTrue(trigger.observe(identity: "a", isPlaying: true))
        XCTAssertTrue(trigger.observe(identity: "b", isPlaying: true))
        XCTAssertTrue(trigger.observe(identity: "c", isPlaying: true))
        XCTAssertEqual(trigger.lastSwept, "c")
    }

    /// A gapless track change can report the new identity before `isPlaying`
    /// settles; it fires when playback is running, not before.
    func testNewTrackWaitsForPlaybackToRun() {
        var trigger = FoilSweepTrigger()
        XCTAssertTrue(trigger.observe(identity: "a", isPlaying: true))
        XCTAssertFalse(trigger.observe(identity: "b", isPlaying: false))
        XCTAssertTrue(trigger.observe(identity: "b", isPlaying: true))
    }

    // MARK: - pause then resume does not fire

    func testPauseThenResumeDoesNotFire() {
        var trigger = FoilSweepTrigger()
        XCTAssertTrue(trigger.observe(identity: "a", isPlaying: true))
        for _ in 0..<10 {
            XCTAssertFalse(trigger.observe(identity: "a", isPlaying: false))
            XCTAssertFalse(trigger.observe(identity: "a", isPlaying: true))
        }
    }

    // MARK: - a launch-restored queue fires on its first play, not at launch

    func testRestoredQueueFiresOnFirstPlayNotAtLaunch() {
        var trigger = FoilSweepTrigger()
        trigger.appear(identity: "restored", isPlaying: false)
        XCTAssertFalse(trigger.observe(identity: "restored", isPlaying: false))
        XCTAssertNil(trigger.lastSwept)
        XCTAssertTrue(trigger.observe(identity: "restored", isPlaying: true))
        XCTAssertFalse(trigger.observe(identity: "restored", isPlaying: true))
    }

    /// The view appearing mid-playback (opening the player during a song, the
    /// Duo rebuilding it on rotation) marks that track as seen — no sweep for a
    /// screen opening — while the next track still sweeps.
    func testAppearingMidPlaybackMarksTheTrackSeen() {
        var trigger = FoilSweepTrigger()
        trigger.appear(identity: "a", isPlaying: true)
        XCTAssertEqual(trigger.lastSwept, "a")
        XCTAssertFalse(trigger.observe(identity: "a", isPlaying: true))
        XCTAssertTrue(trigger.observe(identity: "b", isPlaying: true))
    }

    func testNothingCurrentNeverFires() {
        var trigger = FoilSweepTrigger()
        XCTAssertFalse(trigger.observe(identity: nil, isPlaying: true))
        XCTAssertFalse(trigger.observe(identity: nil, isPlaying: false))
        XCTAssertNil(trigger.lastSwept)
    }

    // MARK: - the same track coming back later

    func testSameTrackBackAfterADifferentTrackPlayedFiresAgain() {
        var trigger = FoilSweepTrigger()
        XCTAssertTrue(trigger.observe(identity: "a", isPlaying: true))
        XCTAssertTrue(trigger.observe(identity: "b", isPlaying: true))
        XCTAssertTrue(trigger.observe(identity: "a", isPlaying: true))
    }

    func testSameTrackRequeuedWithNothingInBetweenDoesNotFire() {
        var trigger = FoilSweepTrigger()
        XCTAssertTrue(trigger.observe(identity: "a", isPlaying: true))
        // Re-queued (a new queue entry for the same catalog track) and played.
        XCTAssertFalse(trigger.observe(identity: "a", isPlaying: false))
        XCTAssertFalse(trigger.observe(identity: "a", isPlaying: true))
    }

    /// "In between" means a different track PLAYED: one that was only current
    /// (skipped past while paused) doesn't reset the memory.
    func testATrackThatWasCurrentButNeverPlayedDoesNotCountAsInBetween() {
        var trigger = FoilSweepTrigger()
        XCTAssertTrue(trigger.observe(identity: "a", isPlaying: true))
        XCTAssertFalse(trigger.observe(identity: "a", isPlaying: false))
        XCTAssertFalse(trigger.observe(identity: "b", isPlaying: false))
        XCTAssertFalse(trigger.observe(identity: "a", isPlaying: false))
        XCTAssertFalse(trigger.observe(identity: "a", isPlaying: true))
    }

    /// An emptied queue (nothing current) is not a different track either:
    /// clearing and re-queueing the same track doesn't re-fire.
    func testClearedQueueThenSameTrackDoesNotFire() {
        var trigger = FoilSweepTrigger()
        XCTAssertTrue(trigger.observe(identity: "a", isPlaying: true))
        XCTAssertFalse(trigger.observe(identity: nil, isPlaying: false))
        XCTAssertEqual(trigger.lastSwept, "a")
        XCTAssertFalse(trigger.observe(identity: "a", isPlaying: true))
    }
}
