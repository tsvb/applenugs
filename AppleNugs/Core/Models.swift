import Foundation

// --- persisted session ------------------------------------------------------

struct TokenSet: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}

/// Mirrors subscriptions.nugs.net/api/v1/me/subscriptions.
struct SubInfo: Codable {
    struct Plan: Codable {
        var id: String
        var description: String
    }
    struct Promo: Codable {
        var plan: Plan
    }

    var legacySubscriptionId: String
    var startedAt: String
    var endsAt: String
    var isContentAccessible: Bool
    var plan: Plan?
    var promo: Promo?
}

struct PersistedSession: Codable {
    var tokens: TokenSet
    var userId: String
    var sub: SubInfo
}

/// View of the persisted session adapted for the calls that need stream params.
struct Session {
    var accessToken: String
    var userId: String
    var subscriptionId: String
    var planId: String
    var startStamp: Int64
    var endStamp: Int64
    var planDescription: String
    var isAccessible: Bool

    init(_ state: PersistedSession) throws {
        let sub = state.sub
        guard let plan = sub.promo?.plan ?? sub.plan else {
            throw NugsError.badResponse("subscription has neither plan nor promo")
        }
        accessToken = state.tokens.accessToken
        userId = state.userId
        subscriptionId = sub.legacySubscriptionId
        planId = plan.id
        planDescription = plan.description
        isAccessible = sub.isContentAccessible
        startStamp = Self.parseStamp(sub.startedAt)
        endStamp = Self.parseStamp(sub.endsAt)
    }

    /// nugs returns subscription timestamps as "MM/dd/yyyy HH:mm:ss" UTC.
    private static func parseStamp(_ s: String) -> Int64 {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "MM/dd/yyyy HH:mm:ss"
        return Int64(f.date(from: s)?.timeIntervalSince1970 ?? 0)
    }
}

enum NugsError: LocalizedError {
    case notLoggedIn
    case loginCancelled
    case authFailed(status: Int, body: String)
    case badResponse(String)
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "Not logged in."
        case .loginCancelled:
            return "Login was cancelled."
        case .authFailed(let status, let body):
            return "Login failed (\(status)): \(body)"
        case .badResponse(let why):
            return "Unexpected nugs response: \(why)"
        case .http(let code):
            return "nugs returned HTTP \(code)."
        }
    }
}

// --- streaming ----------------------------------------------------------------

enum AudioFormat: String {
    case unknown, alac16, flac16, mqa24, s360ra, aac150, hls

    /// Identify the actual byte format of a subPlayer URL from its path patterns.
    static func identify(_ url: String) -> AudioFormat {
        let u = url.lowercased()
        if u.contains(".flac16/") { return .flac16 }
        if u.contains(".mqa24/") { return .mqa24 }
        if u.contains(".alac16/") { return .alac16 }
        if u.contains(".s360/") { return .s360ra }
        if u.contains(".aac150/") { return .aac150 }
        if u.contains(".m3u8") { return .hls }
        // Fall back to extension sniffing for unknown patterns.
        if u.contains(".flac") { return .flac16 }
        if u.contains(".m4a") { return .aac150 }
        return .unknown
    }

    var qualityLabel: String {
        switch self {
        case .flac16: return "FLAC 16-bit lossless"
        case .mqa24: return "MQA 24-bit (FLAC)"
        case .alac16: return "ALAC 16-bit lossless"
        case .s360ra: return "Sony 360 Reality Audio"
        case .aac150: return "AAC ~150 kbps"
        case .hls: return "HLS adaptive"
        case .unknown: return "Unknown"
        }
    }

    /// Short badge text for the transport bar.
    var badge: String {
        switch self {
        case .flac16: return "FLAC"
        case .mqa24: return "MQA"
        case .alac16: return "ALAC"
        case .s360ra: return "360RA"
        case .aac150: return "AAC"
        case .hls: return "HLS"
        case .unknown: return "?"
        }
    }

    /// Native playback preference (lower is better). Unlike the web port we
    /// put ALAC first — it ships in an MP4 container, AVFoundation's home
    /// turf — and HLS stays playable (AVPlayer speaks it natively; the
    /// browser build had to punt on it).
    var preferenceRank: Int {
        switch self {
        case .alac16: return 0
        case .flac16: return 1
        case .mqa24: return 2
        case .aac150: return 3
        case .hls: return 4
        case .s360ra: return 5
        case .unknown: return 6
        }
    }

    /// Known bit depth implied by the format tier, used when the decoder
    /// doesn't report one (compressed formats report 0 bits per channel).
    var impliedBitDepth: Int? {
        switch self {
        case .flac16, .alac16: return 16
        case .mqa24: return 24
        default: return nil
        }
    }
}

struct StreamPick: Equatable {
    var url: String
    var platformId: Int
    var format: AudioFormat
}
