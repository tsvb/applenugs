import Foundation

/// How the app identifies itself to nugs.net — the one place the request
/// headers that carry identity are decided. Every request site reads
/// `NugsIdentity.current`; nothing sets a `User-Agent` or `Referer` by hand.
///
/// `.current` is the honest identity — `Yeti/<version> (unofficial; +<repo>;
/// <platform>)` on the API, the stream resolver and the CDN alike, and no
/// Referer. Phase B of the compliance spec
/// (docs/superpowers/specs/2026-11-06-yeti-compliance-design.md) proved nugs
/// accepts it everywhere (Tim's Duo, 2026-11-07) and that the CDN serves
/// without a Referer. The app used to borrow the official Android app's user
/// agents and the web player's Referer; those strings now exist only in DEBUG
/// builds, as the Network Probe's control (`legacyAndroidForProbe`).
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

    /// What every request says: the honest identity for this build.
    static let current = honestForThisBuild

    #if DEBUG
    /// The identity the app used to send (the official Android app's user
    /// agents, the web player's Referer on the CDN). DEBUG-only: the Network
    /// Probe sends it as the control its honest rows are compared against.
    /// Release builds contain none of these strings.
    static let legacyAndroidForProbe = NugsIdentity(
        userAgentAPI: "NugsNet/3.26.724 (Android; 7.1.2; Asus; ASUS_Z01QD; Scale/2.0; en)",
        userAgentLegacy: "nugsnetAndroid",
        userAgentCDN: "NugsNet/3.26.724 (Android; 7.1.2; Asus; ASUS_Z01QD; Scale/2.0; en)",
        refererCDN: "https://play.nugs.net/")
    #endif

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

    // --- the honest identity -------------------------------------------------

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
