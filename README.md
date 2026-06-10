# AppleNugs

A native macOS port of [nugsdotnet](https://github.com/tsvb/nugsdotnet) — a
personal client for [nugs.net](https://nugs.net), written in Swift/SwiftUI.
Personal use against your own subscription only — no content is downloaded,
redistributed, or stripped of DRM.

## Why native

The web port needed an ASP.NET Core proxy for two reasons: CORS, and the
audio CDN's required `Referer`/`User-Agent` headers that browsers won't let
JS set. A native app has neither problem — `AVURLAsset` carries the headers
directly, so the whole server tier disappears:

```
┌──────────────────────────────┐    TLS    ┌──────────┐
│ AppleNugs.app                │ ────────► │ nugs.net │
│ SwiftUI · AVFoundation       │           └──────────┘
│ session.json in ~/Library/…  │
└──────────────────────────────┘
```

Other things the platform gives us for free:

- **ALAC & HLS playback.** AVPlayer decodes ALAC natively (preferred here —
  it's lossless in an MP4 container) and speaks HLS, which the browser build
  had to punt on. If a format fails to play, the player falls through to the
  next available one automatically.
- **Media keys / Control Center / AirPods controls** via `MPRemoteCommandCenter`.
- **Exact stream specs** (sample rate, bit depth, channels) from the decoder
  itself instead of hand-parsing FLAC/MP4 headers.

## Component map

| nugsdotnet (.NET)                  | AppleNugs (Swift)                          |
| ---------------------------------- | ------------------------------------------ |
| `NugsClient.cs`                    | `Core/NugsClient.swift`                    |
| `TokenStore.cs` (tokens.json)      | `Core/SessionStore.swift` (session.json)   |
| `NugsShape.cs` (JSON digging)      | `Core/JSON.swift` + `Core/Catalog.swift`   |
| `StreamInspector.cs` (header parse)| AVFoundation format descriptions           |
| `PlayerService.cs` + audio-interop | `Player/PlayerService.swift` (AVPlayer)    |
| ASP.NET Core proxy endpoints       | — (not needed natively)                    |
| Razor pages                        | `Views/*.swift`                            |

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

The target is ad-hoc signed (`CODE_SIGN_IDENTITY: "-"`) so it builds without
a developer team; flip to automatic signing in `project.yml` if you want one.

Sign in with your nugs.net email and password. Tokens persist in the app's
sandbox container (`~/Library/Containers/com.timvbs.applenugs/Data/Library/
Application Support/AppleNugs/session.json`) and refresh automatically ~60s
before expiry. Apple/Google SSO accounts won't work with the password grant —
same caveat as the web port.

## Keyboard shortcuts

| key     | action                          |
| ------- | ------------------------------- |
| `/`     | Focus search                    |
| `space` | Play / pause                    |
| `n`     | Next track in queue             |
| `p`     | Previous track in queue         |
| `Esc`   | Blur a focused input            |
| `⌃⌘→ / ⌃⌘←` | Next / previous (menu)      |
| `⌥⌘I`   | Toggle the dashboard panel      |

Plain-letter keys are handled by a window-level event monitor and pass
through untouched while a text field has focus — same behavior as the web
port's `audio-interop.js`.

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
  ALAC → FLAC → MQA → AAC → HLS, and playback falls through on failure.
- Roadmap parity: this port covers the web app's v0.2 (auth, artist list,
  search, album/artist views, queue + autoplay, shortcuts) plus artist-page
  pagination. Not yet: persistent now-playing across launches, favorites,
  history, offline cache.
