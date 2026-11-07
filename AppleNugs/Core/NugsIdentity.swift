import Foundation

/// How the app identifies itself to nugs.net — the one place the request
/// headers that carry identity are decided. Every request site reads
/// `NugsIdentity.current`; nothing sets a `User-Agent` or `Referer` by hand.
///
/// `.current` is today's identity, byte for byte: the official Android app's
/// user agents and the web player's Referer on the CDN. Phase B of the
/// compliance spec (docs/superpowers/specs/2026-11-06-yeti-compliance-design.md)
/// probes what nugs accepts from an honest identity before anything here
/// changes; the DEBUG Network Probe screen builds alternatives from `.honest`.
///
/// Pure Foundation, compiled into AppleNugsTests.
struct NugsIdentity: Sendable, Equatable {
    /// JSON hosts: id.nugs.net (token, userinfo), subscriptions.nugs.net, and
    /// the streamapi/catalog JSON endpoints.
    var userAgentAPI: String
    /// The legacy bigriver stream resolvers (`subPlayer.aspx`).
    var userAgentLegacy: String
    /// The media CDN: AVURLAsset playback (audio + video) and downloads.
    var userAgentCDN: String
    /// Sent to the CDN only when non-nil. An honest identity omits the header
    /// entirely rather than sending an empty one — those are different requests.
    var refererCDN: String?

    /// Today's identity. Changing this changes what every request says.
    static let current = NugsIdentity(
        userAgentAPI: NugsConstants.mobileUserAgent,
        userAgentLegacy: NugsConstants.legacyUserAgent,
        userAgentCDN: NugsConstants.mobileUserAgent,
        refererCDN: NugsConstants.playerReferer)

    /// Header fields for a CDN request (AVURLAsset's
    /// `AVURLAssetHTTPHeaderFieldsKey`, or a URLRequest).
    var cdnHeaders: [String: String] {
        var headers = ["User-Agent": userAgentCDN]
        if let refererCDN { headers["Referer"] = refererCDN }
        return headers
    }

    /// Applies `cdnHeaders` to a request.
    func applyCDN(to request: inout URLRequest) {
        for (field, value) in cdnHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
    }

    // --- the honest alternative ----------------------------------------------

    static let projectURL = "https://github.com/tsvb/applenugs"

    /// `Yeti/<version> (unofficial; +<project URL>; <platform>)` — names the
    /// app, says it is unofficial, and gives nugs somewhere to look. The
    /// platform segment is dropped when empty.
    static func honestUserAgent(version: String, platform: String) -> String {
        var parts = ["unofficial", "+\(projectURL)"]
        let platform = platform.trimmingCharacters(in: .whitespaces)
        if !platform.isEmpty { parts.append(platform) }
        let version = version.isEmpty ? "0" : version
        return "Yeti/\(version) (\(parts.joined(separator: "; ")))"
    }

    /// "iOS 26.5" / "macOS 27.0" — patch component only when non-zero.
    static func platformDescription(os: String, version: OperatingSystemVersion) -> String {
        var v = "\(version.majorVersion).\(version.minorVersion)"
        if version.patchVersion != 0 { v += ".\(version.patchVersion)" }
        return "\(os) \(v)"
    }

    /// The same honest UA on every surface, and no Referer.
    static func honest(version: String, platform: String) -> NugsIdentity {
        let ua = honestUserAgent(version: version, platform: platform)
        return NugsIdentity(userAgentAPI: ua, userAgentLegacy: ua,
                            userAgentCDN: ua, refererCDN: nil)
    }

    /// `honest(...)` filled in from the running app and OS. Not unit-tested:
    /// in the host-free test bundle `Bundle.main` is xctest, not the app.
    static var honestForThisBuild: NugsIdentity {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? ""
        #if os(iOS)
        let os = "iOS"
        #else
        let os = "macOS"
        #endif
        let platform = platformDescription(
            os: os, version: ProcessInfo.processInfo.operatingSystemVersion)
        return honest(version: version, platform: platform)
    }
}
