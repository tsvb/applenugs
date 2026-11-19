import AVFoundation
import CryptoKit
import XCTest

/// Integration: real FLAC and ALAC files, sealed, played back through
/// `SealedAssetLoader` by AVFoundation itself — the exact path a downloaded
/// track takes. The audio is generated here (3s of a 440Hz tone), so no
/// binary fixtures are checked in.
final class SealedAssetLoaderTests: XCTestCase {

    private var dir: URL!
    private let key = SymmetricKey(size: .bits256)

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SealedAssetLoaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // --- fixtures -------------------------------------------------------------------

    private enum Container: String, CaseIterable {
        case flac, m4a
        var formatID: AudioFormatID { self == .flac ? kAudioFormatFLAC : kAudioFormatAppleLossless }
    }

    /// `noisy` mixes in pseudo-random noise so the file compresses like real
    /// music (megabytes, many loader requests) instead of a few KiB of tone.
    private func makeAudio(_ container: Container, seconds: Double = 3,
                           noisy: Bool = false) throws -> URL {
        let url = dir.appendingPathComponent("tone.\(container.rawValue)")
        let rate = 44_100.0
        let settings: [String: Any] = [
            AVFormatIDKey: container.formatID,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(rate * seconds)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        var seed: UInt32 = 1
        for channel in 0..<2 {
            let samples = try XCTUnwrap(buffer.floatChannelData)[channel]
            for i in 0..<Int(frames) {
                var noise: Float = 0
                if noisy {
                    seed = seed &* 1_664_525 &+ 1_013_904_223
                    noise = (Float(seed >> 8) / Float(1 << 24) - 0.5) * 0.1
                }
                samples[i] = sinf(Float(i) * 2 * .pi * 440 / Float(rate)) * 0.3 + noise
            }
        }
        try file.write(from: buffer)
        return url
    }

    private func sealedAsset(for plain: URL, key: SymmetricKey? = nil) throws -> SealedURLAsset {
        let sealed = dir.appendingPathComponent("\(UUID().uuidString).yeti")
        try SealedFile.seal(contentsOf: plain, to: sealed, key: self.key,
                            contentType: SealedFile.contentType(forExtension: plain.pathExtension))
        let readKey = key ?? self.key
        return SealedURLAsset(fileURL: sealed, name: sealed.lastPathComponent) { readKey }
    }

    /// Decoded 16-bit PCM for `range` of the asset's audio track.
    private func decodePCM(_ asset: AVAsset, range: CMTimeRange) async throws -> Data {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        reader.timeRange = range
        XCTAssertTrue(reader.startReading(), "\(String(describing: reader.error))")
        var pcm = Data()
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var bytes = Data(count: length)
            _ = bytes.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length,
                                           destination: $0.baseAddress!)
            }
            pcm.append(bytes)
        }
        XCTAssertEqual(reader.status, .completed, "\(String(describing: reader.error))")
        return pcm
    }

    private func seconds(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 44_100) }

    // --- AVFoundation through the loader -----------------------------------------------

    func testSealedAudioLoadsWithThePlaintextDuration() async throws {
        for container in Container.allCases {
            let plain = try makeAudio(container)
            let asset = try sealedAsset(for: plain)
            let (duration, playable) = try await asset.load(.duration, .isPlayable)
            let plainDuration = try await AVURLAsset(url: plain).load(.duration)
            XCTAssertTrue(playable, container.rawValue)
            XCTAssertEqual(duration.seconds, plainDuration.seconds, accuracy: 0.001, container.rawValue)
            XCTAssertEqual(duration.seconds, 3, accuracy: 0.01, container.rawValue)
        }
    }

    /// Decoding a range from the middle exercises byte-range reads (a seek):
    /// the decoded PCM must be bit-identical to decoding the plaintext file.
    func testMidFileRangeDecodesIdenticallyToThePlaintext() async throws {
        for container in Container.allCases {
            let plain = try makeAudio(container)
            let range = CMTimeRange(start: seconds(1.5), duration: seconds(1))
            let fromPlain = try await decodePCM(AVURLAsset(url: plain), range: range)
            let label = container.rawValue
            let fromSealed = try await decodePCM(try sealedAsset(for: plain), range: range)
            XCTAssertGreaterThan(fromSealed.count, 44_100 * 2 * 2 / 2, label)
            XCTAssertEqual(fromSealed, fromPlain, label)
        }
    }

    /// The whole of a multi-megabyte file — many loader requests — must decode
    /// bit-identically to the plaintext.
    func testWholeNoisyFileDecodesIdenticallyToThePlaintext() async throws {
        for container in Container.allCases {
            let label = container.rawValue
            let plain = try makeAudio(container, seconds: 20, noisy: true)
            let size = try XCTUnwrap(try FileManager.default
                .attributesOfItem(atPath: plain.path)[.size] as? Int)
            XCTAssertGreaterThan(size, 1 << 20, "\(label): fixture too small to need many requests")
            let range = CMTimeRange(start: .zero, duration: seconds(20))
            let fromPlain = try await decodePCM(AVURLAsset(url: plain), range: range)
            let fromSealed = try await decodePCM(try sealedAsset(for: plain), range: range)
            XCTAssertEqual(fromSealed.count, fromPlain.count, label)
            XCTAssertTrue(fromSealed == fromPlain, "\(label): PCM differs")
        }
    }

    /// With `isEntireLengthAvailableOnDemand` set, a PLAYING item asks for
    /// small ranges as it needs them. Without it AVPlayer opens with
    /// "everything to the end" and buffers what it's fed — a 10-minute sealed
    /// track then cost ~5x a plain file's memory.
    @MainActor
    func testPlaybackAsksForSmallRangesNotTheWholeFile() async throws {
        for container in Container.allCases {
            let label = container.rawValue
            let asset = try sealedAsset(for: try makeAudio(container, seconds: 20, noisy: true))
            let item = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: item)
            player.volume = 0
            player.play()
            let deadline = Date().addingTimeInterval(10)
            while item.status == .unknown, Date() < deadline {
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertEqual(item.status, .readyToPlay, "\(label): \(String(describing: item.error))")
            try await Task.sleep(for: .seconds(1))
            player.pause()
            let largest = asset.loader.queue.sync { asset.loader.largestRequestedLength }
            XCTAssertGreaterThan(largest, 0, label)
            XCTAssertLessThanOrEqual(largest, 1 << 20, "\(label): largest request \(largest) bytes")
        }
    }

    @MainActor
    func testPlayerItemBecomesReadySeeksAndPlaysToTheEnd() async throws {
        for container in Container.allCases {
            let label = container.rawValue
            let plainURL = try makeAudio(container)
            let item = AVPlayerItem(asset: try sealedAsset(for: plainURL))
            let player = AVPlayer(playerItem: item)
            player.volume = 0
            let deadline = Date().addingTimeInterval(10)
            while item.status == .unknown, Date() < deadline {
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertEqual(item.status, .readyToPlay, "\(label): \(String(describing: item.error))")
            // A seek on an item that never got ready can wait forever.
            guard item.status == .readyToPlay else { continue }
            let finished = await player.seek(to: seconds(2.25), toleranceBefore: .zero,
                                             toleranceAfter: .zero)
            XCTAssertTrue(finished, label)
            XCTAssertEqual(player.currentTime().seconds, 2.25, accuracy: 0.05, label)

            // Play the last stretch: the final chunk must decode and the item
            // must reach the end — not stall short of it, not run past it.
            //
            // "Past it" is judged against the PLAIN file's player item, not a
            // fixed 3.0: AVPlayer gives a 3.0s FLAC an item duration of
            // ~3.03s and keeps advancing currentTime for a moment after the
            // end, for a plain file URL just the same (measured, 2026-11-07).
            // Polling currentTime against 3.0 ± 0.02 was timing-flaky for
            // exactly that reason; the end notification and the item duration
            // are deterministic.
            let ended = expectation(forNotification: AVPlayerItem.didPlayToEndTimeNotification,
                                    object: item)
            _ = await player.seek(to: seconds(2.7), toleranceBefore: .zero, toleranceAfter: .zero)
            player.play()
            await fulfillment(of: [ended], timeout: 5)
            XCTAssertNil(item.error, label)
            XCTAssertGreaterThanOrEqual(player.currentTime().seconds, 2.98, label)
            player.pause()
            let plainItem = AVPlayerItem(asset: AVURLAsset(url: plainURL))
            let plainPlayer = AVPlayer(playerItem: plainItem)
            plainPlayer.volume = 0
            let plainDeadline = Date().addingTimeInterval(10)
            while plainItem.status == .unknown, Date() < plainDeadline {
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertEqual(item.duration.seconds, plainItem.duration.seconds, accuracy: 0.001, label)
        }
    }

    func testWrongKeyIsNotPlayable() async throws {
        let asset = try sealedAsset(for: try makeAudio(.flac), key: SymmetricKey(size: .bits256))
        do {
            let playable = try await asset.load(.isPlayable)
            XCTAssertFalse(playable)
        } catch {
            // Failing to load at all is just as good.
        }
    }

    // --- range math -------------------------------------------------------------------

    func testSpanCoversTheOutstandingRequestClampedToTheResource() {
        // Fresh request.
        XCTAssertEqual(SealedAssetLoader.span(requestedOffset: 100, requestedLength: 50, toEnd: false,
                                              currentOffset: 100, resourceLength: 1000), 100..<150)
        // Part-served request resumes from currentOffset.
        XCTAssertEqual(SealedAssetLoader.span(requestedOffset: 100, requestedLength: 50, toEnd: false,
                                              currentOffset: 130, resourceLength: 1000), 130..<150)
        // "Everything to the end" ignores requestedLength.
        XCTAssertEqual(SealedAssetLoader.span(requestedOffset: 0, requestedLength: 2, toEnd: true,
                                              currentOffset: 0, resourceLength: 1000), 0..<1000)
        // A length past the end is clamped; an offset past it yields nothing.
        XCTAssertEqual(SealedAssetLoader.span(requestedOffset: 900, requestedLength: 500, toEnd: false,
                                              currentOffset: 900, resourceLength: 1000), 900..<1000)
        XCTAssertTrue(SealedAssetLoader.span(requestedOffset: 1200, requestedLength: 10, toEnd: false,
                                             currentOffset: 1200, resourceLength: 1000).isEmpty)
    }

    func testPiecesWalkTheSpanWithoutGapsOrOverlap() {
        var span: Range<Int64> = 5 ..< 1_000_005
        var covered: Int64 = 5
        var pieces = 0
        while let piece = SealedAssetLoader.nextPiece(in: span, pieceSize: 262_144) {
            XCTAssertEqual(piece.lowerBound, covered)
            XCTAssertLessThanOrEqual(piece.count, 262_144)
            covered = piece.upperBound
            span = piece.upperBound ..< span.upperBound
            pieces += 1
        }
        XCTAssertEqual(covered, 1_000_005)
        XCTAssertEqual(pieces, 4)
    }
}
