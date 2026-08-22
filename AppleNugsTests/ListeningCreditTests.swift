import XCTest

final class ListeningCreditTests: XCTestCase {

    /// A four-minute track: threshold is min(120, 240) == 120.
    private let normalDuration: Double = 240
    /// A twenty-five-minute jam: threshold is capped at 240.
    private let longDuration: Double = 1_500

    /// Feed `count` ordinary 0.25s ticks.
    private func run(_ credit: inout ListeningCredit,
                     ticks count: Int,
                     duration: Double,
                     isPlaying: Bool = true) {
        for _ in 0..<count {
            credit.tick(delta: 0.25, isPlaying: isPlaying, duration: duration)
        }
    }

    func testANormalTickContributesAQuarterSecond() {
        var credit = ListeningCredit()
        credit.tick(delta: 0.25, isPlaying: true, duration: normalDuration)

        XCTAssertEqual(credit.trackSeconds, 0.25, accuracy: 0.0001)
        XCTAssertEqual(credit.uncommittedSeconds, 0.25, accuracy: 0.0001)
    }

    /// A seek, a wake-from-sleep, or a stall all produce one huge delta. The
    /// clamp caps every one of them without the policy detecting any of them.
    func testATickAboveOneSecondIsClampedToOneSecond() {
        var credit = ListeningCredit()
        credit.tick(delta: 600, isPlaying: true, duration: longDuration)

        XCTAssertEqual(credit.trackSeconds, 1, accuracy: 0.0001)
        XCTAssertEqual(ListeningCredit.maxTickSeconds, 1)
    }

    func testANegativeDeltaContributesNothing() {
        var credit = ListeningCredit()
        credit.tick(delta: -30, isPlaying: true, duration: normalDuration)

        XCTAssertEqual(credit.trackSeconds, 0)
        XCTAssertEqual(credit.uncommittedSeconds, 0)
    }

    func testANonFiniteDeltaContributesNothing() {
        var credit = ListeningCredit()
        credit.tick(delta: .nan, isPlaying: true, duration: normalDuration)
        credit.tick(delta: .infinity, isPlaying: true, duration: normalDuration)

        XCTAssertEqual(credit.trackSeconds, 0)
    }

    func testNoSecondsAccrueWhilePaused() {
        var credit = ListeningCredit()
        run(&credit, ticks: 100, duration: normalDuration, isPlaying: false)

        XCTAssertEqual(credit.trackSeconds, 0)
        XCTAssertFalse(credit.playCredited)
    }

    func testAPlayIsCreditedAtHalfOfDuration() {
        var credit = ListeningCredit()
        XCTAssertEqual(ListeningCredit.playThreshold(duration: normalDuration), 120)

        run(&credit, ticks: 479, duration: normalDuration)   // 119.75s
        XCTAssertFalse(credit.playCredited)

        credit.tick(delta: 0.25, isPlaying: true, duration: normalDuration)  // 120.0s
        XCTAssertTrue(credit.playCredited)
        XCTAssertTrue(credit.uncommittedPlay)
    }

    func testAPlayIsCreditedAtTwoHundredFortySecondsForALongTrack() {
        var credit = ListeningCredit()
        XCTAssertEqual(ListeningCredit.playThreshold(duration: longDuration), 240)

        run(&credit, ticks: 959, duration: longDuration)     // 239.75s
        XCTAssertFalse(credit.playCredited)

        credit.tick(delta: 0.25, isPlaying: true, duration: longDuration)    // 240.0s
        XCTAssertTrue(credit.playCredited)
    }

    /// Because the threshold is measured against LISTENED time rather than
    /// playhead position, scrubbing to the end of a track earns nothing extra.
    func testAPlayIsCreditedAtMostOncePerTrackVisit() {
        var credit = ListeningCredit()
        run(&credit, ticks: 2_000, duration: normalDuration)

        XCTAssertTrue(credit.playCredited)
        let first = credit.flush()
        XCTAssertTrue(first.completedPlay)

        run(&credit, ticks: 2_000, duration: normalDuration)
        XCTAssertFalse(credit.flush().completedPlay)
    }

    func testStartTrackResetsTheAccumulatorAndThePlayLatch() {
        var credit = ListeningCredit()
        run(&credit, ticks: 2_000, duration: normalDuration)
        XCTAssertTrue(credit.playCredited)

        credit.startTrack()

        XCTAssertEqual(credit.trackSeconds, 0)
        XCTAssertEqual(credit.uncommittedSeconds, 0)
        XCTAssertFalse(credit.playCredited)
        XCTAssertFalse(credit.uncommittedPlay)

        run(&credit, ticks: 480, duration: normalDuration)
        XCTAssertTrue(credit.playCredited)   // the new visit can earn its own
    }

    /// A livestream / webcast reports no duration. Same treatment the progress
    /// ring and all six scrub sliders already give `duration <= 0`.
    func testADurationlessStreamCreditsAPlayAtTwoHundredFortySecondsAndNotBefore() {
        XCTAssertEqual(ListeningCredit.playThreshold(duration: 0), 240)
        XCTAssertEqual(ListeningCredit.playThreshold(duration: -1), 240)

        var credit = ListeningCredit()
        run(&credit, ticks: 959, duration: 0)
        XCTAssertFalse(credit.playCredited)

        credit.tick(delta: 0.25, isPlaying: true, duration: 0)
        XCTAssertTrue(credit.playCredited)
    }

    func testFlushHandsOverAndClearsTheUncommittedBatch() {
        var credit = ListeningCredit()
        run(&credit, ticks: 40, duration: normalDuration)    // 10s, no play

        let batch = credit.flush()
        XCTAssertEqual(batch.seconds, 10, accuracy: 0.0001)
        XCTAssertFalse(batch.completedPlay)
        XCTAssertFalse(batch.isEmpty)

        XCTAssertEqual(credit.uncommittedSeconds, 0)
        XCTAssertTrue(credit.flush().isEmpty)                // idempotent
        XCTAssertEqual(credit.trackSeconds, 10, accuracy: 0.0001)  // visit total survives
    }

    func testACommitIsDueEveryThirtySecondsAndImmediatelyOnAnEarnedPlay() {
        XCTAssertEqual(ListeningCredit.commitIntervalSeconds, 30)

        var credit = ListeningCredit()
        run(&credit, ticks: 119, duration: longDuration)     // 29.75s
        XCTAssertFalse(credit.isCommitDue)

        credit.tick(delta: 0.25, isPlaying: true, duration: longDuration)  // 30.0s
        XCTAssertTrue(credit.isCommitDue)
        _ = credit.flush()
        XCTAssertFalse(credit.isCommitDue)

        var earner = ListeningCredit()
        earner.tick(delta: 1, isPlaying: true, duration: 2)   // threshold 1s
        XCTAssertTrue(earner.isCommitDue)
    }
}
