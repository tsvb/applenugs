# AppleNugs

[![CI](https://github.com/tsvb/applenugs/actions/workflows/ci.yml/badge.svg)](https://github.com/tsvb/applenugs/actions/workflows/ci.yml)

A native macOS client for [nugs.net](https://nugs.net), written in
Swift/SwiftUI. Fast search, a real queue,
gapless playback, video, a Winamp-style artist library, and keyboard control
over your own nugs.net subscription.

> [!IMPORTANT]
> **Unofficial and unaffiliated.** AppleNugs is an independent client. It is
> not affiliated with, authorized, sponsored, or endorsed by nugs.net. It is
> for **personal use against your own nugs.net subscription only**: it streams
> the same content the official apps do, downloads nothing for offline use,
> redistributes nothing, and circumvents no DRM. You are responsible for
> complying with the [nugs.net Terms of Service](https://nugs.net).

## Features

- **Sign in your way.** Browser-based SSO (Apple / Google / Facebook / SiriusXM)
  via `ASWebAuthenticationSession` with OAuth2 Authorization Code + PKCE, *or*
  classic email + password. Tokens persist locally and refresh automatically.
- **Gapless audio.** The next track is resolved and parked in an
  `AVQueuePlayer` while the current one plays, so live-show segues flow. ALAC
  is preferred (lossless in MP4); FLAC, MQA, AAC, and HLS all play, with
  automatic fallthrough if a format fails.
- **Video.** Continue Watching with resume positions, Live & Upcoming, a paged
  on-demand grid, chapters, and a quality cap — audio and video share one
  playback arbiter so they never talk over each other.
- **Artist library.** Each artist opens as a Winamp-style expandable outline —
  Albums, Videos, and Shows as collapsible nodes (Videos and Shows grouped by
  year) rendered as dense, scannable rows under a VU + LCD-style header, instead
  of a wall of posters. Rows page in on scroll and lazily build per year, so a
  catalog of hundreds stays fast.
- **Favorites.** Follow artists and save shows and videos; they surface on a
  Home landing strip and a dedicated Favorites view.
- **Themes.** Four runtime-swappable looks (Tape Room, Soundboard, Shoebox,
  The Receiver) with album-art-driven accent washes.
- **System integration.** Media keys, Control Center, and AirPods transport
  via `MPRemoteCommandCenter`; cover art and now-playing in the system widget.
- **Live quality dashboard.** Real format, platform tier, sample rate, bit
  depth, channels, and buffer-ahead — read from the decoder, not guessed.
- **Auto-update.** Built-in Sparkle updater — the app checks for new releases
  and installs them in place with one click; "Check for Updates…" lives under
  the app menu.

## Why native

Two nugs.net platform constraints rule out a browser-based client: CORS, and
the audio CDN's required `Referer`/`User-Agent` headers that browsers won't let
JavaScript set. A native app has neither problem — `AVURLAsset` carries the
headers directly, so no proxy tier is needed:

```
┌──────────────────────────────┐    TLS    ┌──────────┐
│ AppleNugs.app                │ ────────► │ nugs.net │
│ SwiftUI · AVFoundation       │           └──────────┘
│ tokens in the macOS Keychain │
└──────────────────────────────┘
```

## Build & run

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). The `.xcodeproj` is generated, not committed:

```sh
xcodegen generate
open AppleNugs.xcodeproj   # then ⌘R
```

or headless:

```sh
xcodebuild -project AppleNugs.xcodeproj -scheme AppleNugs -configuration Debug build
```

The committed project is **ad-hoc signed** so it builds in CI and on any
machine with no Apple Developer team. Producing a signed, notarized build for
the App Store or for direct download is covered in
[DISTRIBUTION.md](DISTRIBUTION.md).

Sign in with browser SSO or your nugs.net email and password. Access and refresh
tokens are stored in the macOS **Keychain** (the source of truth), with a
`chmod 600` file fallback inside the app's sandbox container
(`~/Library/Containers/com.timvbs.applenugs/…`) for unsigned/ad-hoc builds that
have no Keychain entitlement; a legacy `session.json` is migrated into the
Keychain on first launch and then removed. Tokens refresh ~60s before expiry.

## Keyboard shortcuts

| key         | action                          |
| ----------- | ------------------------------- |
| `/`         | Focus search                    |
| `space`     | Play / pause                    |
| `n` / `p`   | Next / previous track           |
| `←` / `→`   | Seek −10s / +10s (⇧ for ∓30s)   |
| `0`         | Seek to start                   |
| `1`–`9`     | Seek to 10%–90% of the track    |
| `Esc`       | Blur a focused input            |
| `⌃⌘→ / ⌃⌘←` | Next / previous (menu)          |
| `⌘⇧F`       | Focus search (menu)             |
| `⌥⌘I`       | Toggle the dashboard panel      |

Plain-letter keys are handled by a window-level event monitor and pass through
untouched while a text field has focus.

## Notes for hacking

- The unofficial API surface is documented by
  [Sorrow446/Nugs-Downloader](https://github.com/Sorrow446/Nugs-Downloader) and
  [Dniel97/orpheusdl-nugs](https://github.com/Dniel97/orpheusdl-nugs); check
  those when an endpoint or shape stops working.
- nugs's catalog JSON uses inconsistent casing (`artistID` vs `ArtistID`) and
  pluralization. All shape-dependent digging lives in `Core/JSON.swift` and
  `Core/Catalog.swift`.
- `platformID` for `bigriver/subPlayer.aspx` is a *device tier*, not a format:
  we probe `{1, 4, 7, 10}` concurrently and identify the actual format from
  URL path patterns (`.flac16/`, `.alac16/`, `.m3u8`, …). Preference order is
  ALAC → FLAC → MQA → AAC → HLS, with fallthrough on failure.
- Browser login relies on id.nugs.net (Duende IdentityServer) trusting the
  mobile client's `client_id` + `nugsnet://oauth2/callback` redirect pair;
  `ASWebAuthenticationSession` captures the callback in-process, so the scheme
  is deliberately *not* registered in `Info.plist`.

## License

[MIT](LICENSE) for the AppleNugs source. The license covers this code only and
grants no rights in nugs.net's service, content, or marks.
