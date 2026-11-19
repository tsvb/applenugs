import Foundation

/// Whether a download may play right now. Downloads are for an active
/// subscriber, so the app must have seen nugs confirm the subscription within
/// the last 30 days — after that, offline play waits for a trip online.
/// Pure: the clock is injected.
enum OfflineAccessPolicy {
    static let window: TimeInterval = 30 * 24 * 60 * 60
    /// A stamp this far in the future is a clock that was moved, not a real
    /// verification; it doesn't count (otherwise setting the clock forward
    /// once, verifying, and setting it back would unlock offline play for
    /// years).
    static let futureTolerance: TimeInterval = 24 * 60 * 60

    static let expiredMessage = "Go online to keep listening offline"
    /// The second line under `expiredMessage`, wherever it is shown: why.
    static let expiredDetail =
        "Offline play needs nugs.net to confirm your subscription at least once every 30 days."

    /// The explanatory line to print under a playback error, if it has one.
    /// Only the offline-expiry error does; every other message stands alone.
    static func detail(forError message: String) -> String? {
        message == expiredMessage ? expiredDetail : nil
    }

    static func allowsOfflinePlay(lastVerifiedAt: Date?, now: Date) -> Bool {
        guard let lastVerifiedAt else { return false }
        let age = now.timeIntervalSince(lastVerifiedAt)
        return age >= -futureTolerance && age <= window
    }
}

/// What a FRESH subscription answer does to the offline-play stamp and the
/// session's access flag. Only a fresh answer counts: the access flag stored
/// at sign-in goes stale, so renewing the stamp from it would let a cancelled
/// subscriber keep offline play alive just by browsing. Pure.
enum SubscriptionRecheck {
    enum Outcome: Equatable {
        /// The subscriptions endpoint answered and says content is accessible.
        case active
        /// It answered and says it is not.
        case inactive
        /// No usable answer (network, 5xx, undecodable). Proves nothing.
        case failed
    }

    struct Decision: Equatable {
        /// Write `OfflineVerification` now.
        var stamp: Bool
        /// The session's `isContentAccessible` from here on.
        var isContentAccessible: Bool
    }

    static func decide(_ outcome: Outcome, currentlyAccessible: Bool) -> Decision {
        switch outcome {
        case .active:
            return Decision(stamp: true, isContentAccessible: true)
        case .inactive:
            return Decision(stamp: false, isContentAccessible: false)
        case .failed:
            // A transient failure neither renews offline play nor locks the
            // user out: keep what we had, and let the window run.
            return Decision(stamp: false, isContentAccessible: currentlyAccessible)
        }
    }
}

/// The persisted "last time nugs confirmed an active subscription" stamp.
/// Written by `NugsClient` only after a fresh subscription answer says active
/// (at sign-in, and on each access-token refresh); cleared on logout.
enum OfflineVerification {
    static let defaultsKey = "downloads.lastVerifiedAt"

    static func lastVerifiedAt(in defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: defaultsKey) as? Date
    }

    static func record(_ date: Date, in defaults: UserDefaults = .standard) {
        defaults.set(date, forKey: defaultsKey)
    }

    static func clear(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}
