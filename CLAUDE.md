# Yeti (formerly AppleNugs) — guide for Claude

Native **macOS + iOS SwiftUI** player for nugs.net, shipped as **Yeti — an unofficial player for nugs.net**
(named for the Goose song). Public repo `tsvb/applenugs`; the repo, bundle ids, Xcode project/target names
and the `.app` file name still say AppleNugs on purpose (see Conventions → compliance). Unofficial: talks
nugs.net's private API with the user's own subscription and identifies itself honestly as Yeti. Developer ID /
direct-download distribution, not the App Store (guideline 5.2.2). Latest release: **v1.5** (build 6), which
predates the Yeti design — everything since is on `main`, unreleased. **Tim is the only user**: no migrations
or release notes for design changes, but keep his own data safe.

## Read first
- **Auto-memory:** `~/.claude/projects/<project-slug>/memory/MEMORY.md` (loaded at session start) holds the
  deep context — distribution runbook and secrets-adjacent values (team ID, notary profile, device UDIDs),
  the Duo, the pill, the catalog APIs, gotchas. Skim the notes relevant to your task before acting.
- **Tim prefers the system's own chrome and layout** over custom UI — recommend the system mechanism first
  (the `feedback-system-guidelines-first` memory).

## Workflow
- How features are built: brainstorm → spec in `docs/superpowers/specs/` → plan → implement with review.
  Don't skip the design/spec step for anything with a design choice in it. `docs/superpowers/` is
  **gitignored** (local only, dies with the worktree) — durable decisions go in this file or memory.
- **Landing recipe:** branch from `origin/main`, push, open a PR, wait for CI (the `xcode-27` runner), then
  `git push origin <branch>:main` — **fast-forward only**, never a merge or rebase, so commit hashes stay valid.
  GitHub marks the PR merged by itself. Delete the branch after. Pushing/landing is Tim's call.
- **CI sometimes doesn't start for a PR** (seen on #12, #13). Then `gh workflow run CI --ref <branch>`
  (the workflow has `workflow_dispatch`), watch it, check its `headSha` is the branch tip, and land.
- Install on Tim's devices to verify before landing anything visual — he judges on hardware.

## Environment & build
- Work in the git **worktree** you were started in; don't `cd` to the main checkout (`/Users/tim/applenugs`).
  `git -C /Users/tim/applenugs pull --ff-only` updates it when Tim asks.
- `xcodegen generate` after any `project.yml` edit (`AppleNugs.xcodeproj/` is gitignored). Regenerate before
  building. `APPLENUGS_TEAM_ID=<team> xcodegen generate` for device builds (team ID in memory, not the repo).
- **Toolchain:** Xcode **27.1+** is required — the iOS app compiles iOS 27.1 SDK symbols (`ArrangementView`)
  behind `#available`, which an older SDK can't compile at all. CI pins `Xcode_27.1.app` and asserts it;
  locally `xcode-select` points at Xcode 27.2. Deployment floors: macOS 14.0, iOS 26.1 (for
  `tabViewBottomAccessory(isEnabled:)`; see `project.yml`).
- Schemes: `AppleNugs` (macOS, `-destination 'platform=macOS'`), `AppleNugs-iOS`
  (`'generic/platform=iOS Simulator'` or `'platform=iOS,id=<udid>'`), `AppleNugsTests` (host-free unit tests
  — pure Foundation files compiled straight into the bundle via `project.yml`, no `@testable`; take the count
  from the suite, not from docs).
- **Always verify with a fresh `-derivedDataPath`** (incremental builds can report a false clean), and keep
  **both** schemes warning-free under `SWIFT_STRICT_CONCURRENCY=complete`. SourceKit "No such module 'UIKit'"
  on iOS-only files is index noise; `xcodebuild` is authoritative. **Delete DerivedData after** — disk is tight.
- **Seeded launch, no login:** `-UITEST -UITestSeedQueue` (stub catalog with FAKE ids, a parked queue). It
  never writes the resume queue or listening stats, and it skips artist-photo lookups (fake ids would show
  strangers' photos). Listening-stat READS stay live, so a seeded run shows real nice-list data.
- **iOS device install** (Tim's iPhone Duo; UDID in memory): Developer Mode on, phone UNLOCKED, build against
  the specific device with `-allowProvisioningUpdates -allowProvisioningDeviceRegistration` (a generic build
  never registers a new phone → `0xe8008012`), then `xcrun devicectl device install app --device <udid> <app>`.
  Trust `devicectl list devices` over `xctrace`. A running VPN on the Mac hangs every `devicectl` call.
- **Mac local install** must be **Developer ID-signed** (ad-hoc + hardened runtime can't load Sparkle) —
  recipe in the `applenugs-local-install-signing` memory. Every built `.app` registers `applenugs://`; after
  installing, `lsregister -u` the build-folder copy and `lsregister -f /Applications/AppleNugs.app`.
- **Duo simulator:** needs its own runtime (iOS 27.1 `24A94425`). Xcode 27 has no Simulator.app — open
  `/Applications/Xcode.app/Contents/Applications/DeviceHub.app`; folding/rotating are on-screen controls only,
  so poses need Tim. `simctl io <udid> screenshot --display=1` (outer) / `--display=3` (inner); a black inner
  shot means the device is folded, whatever pose was described — check both displays.

## Conventions worth knowing

### Design system
- **Yeti is the only design** (macOS + iOS, dark only). The five old themes, their picker, the transport and
  miniplayer variants, the art-color pipeline, wash and grain were deleted 2026-11-07. ONE token struct,
  `Theme` (`AppleNugs/Theme/Theme.swift`, the only place literal hex lives): `palette` (semantic roles —
  `base`/`raised`/`hairline`, `textPrimary`/`textSecondary`/`textIdle`, `accent` = foil, `playState` = sale
  yellow, `cardStock`, `stickerInk`, the sticker stock stops, `segmentThumb`, `videoErrorBackdrop`, the
  bubble's plastic), `type` (size-taking font closures) and `copy` (the app's voice). `Theme.yeti` is the
  `\.theme` default; `ThemedRoot` (`.themed(_:)`) sets the snow root tint, base background, body font and
  `.dark`.
- **Foil means time.** The root tint is snow (`palette.textPrimary`), so system controls never paint an
  accent fill; foil is applied explicitly only where time moves (scrubs, the pill ring, the sweep, the caret,
  download/resume progress).
- **Components** live in `AppleNugs/Theme/Components/`: `BlisterPack` (card stock + bubble, `PackArt`,
  `BlisterGlass`; the card's top padding is DERIVED from the hang slot + clearance + halo — don't copy the
  sheet's 30–34pt tops back), the stickers (`StickerStock`, `PlaySticker`, `PriceSticker`, `RowSticker`,
  `LabelSticker`), `FoilSweep` (reads no time), `YetiButtonStyles` (+ the macOS foil focus outline),
  `YetiSegmentedControl`, `EmptyPackMessage`, `MonogramTile`, `ArtistPortrait`, `ArtistTile`.
- **Artists are circles, shows are squares.** Every artist surface uses the artist's photo in a circle
  (`ArtistPortrait`): Home's crate (iOS tiles via `ArtistTile`; Mac rows), the Artists list, the artist page
  header, the Favorites page. Photos come from the v1 catalog (`Catalog.artistAvatars`; `?ids=` in batches of
  100, or the full 718-artist walk for the Artists list, cached per session on `AppModel`); the monogram is
  the loading/miss fallback. Show covers stay square.
- **Design pages:** `docs/design/yeti-theme/` (`yeti-theme.html` token sheet, `yeti-surfaces.html`,
  `yeti-decisions.html` — Tim's rulings); superseded mockups are in its `archive/`. App icon:
  `AppleNugs/AppIcon.icon` (Icon Composer; concepts in `docs/design/yeti-icon/`, rendered by
  `scripts/render-app-icon.py`). The README banner is generated by `scripts/generate-banner.swift`.
- **Never quote the Goose song's lyrics** in the app or docs (copyrighted) — paraphrase only. The app's
  copy lines ("It's on its way", "Says so on the box", "The nice list"…) are cleared as paraphrase.
- Tim's standing rulings: the Artists list shows no per-artist show counts (a fan-out would break polite
  networking); the now-playing counter reads "Track 3 of 24"; the Mac Home resume card is a FLAT cover (the
  Mac's bubble belongs to the dashboard miniplayer and the Now Playing window); "Sign out" app-wide; all
  clear-queue paths confirm.

### Platforms and layout
- **macOS vs iOS:** `AppleNugs/macOS/` and `AppleNugs/iOS/` are per-platform (excluded from the other
  target); everything else is shared. Keep the untouched platform building.
- **`DashboardPanel.swift` is SHARED**, not macOS code: iOS presents it as a sheet from `NowPlayingScreen`
  and beside it in `NowPlayingArrangement`. Anything under `AppleNugs/macOS/` it calls MUST sit behind
  `#if os(macOS)` — the macOS build won't catch the iOS break.
- **Leaf views own the ~4Hz tick.** `DashboardPanel` is a `ScrollView`+`VStack` (NOT a `List` — macOS-26
  `NSTableView` reentrancy). Only leaf views may read `currentTime`: `MiniPlayerScrubTrack`, `BufferedRow`,
  the iOS `ElapsedTimeLine`, `PanelScrubRow` (in `ExpandedPlayerPanel`), `PillProgressRing`, and
  `ResumeProgressRule` (both Home heroes). Add to this list rather than hoisting a read into a host body.
  **A leaf must render CONSTANT-HEIGHT content** — collapsing to `EmptyView` when a value is unknown
  re-lays-out the parent (a visible jump, and the very re-layout the isolation exists to prevent).
- **The inspector's Signal section holds a constant row set** (`SignalReadout`, pure + tested). Gate on
  `player.current`, never on `nowPick`/`specs` (`startCurrent()` nils them every track change). Unknown
  values degrade to `"—"`, dimmed via `foregroundStyle` ONLY (a font/weight change moves the row height);
  `"--:--"` is reserved for clocks.
- **Dashboard miniplayer** (`AppleNugs/macOS/MiniPlayer/`, macOS only): `DashboardMiniPlayer` shows the idle
  line or `MiniPlayerStandard` (the blister-pack miniplayer); shared leaves in `MiniPlayerParts.swift`. The
  inspector column is pinned `min: 340, ideal: 340, max: 380` because a real 44-char venue clips below 340.
- **Duration-less streams:** a stream that reports no duration must not pin a scrub thumb hard right
  ("finished"). Every slider carries `duration > 0 ? min(currentTime, sliderMax) : 0` (three sites:
  `TransportBar`, `NowPlayingScreen`, `ExpandedPlayerPanel`); the pill ring is empty, not full
  (`PillLayout.progressFraction`). A new scrub surface needs the same guard.
- **iPhone Duo layout rules** — all switched on MEASURED width, never size class. Phones are portrait-locked
  (`OrientationGate`, open only during full-screen video), so no regular iPhone reaches the wide layouts; the
  Duo's unfolded inner display is wide in portrait (~951×669pt flat, ~669×951pt upright).
  (1) **Art must yield height** — never a rigid tile: the bubble takes what the nameplate leaves (capped by
  `maxBubbleSide`), and with no cover `PackArt` sizes the `MonogramTile` to that box.
  (2) **The pill is Apple's `tabViewBottomAccessory`, on the Duo too** (no custom overlay, shelf or duck —
  built, then reversed by Tim; don't rebuild). It sheds controls by measured width
  (`PillLayout.controls(slot:width:…)`, 90pt text floor — the folded Duo's vertical tab bar leaves a ~290pt
  accessory that still reports `.expanded`), and its second line becomes "artist · show" at a ≥ 220pt text
  column (`PillLayout.showsShowLine`: the flat Duo; the upright Duo's pill is ~400pt, artist only).
  (3) The full-screen cover hosts `NowPlayingArrangement`; pure `NowPlayingColumns` picks compact → player
  alone, regular + wider-than-tall → iOS 27.1 `ArrangementView` (player + `DashboardPanel(showsNowPlaying:
  false)`), regular + upright → an explicit HStack with a 220–260pt queue column. The arrangement REMOVES the
  secondary when it can't split, so players read `\.nowPlayingQueueBeside` and swap their queue button for a
  same-size hidden placeholder. It owns **swipe-down to close** (pure `NowPlayingDismissDrag`, a plain
  `.gesture` on the PLAYER only so sliders and buttons win; the moving layer carries its own
  `safeAreaPadding`). Scaling a fixed cluster = `NowPlayingFit.scale` + `scaleEffect` + a matching `.frame`.
  (4) **Wide Home splits into two columns** (`HomeColumns`, iOS only): ≥ 560pt of content with a track
  loaded → the hero keeps its UPRIGHT blister pack in a 280–320pt leading column, favorites / nice list /
  crate beside it. A sideways hero card was built and REJECTED ("still too wide… a little lazy") — Tim wants
  wide canvases to gain content, not stretched components.
- **The pill's hard-won facts:** `tabViewBottomAccessory` is 360×48pt expanded, 284×48pt inline, height
  system-owned; a `.sheet` attached INSIDE the accessory never appears (the shell presents the panel and the
  pill takes an injected `onExpand`); a drag-up loses to the tab bar's scroll-to-minimize (hence the
  chevron). The art chip is clipped to a CIRCLE so the progress ring's 1pt gap holds at every angle.

### Navigation and metadata
- **Now-playing metadata is clickable** (`NowPlayingMetaText` + pure `NowPlayingMetaLine`): artist and show
  are separate `.link` runs inside ONE `Text(AttributedString)` — never an HStack of Buttons (several sites
  have no layout slack, the pill above all). Taps arrive as `x-applenugs-meta://` URLs, intercepted by
  `.nowPlayingMetaLinks(app:ui:)` at all THREE scene roots (`RootView`, `IOSRootView`, the macOS Now Playing
  `Window`). **The interceptor MUST return `.systemAction` for foreign URLs** or the video page's donation
  links break. Links are invisible at rest (each run carries the surrounding color) and get a dotted
  underline on hover, macOS only. Build attributes with the `AttributeScopes.…Attribute.self` subscript —
  the dynamic-member form warns under strict concurrency. `tappableText: false` is the dial if a mis-tap
  problem appears on the pill or a Home hero; `showsLinks: false` for the offline Downloads sheet.
- **Navigating from a modal surface uses `UIState.navigate(to:)`, not `open(_:)`** — it bumps a tick every
  presentation owner observes (`dismissesOnNavigation(_:ui:)`), because on iOS the dashboard can be a sheet
  inside a sheet. It deliberately doesn't touch `sidebarSelection` (whose `didSet` resets `navPath`). Deep
  links route through it too.
- **Deep links** (`applenugs://`, `yeti://`; goosealmanac depends on `applenugs://`): `DeepLinkMatch.normalize`
  carries the SITE's venue rule — apostrophes (ASCII + U+2019) deleted, every other non-alphanumeric run
  collapsed to one space ("Slim's" ↔ "Slims", "St-Denis" ↔ "St Denis"). Don't simplify it. There is no
  picker: `DeepLinkRouter` takes the first same-date match when no usable venue hint is given.
- Catalog dates are UTC-midnight instants — use `CrateSection.catalogCalendar`, never `Calendar.current`.

### Playback, data and compliance
- **Audio/video arbiter: only one plays; the last one DELIBERATELY started wins.** `VideoPlayerService` calls
  `PlayerService.pauseForExternalAudio()` on EVERY claim. While `suspendedForVideo`, `startPlayback()`
  refuses, so an automatic start can't play underneath. Deliberate audio starts (`startAt` with
  `deliberate: true`, `resume`, `togglePlayPause`, the gapless `next()`) call `takePlaybackFromVideo()`
  first. Any new "the listener pressed play" entry point must too, or it's silently swallowed during video.
- **A restored queue loads its cover at launch** (`restorePersistedState` → `loadArtwork`), so the paused
  hero, pill and lock screen show art without pressing play. `PlaybackStateStore` never writes under
  `-UITEST` (reads stay live).
- **Listening stats are artists-only rolling aggregates with NO event log.** `ListeningStats`,
  `ListeningCredit` (play = min(50%, 240s) LISTENED) and `LedgerSummary` are pure + tested; the
  `@Observable` `ListeningStatsStore` writes `listening.json`. Rules that fail silently: (1) `PlayerService`
  owns the accumulator (`@ObservationIgnored`) and credits only at commit boundaries (track change, 30s,
  pause, background, terminate), never per tick. (2) `HomeView` gates the ledger on `listening.hasAnyPlay`,
  never on `stats`. (3) `save()` refuses to write while `loadFailed` is latched (that file is the only copy).
  (4) Backgrounded iOS has no tick, so credit is SETTLED (`ListeningCredit.span`), reading `creditPosition`
  — nil, never the stale `currentTime`, when the head isn't our item; paused → playing re-anchors without
  crediting. Don't add a wake or background tick for stats. Deliberate scope cuts: artists only, all-time
  only, Home only, typographic ledger, audio only. Reset lives in the account menu.
- **Compliance (nugs.net Terms):** identity is honest everywhere — `NugsIdentity.current` =
  `Yeti/<ver> (unofficial; +github; <OS>)`, no Referer; the old Android UA strings exist ONLY as the DEBUG
  Network Probe's control. Streams try tier 7 (ALAC 16) first and other tiers ONE AT A TIME
  (`StreamTierPlan`) — never re-parallelize; tier map 1 FLAC16, 4 MQA24, 7 ALAC16, 10 MQA24. API/resolver
  calls go through a 4 req/s token bucket (burst 8). **Browser sign-in only** (no password screen). The
  OAuth client ID is the official app's — unavoidable without a nugs-issued client (NOTICE says so).
- **Downloads are sealed `.yeti` files** (64 KiB AES-GCM chunks, a per-install Keychain key, `yeti-local://`
  + `SealedAssetLoader`). Never write or keep plaintext; logout deletes all downloads and the key; offline
  play needs a subscription check within 30 days. No Reveal in Finder or export. Keep
  `isEntireLengthAvailableOnDemand = true` in `SealedAssetLoader` (without it AVFoundation buffers whole
  files; a test guards it), and keep the player tick off in the background.
- **Display-only rename:** bundle ids `com.timvbs.applenugs*`, `Application Support/AppleNugs/`, the Keychain
  service, the Sparkle feed + EdDSA key, the repo and `PRODUCT_NAME` (`AppleNugs.app`) are deliberately
  unchanged (DISTRIBUTION.md lays out the `.app` rename trade-off).

### Verifying UI
- Launching the app is fine, but quit it afterward, don't grind on stuck GUI automation, and never enter
  credentials at a Keychain prompt. Magnet's overlay swallows synthetic clicks.
- For pure layout questions on the Mac, the `swiftc` + `NSHostingView` harness (offscreen PNGs via
  `cacheDisplay`) beats the live app — see the `applenugs-swiftui-hypothesis-testing` memory.

## Releases
`DISTRIBUTION.md` is the runbook (Path B: Developer ID → notarize → DMG → GitHub release → Sparkle appcast),
with the details and gotchas in the `applenugs-distribution` memory (the `ExportOptions` `TEAMID` template,
where `generate_appcast` lives after `rm -rf build`). Push the version bump BEFORE `gh release create`.
**Tim's `/Applications/AppleNugs.app` is a local Developer ID build of `main`**, not the v1.5 release, though
it still reads 1.5 (6) — bump `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` before any real release. The
v1.5 release is backed up at `~/AppleNugs-1.5-build6-backup.zip`.

## State — as of 2026-11-16
- `main` carries the whole Yeti design (PR #8), the Duo two-column Home + pill show line (#9), the restored
  queue's cover art (#10), crate tiles (#11), artist photos on the crate (#12), the Artists list (#13), the
  Mac (#14), the artist page (#15) and Favorites (#16). Tim's Duo and Mac run this build.
- **Next on Tim's list:** the Duo nightstand/tent work (Tim chose all three: a propped-open player with
  clock + night dimming, a tent-pose landscape player that auto-opens, a StandBy Now Playing widget — start
  with a DEBUG pose probe; `onHingeChange` gives only status + angle, there is no posture enum; spec local in
  `docs/superpowers/specs/`). Not yet scheduled: a release of everything since v1.5 (Path B, after the
  version bump) — Tim's call.
- **Small follow-ups:** Home's Favorites strip still shows followed artists as text chips (could be photo
  circles); decide the `.app`/`PRODUCT_NAME` rename; goosealmanac's deep-link doc should mention `yeti://`;
  `VideoPlayerService` pushes Now Playing every 0.5s during video; ask nugs.net for an official OAuth client;
  shuffle and repeat (collapse the partial transport-control implementations first — player-backlog memory).
- **Unverified, needs hardware:** locked-screen listening credit on the Duo (play locked 5+ min; the
  artist's time should include it); the nice list's reset dialog on iOS; swipe-down to close starting on a
  slider thumb; the offline Downloads sheet's pill; VoiceOver on the pill, hero, segmented control and login;
  Dynamic Type against the expanded panel's 250pt detent; the Mac's plaintext-download migration and the
  logout wipe; Mac keyboard focus showing the foil outline (not the system ring) on our own controls.
