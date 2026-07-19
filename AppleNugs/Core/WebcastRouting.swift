import Foundation

/// Everything the detail/play layer needs about a webcast, carried from the
/// rail tap so a webcast resolves without a legacy `catalog.container`
/// round-trip (which can't derive an audio SKU). Hashable so it rides in
/// `Route`/`NavigationPath`.
struct WebcastContext: Hashable {
    let id: String
    let title: String?
    let sku: Int
    let access: WebcastAccess
    let isAudio: Bool
    let benefitNotes: String?
    let externalURL: URL?
}

/// What tapping a webcast card should do.
enum WebcastTap: Equatable {
    case openExternal(URL)          // free-video: nugs's own YouTube watch link
    case openWebcast(WebcastContext) // navigate to detail (buy / play / link-out)
}

/// Pure tap decision. A free video with a published external (YouTube) link
/// opens directly ONLY when it has no in-app framing to show; if it carries
/// benefit/donation notes, it routes to the detail screen (which shows those
/// notes plus a Watch-on-YouTube action). Everything else navigates to detail.
func webcastTap(for v: VideoSummary) -> WebcastTap {
    if v.access == .free, let external = v.externalURL, (v.benefitNotes?.isEmpty ?? true) {
        return .openExternal(external)
    }
    return .openWebcast(WebcastContext(
        id: v.id, title: v.title, sku: v.skuId ?? 0, access: v.access,
        isAudio: v.isAudio, benefitNotes: v.benefitNotes, externalURL: v.externalURL))
}

/// The nugs web-player watch/buy page for a webcast. Verified live: an
/// unauthenticated hit redirects to id.nugs.net login, confirming the route is
/// real and auth-gated. Without a sku, fall back to the nugs.net home page.
func nugsWatchURL(access: WebcastAccess, skuId: Int) -> URL? {
    guard skuId > 0 else { return URL(string: "https://www.nugs.net/") }
    return URL(string: "https://play.nugs.net/watch/livestreams/\(access.rawValue)/\(skuId)")
}
