// sealed-footprint — peak memory of sealed-download playback vs a plain file.
//
// A repeatable, nugs-free measurement of the `yeti-local://` path: it writes
// two 10-minute tracks (FLAC and ALAC, tone + loud noise — 136 / 186 MB, i.e.
// LARGER than a real 10-minute 16/44.1 FLAC of ~60 MB, so a worst case), seals
// them with `SealedFile`, and plays them through an
// AVQueuePlayer exactly the way PlayerService does — track A playing, track B
// parked behind it for the gapless hand-off — sampling the process's
// phys_footprint (the number jetsam uses) every 50 ms.
//
// Build (from the repo root; output goes wherever you like):
//   swiftc -O -swift-version 5 -o /tmp/sealed-footprint scripts/sealed-footprint/main.swift \
//       AppleNugs/Downloads/SealedFile.swift AppleNugs/Downloads/SealedAssetLoader.swift
// Run:
//   /tmp/sealed-footprint gen  <dir>                     # ~1.3 GB of fixtures; delete after
//   /tmp/sealed-footprint play <dir> flac|m4a plain|sealed [early|late]
//
// `early` (default) parks B one second in — streaming's preload timing.
// `late` parks B 20 s before A ends — the deferred LOCAL preload — and reports
// how long B took to become ready (it must be well inside the 20 s lead).
//
// Each `play` prints one line: baseline / peak / final footprint in MB, whether
// playback crossed into B, and B's position 4 s after the crossing.
//
// Results, macOS 27 / Apple silicon, 2026-11-07 (peak MB, A + B preloaded):
//   plain  FLAC 19.3   ALAC 18.6
//   sealed FLAC 134.0  ALAC 105.5   — before isEntireLengthAvailableOnDemand
//   sealed FLAC 19.5   ALAC 20.8    — with it
//   early vs late parking, sealed, with it: FLAC 20.5 / 20.3, ALAC 20.2 / 19.8
//
// Why parking a downloaded successor later buys nothing: AVQueuePlayer
// prepares a queued item on its own schedule. Parked early, B is still
// `.unknown` 8 s later; parked 20 s before A ends, it turns ready only
// ~14.3 s (FLAC) / ~10.7 s (ALAC) after parking — i.e. ~6–9 s before the
// boundary, plain and sealed alike. Until then a parked sealed item holds
// one file handle, one Keychain read and one 64 KiB decrypted chunk.
import AVFoundation
import CryptoKit
import Foundation

func physFootprint() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return kr == KERN_SUCCESS ? info.phys_footprint : 0
}

func mb(_ b: UInt64) -> String { String(format: "%.1f", Double(b) / 1_048_576) }

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: sealed-footprint gen <dir> | play <dir> flac|m4a plain|sealed [early|late]")
    exit(2)
}
let dir = URL(fileURLWithPath: args[2], isDirectory: true)
let keyURL = dir.appendingPathComponent("key.bin")
let trackSeconds = 600.0

func makeAudio(_ ext: String, name: String, seconds: Double, seed: UInt32) throws -> URL {
    let url = dir.appendingPathComponent("\(name).\(ext)")
    let rate = 44_100.0
    let settings: [String: Any] = [
        AVFormatIDKey: ext == "flac" ? kAudioFormatFLAC : kAudioFormatAppleLossless,
        AVSampleRateKey: rate, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16,
    ]
    let file = try AVAudioFile(forWriting: url, settings: settings,
                               commonFormat: .pcmFormatFloat32, interleaved: false)
    let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
    let block = AVAudioFrameCount(rate * 10)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: block)!
    var state = seed
    var written = 0
    let total = Int(rate * seconds)
    while written < total {
        let n = min(Int(block), total - written)
        buffer.frameLength = AVAudioFrameCount(n)
        for ch in 0..<2 {
            let s = buffer.floatChannelData![ch]
            for i in 0..<n {
                state = state &* 1_664_525 &+ 1_013_904_223
                let noise = (Float(state >> 8) / Float(1 << 24) - 0.5) * 0.25
                let t = Float(written + i) / Float(rate)
                s[i] = sinf(t * 2 * .pi * (220 + Float(ch) * 110)) * 0.3 + noise
            }
        }
        try file.write(from: buffer)
        written += n
    }
    return url
}

if args[1] == "gen" {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let key = SymmetricKey(size: .bits256)
    try key.withUnsafeBytes { Data($0) }.write(to: keyURL)
    for ext in ["flac", "m4a"] {
        for (name, seed) in [("a", UInt32(1)), ("b", UInt32(2))] {
            let plain = try makeAudio(ext, name: name, seconds: trackSeconds, seed: seed)
            let sealed = dir.appendingPathComponent("\(name)-\(ext).yeti")
            try SealedFile.seal(contentsOf: plain, to: sealed, key: key,
                                contentType: SealedFile.contentType(forExtension: ext))
            let size = (try FileManager.default.attributesOfItem(atPath: plain.path)[.size] as? Int) ?? 0
            print("wrote \(plain.lastPathComponent) \(size / 1_048_576) MB + sealed copy")
        }
    }
    exit(0)
}

guard args.count >= 5 else { print("play needs <dir> <flac|m4a> <plain|sealed>"); exit(2) }
let ext = args[3]
let sealed = args[4] == "sealed"
let late = args.count > 5 && args[5] == "late"
let key = SymmetricKey(data: try Data(contentsOf: keyURL))

func asset(_ name: String) -> AVURLAsset {
    if sealed {
        let f = dir.appendingPathComponent("\(name)-\(ext).yeti")
        return SealedURLAsset(fileURL: f, name: f.lastPathComponent) { key }
    }
    return AVURLAsset(url: dir.appendingPathComponent("\(name).\(ext)"))
}

nonisolated(unsafe) var peak: UInt64 = 0
let baseline = physFootprint()
let sampler = DispatchSource.makeTimerSource(queue: .global())
sampler.schedule(deadline: .now(), repeating: .milliseconds(50))
sampler.setEventHandler { peak = max(peak, physFootprint()) }
sampler.resume()

func seekTime(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600) }

@MainActor func waitUntil(_ timeout: Double, _ condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
}

@MainActor func run() async {
    let player = AVQueuePlayer(playerItem: AVPlayerItem(asset: asset("a")))
    player.volume = 0
    player.play()
    let b = AVPlayerItem(asset: asset("b"))
    var readyNote = ""
    if late {
        try? await Task.sleep(for: .seconds(8))
        _ = await player.seek(to: seekTime(300), toleranceBefore: .zero, toleranceAfter: .zero)
        try? await Task.sleep(for: .seconds(4))
        _ = await player.seek(to: seekTime(trackSeconds - 25), toleranceBefore: .zero, toleranceAfter: .zero)
        await waitUntil(10) { player.currentTime().seconds >= trackSeconds - 20 }
        let parked = Date()
        player.insert(b, after: player.items().first)
        await waitUntil(20) { b.status != .unknown }
        readyNote = String(format: " B ready %.0f ms after parking (status %d)",
                           Date().timeIntervalSince(parked) * 1000, b.status.rawValue)
        // Skip most of the lead so the run stays short; B is already ready.
        _ = await player.seek(to: seekTime(trackSeconds - 4), toleranceBefore: .zero, toleranceAfter: .zero)
    } else {
        try? await Task.sleep(for: .seconds(1))
        player.insert(b, after: player.items().first)
        try? await Task.sleep(for: .seconds(8))
        readyNote = " B status 8 s after parking: \(b.status.rawValue)"
        _ = await player.seek(to: seekTime(300), toleranceBefore: .zero, toleranceAfter: .zero)
        try? await Task.sleep(for: .seconds(4))
        _ = await player.seek(to: seekTime(trackSeconds - 8), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    // Play across the A→B boundary.
    await waitUntil(20) { player.currentItem === b }
    let crossed = player.currentItem === b
    try? await Task.sleep(for: .seconds(4))
    let t = player.currentTime().seconds
    print("\(ext) \(sealed ? "sealed" : "plain ") \(late ? "late " : "early") baseline \(mb(baseline)) "
          + "peak \(mb(peak)) final \(mb(physFootprint())) MB; crossed=\(crossed) "
          + "tB=\(String(format: "%.1f", t))\(readyNote) err=\(String(describing: player.currentItem?.error))")
    exit(0)
}
Task { @MainActor in await run() }
RunLoop.main.run()
