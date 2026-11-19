import Foundation

/// Constants for nugs.net's public endpoints and the OAuth client used by its
/// own apps (see NOTICE).
enum NugsConstants {
    static let clientId = "Eg7HuH873H65r5rt325UytR5429"

    static let authURL = URL(string: "https://id.nugs.net/connect/token")!
    static let authorizeURL = URL(string: "https://id.nugs.net/connect/authorize")!
    static let userInfoURL = URL(string: "https://id.nugs.net/connect/userinfo")!
    static let subInfoURL = URL(string: "https://subscriptions.nugs.net/api/v1/me/subscriptions")!
    static let streamAPIBase = "https://streamapi.nugs.net"

    /// Modern REST host for the video browse catalog and live schedule
    /// (`GET /releases/recent`, `/livestreams`). Reuses the same Bearer token as
    /// the legacy streamapi host. Spec open-question: `/releases/*` may live on a
    /// sibling host (`api.nugs.net`); the Phase 0 probe confirmed it sits here, so
    /// every v1 browse path defaults to this base.
    static let catalogV1Base = "https://catalog.nugs.net/api/v1"

    /// OAuth scopes requested by the browser (authorization-code + PKCE) sign-in.
    /// The tokens must carry `nugsnet:legacyapi`, which the streamapi.nugs.net
    /// catalog/stream calls require; sessions created by the old password grant
    /// asked for the identical set, so they keep refreshing unchanged.
    static let oauthScope = "openid profile email nugsnet:api nugsnet:legacyapi offline_access"

    /// Redirect URI for the browser (authorization-code + PKCE) login. This is
    /// the nugs mobile client's registered native callback — id.nugs.net (Duende
    /// IdentityServer) whitelists redirect URIs per client, and this pair (our
    /// public `clientId` + this redirect) is one it already trusts. The authorize
    /// endpoint redirects it to the login page rather than to /error, confirming
    /// the whitelist. ASWebAuthenticationSession captures the callback in-process
    /// by matching `oauthCallbackScheme`, so the scheme is deliberately NOT
    /// registered in Info.plist — that avoids colliding with the official nugs
    /// app's URL scheme if it happens to be installed on the same Mac.
    static let oauthRedirectURI = "nugsnet://oauth2/callback"
    static let oauthCallbackScheme = "nugsnet"

    /// Catalog image paths ("/images/...") resolve against the public CDN
    /// with a /livedownloads prefix. The ?h= query param is a CDN-side
    /// resize directive (pixels).
    static let imageCDNBase = "https://assets-01.nugscdn.net/livedownloads"

    /// Resolve a catalog image path (or pass through an absolute URL).
    static func imageURL(path: String, height: Int = 400) -> URL? {
        if path.lowercased().hasPrefix("http") { return URL(string: path) }
        return URL(string: imageCDNBase + path + "?h=\(height)")
    }

    /// The platformID device tiers bigriver/subPlayer.aspx knows. Each returns
    /// "some" URL whose actual format is identified by URL path patterns
    /// (`.flac16/`, `.alac16/`, `.m3u8`, …); different tiers can return
    /// different formats for the same track. Production asks them one at a
    /// time in `StreamTierPlan.order`; the DEBUG Network Probe asks each.
    static let probePlatforms = [1, 4, 7, 10]
}
