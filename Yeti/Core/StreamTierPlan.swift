import Foundation

/// Which `platformID` tier the stream resolver (`bigriver/subPlayer.aspx`) is
/// asked for, in what order, and when to stop asking.
///
/// The app used to ask all four tiers at once for every track. The Phase B
/// probe (docs/superpowers/specs/2026-11-06-yeti-compliance-design.md) showed
/// tier 7 serves ALAC 16, the format the player prefers, so a track now costs
/// ONE resolve: tier 7 first, and only if it has no usable stream the other
/// tiers one at a time, stopping at the first usable one. Never in parallel.
///
/// Pure Foundation, compiled into AppleNugsTests. The networking loop that
/// drives it lives in `NugsClient.resolveStreams`.
enum StreamTierPlan {
    /// The tier asked first: ALAC 16 on the probe's track.
    static let firstTier = 7

    /// Tier 7, then the rest in the preference order the old parallel fan-out
    /// produced (formats ranked by `AudioFormat.preferenceRank`, ties to the
    /// lowest tier): 1 (FLAC 16), 4 (MQA 24), 10 (MQA 24).
    static let order: [Int] =
        [firstTier] + NugsConstants.probePlatforms.filter { $0 != firstTier }

    /// What a resolved stream is for. Downloads need a file, so an HLS
    /// playlist that would satisfy playback has to fall through for them.
    enum Purpose: Sendable, Hashable {
        case playback, download
    }

    /// One tier's answer.
    enum Outcome: Sendable, Equatable {
        /// 2xx with a stream link.
        case stream(StreamPick)
        /// 2xx without a link: nugs has no stream on this tier. A real answer,
        /// so it is cached like a stream and the tier isn't asked again soon.
        case noStream
        /// Transport error or non-2xx. Not cached: it may be transient.
        case failed

        var isCacheable: Bool {
            switch self {
            case .stream, .noStream: return true
            case .failed: return false
            }
        }
    }

    /// The resolver's link, classified. An empty link is no link.
    static func outcome(link: String?, platformId: Int) -> Outcome {
        guard let link, !link.isEmpty else { return .noStream }
        return .stream(StreamPick(url: link, platformId: platformId, format: .identify(link)))
    }

    /// Formats the player is confident it can play. Exhaustive on purpose:
    /// a new `AudioFormat` case should fail to compile here and force a call.
    /// 360 Reality Audio and unidentified URLs are not refused outright —
    /// they are kept as a last resort (see `next`), as the fan-out ranked them.
    static func isPlayable(_ format: AudioFormat) -> Bool {
        switch format {
        case .alac16, .flac16, .mqa24, .aac150, .hls:
            return true
        case .s360ra, .unknown:
            return false
        }
    }

    /// Whether a pick ends the walk for this purpose.
    static func accepts(_ pick: StreamPick, for purpose: Purpose) -> Bool {
        switch purpose {
        case .playback: return isPlayable(pick.format)
        case .download: return isPlayable(pick.format) && pick.isDownloadable
        }
    }

    enum Step: Equatable {
        /// Ask the resolver for this tier next.
        case request(tier: Int)
        /// Stop. One accepted pick, or — when no tier had one — whatever
        /// streams the walk did find, best first (possibly none).
        case done([StreamPick])
    }

    /// The walk, one step at a time. `known` holds every tier answered so far
    /// (cached or just requested); `skipping` holds tiers the player has seen
    /// fail and must not be handed again. Tiers are visited in `order`; the
    /// first unanswered one is the next request, so requests are strictly
    /// sequential and stop at the first accepted pick.
    static func next(known: [Int: Outcome], skipping: Set<Int> = [],
                     purpose: Purpose, order: [Int] = order) -> Step {
        var leftovers: [StreamPick] = []
        for tier in order where !skipping.contains(tier) {
            guard let outcome = known[tier] else { return .request(tier: tier) }
            if case .stream(let pick) = outcome {
                if accepts(pick, for: purpose) { return .done([pick]) }
                leftovers.append(pick)
            }
        }
        return .done(lastResort(leftovers))
    }

    /// Distinct formats (first tier in walk order wins), best rank first.
    static func lastResort(_ picks: [StreamPick]) -> [StreamPick] {
        var seen = Set<AudioFormat>()
        let unique = picks.filter { seen.insert($0.format).inserted }
        return unique.enumerated()
            .sorted { a, b in
                let ra = a.element.format.preferenceRank, rb = b.element.format.preferenceRank
                return ra != rb ? ra < rb : a.offset < b.offset
            }
            .map(\.element)
    }
}
