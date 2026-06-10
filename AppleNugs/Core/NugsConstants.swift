import Foundation

/// Constants from the unofficial nugs.net mobile/web clients.
/// Sourced from Sorrow446/Nugs-Downloader and Dniel97/orpheusdl-nugs.
enum NugsConstants {
    static let clientId = "Eg7HuH873H65r5rt325UytR5429"

    static let mobileUserAgent =
        "NugsNet/3.26.724 (Android; 7.1.2; Asus; ASUS_Z01QD; Scale/2.0; en)"
    static let legacyUserAgent = "nugsnetAndroid"
    static let playerReferer = "https://play.nugs.net/"

    static let authURL = URL(string: "https://id.nugs.net/connect/token")!
    static let userInfoURL = URL(string: "https://id.nugs.net/connect/userinfo")!
    static let subInfoURL = URL(string: "https://subscriptions.nugs.net/api/v1/me/subscriptions")!
    static let streamAPIBase = "https://streamapi.nugs.net"

    /// Catalog image paths ("/images/...") resolve against the public CDN
    /// with a /livedownloads prefix. The ?h= query param is a CDN-side
    /// resize directive (pixels).
    static let imageCDNBase = "https://assets-01.nugscdn.net/livedownloads"

    /// platformID device tiers probed against bigriver/subPlayer.aspx.
    /// Each returns "some" URL whose actual format is identified by URL
    /// path patterns (`.flac16/`, `.alac16/`, `.m3u8`, …); different tiers
    /// can return different formats for the same track.
    static let probePlatforms = [1, 4, 7, 10]
}
