# Yeti (formerly AppleNugs) — guide for Claude

Native **macOS + iOS SwiftUI** player for nugs.net, shipped to users as **Yeti — an unofficial player for nugs.net** (named for the Goose song). Public repo `tsvb/applenugs` (repo, bundle ids, Xcode project/target names and the `.app` file name still say AppleNugs on purpose — see "Yeti — compliance pass" below). Unofficial: talks nugs.net's private API with the user's own subscription, identifies itself honestly as Yeti. Developer ID / direct-download distribution, not App Store (5.2.2). Latest release on `main`: **v1.5**.

## Read first
- **Claude Code auto-memory:** this project's memory index at `~/.claude/projects/<project-slug>/memory/MEMORY.md` (loaded automatically at session start) holds the deep, current project context — parity program, distribution/release runbook, iOS port, theme system, player backlog, gotchas. Skim the notes relevant to your task before acting.

## Workflow (how every feature here is built)
`superpowers:brainstorming` → spec in `docs/superpowers/specs/` → `superpowers:writing-plans` → `superpowers:subagent-driven-development` (fresh implementer per task + per-task spec/quality review + whole-branch review). Don't skip the design/spec step, even for "simple" changes.

## Environment & build
- Work in the git **worktree** you were started in; **don't `cd` to the main checkout** (the repo-root clone). Merge to `main` via a fast-forward from the main checkout using `git -C`, then push (releases/pushes are the maintainer's call).
- `xcodegen generate` after any `project.yml` edit (`AppleNugs.xcodeproj/` is **gitignored**). Regenerate before building/opening.
- Schemes: `AppleNugs` (macOS, `-destination 'platform=macOS'`), `AppleNugs-iOS` (`-destination 'generic/platform=iOS Simulator'` or a device id), `AppleNugsTests` (host-free unit tests, **131** as of 2026-08-18 — CI runs them on every push, so take the count from the suite rather than from this line).
- **Always build/verify with a fresh `-derivedDataPath`** — incremental builds can report a false "clean". Project must stay warning-free under `SWIFT_STRICT_CONCURRENCY=complete` on **both** schemes. SourceKit "No such module 'UIKit'" on iOS-only files = per-target index noise; `xcodebuild` is authoritative.
- `docs/superpowers/` is **gitignored** (specs, plans, reports — local only, and therefore NOT a safe place for handoff state: a worktree removal deletes it. Durable session state belongs in this file plus the auto-memory index).
- Visual verify without a login: launch with `-UITEST -UITestSeedQueue` (bypasses login, seeds a now-playing queue). Theme switcher = account menu (person icon). Dashboard = `sidebar.right` toolbar button / ⌥⌘I.
- iOS device install: `DEVELOPMENT_TEAM=$APPLENUGS_TEAM_ID` (the paid team — value in the local `applenugs-distribution` memory, not in the repo) + `-allowProvisioningUpdates`; **the iPhone must be UNLOCKED** or the developer disk image won't mount. Notary profile name and Developer ID team: see the local `applenugs-distribution` memory. Full release runbook: `DISTRIBUTION.md` + the `applenugs-distribution` memory.

## Conventions worth knowing
- **Themes** (5: Soundboard, Tape Room, Shoebox, The Receiver, Click Wheel) drive personality via `theme.transport` (a `TransportSignature` enum in `AppleNugs/Theme/Theme.swift`) plus `theme.palette/type/copy/caps/washStyle`. Now-playing surfaces dispatch on it (see `AppleNugs/Views/NowPlaying/`). Reusable themed parts live in `AppleNugs/Theme/Components/` (VUMeter/KnurledButton in `FaceplateParts`, `EqualizerBars`, `ArtWashBackground`, `MonogramTile`).
- **macOS vs iOS:** `AppleNugs/macOS/` and `AppleNugs/iOS/` are per-platform (excluded from the other target); everything else is shared. Keep the untouched platform building.
- **Dashboard inspector perf:** `DashboardPanel` is a `ScrollView`+`VStack` (NOT a `List` — macOS-26 `NSTableView` reentrancy). The ~4Hz playback tick (`currentTime`) is isolated in **leaf views** so the panel body / queue `ForEach` don't re-diff every frame. **Only leaf views may read `currentTime`** — never hoist the read into a host or variant body. The current readers are `MiniPlayerScrubTrack`, `MiniPlayerClock`, `CassetteReels`, and the iOS-only `ElapsedTimeLine`/`BufferedRow`, `PanelScrubRow` (in `ExpandedPlayerPanel`) and `PillProgressRing`. Follow this pattern for any live-updating inspector content, and add to this list rather than treating it as closed. **A leaf must also render CONSTANT-HEIGHT content** — a leaf that collapses to `EmptyView` when its value is unknown changes size, and a child size change invalidates the parent's layout, which is both a visible jump and the very re-layout the isolation exists to prevent. `BufferedRow` used to do exactly that; it now always renders a row with a `SignalReadout.unknown` placeholder.
- **The inspector's Signal section holds a constant row set** (`SignalReadout`, pure + unit-tested). `startCurrent()` nils `nowPick`/`specs` on every track change, so gating rows on them collapsed the section from six rows to two — jumping the whole queue below it — and hid it entirely on a launch-restored queue. Gate on `player.current`, never on `nowPick`/`specs`; let unknown values degrade to `"—"` (dimmed via `foregroundStyle` ONLY — a font or weight change moves the row height and brings the bug back one row at a time). `"--:--"` stays reserved for clocks.
- **`DashboardPanel.swift` is SHARED, not macOS code.** It lives in `AppleNugs/Views/`, and iOS presents the same panel as a sheet from `ClickWheelScreen`, `NowPlayingScreen`, and `TouchFaceplate`. Anything under `AppleNugs/macOS/` called from it MUST sit behind `#if os(macOS)` or the iOS build breaks — the macOS build won't catch it.
- **Dashboard miniplayer** (`AppleNugs/macOS/MiniPlayer/`, macOS only): `DashboardMiniPlayer` dispatches on `theme.transport` to `MiniPlayerStandard` (Soundboard + Shoebox share one token-driven view), `MiniPlayerCassette`, `MiniPlayerFaceplate`, `MiniPlayerClickWheel`; shared leaves in `MiniPlayerParts.swift`, pure reel math in `TapeGeometry.swift`. The inspector column is pinned `min: 340, ideal: 340, max: 380` because a real 44-char venue string clips below 340. Tape Room's cassette holds a true **25:16** ratio with only ~19pt of slack — growing the label, the play puck, the clock font, or the reels silently yields the ratio (it has already regressed twice); the budget arithmetic is commented in `MiniPlayerCassette.swift`.
- **Now-playing metadata is clickable** (`NowPlayingMetaText` + the pure `NowPlayingMetaLine`). The artist and the show are separate `.link` runs inside ONE `Text(AttributedString)` — never an HStack of Buttons, because 8 of the 16 render sites join the two fields into one string and several have no layout slack (the cassette's 25:16, the pill's text budget, the faceplate's fixed 220pt ticker). Taps arrive as `x-applenugs-meta://` URLs and are intercepted by `.nowPlayingMetaLinks(app:ui:)`, installed at all THREE scene roots (`RootView`, `IOSRootView`, and the macOS Now Playing `Window` — a separate scene with its own environment). **The interceptor MUST return `.systemAction` for foreign URLs** or `VideoDetailView.benefitNotes`' real donation links break. Links are invisible at rest (each run carries the surrounding color explicitly — SwiftUI honors it over its own link tint, verified by pixel-comparing an offscreen render) and reveal a dotted underline on hover, macOS only. Build attributes with the `AttributeScopes.…Attribute.self` subscript, NOT the `run.foregroundColor =` dynamic-member form, which forms a key path over a non-Sendable type and warns under strict concurrency.
- **Navigating from a modal surface uses `UIState.navigate(to:)`, not `open(_:)`.** It bumps a tick that every presentation owner observes via `dismissesOnNavigation(_:ui:)`. Needed because on iOS the dashboard is a sheet inside a sheet AND a sheet inside a fullScreenCover, so a tap there unwinds two layers and `@Environment(\.dismiss)` reaches only the innermost. `navigate(to:)` deliberately does NOT touch `sidebarSelection` — its `didSet` resets `navPath` and would wipe the push. Deep links route through it too.
- **`NowPlayingMetaText` carries a `tappableText` flag** (and `showsLinks` for the offline Downloads sheet, which has no stack to push onto). All 16 sites are real tap links today, the pill and Home hero included — Tim asked for that explicitly after they initially shipped as long-press/VoiceOver-only. If a mis-tap problem ever shows up on those two (both have their whole body as a competing tap target), `tappableText: false` is the dial, not a rewrite.
- **`PlaybackStateStore` no longer writes under `-UITEST`** (both `save` and `clear`, each behind `#if DEBUG` because `AppModel.isUITestRun` is itself DEBUG-only and is now `nonisolated` so the nonisolated store can read it). This retires the long-standing seeded-launch hazard: a `-UITestSeedQueue` run that touched the transport used to persist stub tracks over the real resume queue, and "Clear" deleted it outright. Reads are deliberately still live.
- **iPhone Duo layout rules.** (1) **Now-playing art must yield height** — never a rigid tile: the no-art
  `MonogramTile` scales with its box (capped at its old 280/260pt), exactly like real artwork; a fixed
  tile overflows short canvases (the Duo's landscape inner display, and portrait iPhones by ~15pt).
  (2) **The pill sheds controls by measured WIDTH** (`PillLayout.controls(slot:width:hasLeadingSlot:trailingReserve:)`,
  90pt text floor), because on the Duo's outer display a vertical tab bar leaves a ~290pt accessory that
  still reports `.expanded`. (3) The iOS full-screen cover hosts `NowPlayingArrangement`; the pure
  `NowPlayingColumns` policy picks compact → player alone, regular + wider-than-tall → iOS 27.1
  `ArrangementView` (player + `DashboardPanel(showsNowPlaying: false)`), regular + upright → an explicit
  HStack with a 220–260pt queue column (ArrangementView's horizontal split refuses tall canvases). It
  also owns **swipe-down to close** (pure `NowPlayingDismissDrag`; a plain `.gesture` on the PLAYER only,
  so sliders/buttons/The Receiver's ladder win; the moving layer must carry its own `safeAreaPadding`
  because offset content stops painting its safe-area backgrounds). Players read
  `\.nowPlayingQueueBeside` and swap their queue button for a same-size hidden placeholder. Scaling a
  fixed-geometry cluster uses `NowPlayingFit.scale` + `scaleEffect` + a matching `.frame` —
  `scaleEffect` alone keeps the old footprint.
- Catalog dates are UTC-midnight instants — use `CrateSection.catalogCalendar`, not `Calendar.current` (see the `applenugs-catalog-dates-are-utc` memory).

## START HERE — state as of 2026-11-07 (handoff for a new session)

**Where the code is.** Worktree `.claude/worktrees/iphone-duo` (stay in it; don't cd to the main checkout).
- **`main` == `origin/main` == `e6ab835`** — everything above is LANDED: the iPhone Duo work (PR #5) and the
  pill duck + Yeti compliance/rename/encrypted downloads/perf + the theme design (PR #6, merged 2026-11-07,
  CI green on `xcode-27`, fast-forward — every hash in this file is on `main`). 307 tests.
- **`yeti-design`** (checked out, no upstream, starts at `e6ab835`) — the branch for the single-design
  refactor (step 3 below).
- The main checkout's local `main` ref is behind — `git -C /Users/tim/applenugs fetch origin main:main`
  (run by Tim; the worktree guard blocks `git -C` outside the worktree). Remote branches `iphone-duo` and
  `yeti` are merged and can be deleted on GitHub (Tim's call).
- `listening-stats` (in the main checkout; built, unmerged, based on the OLD main — needs a rebase onto
  `e6ab835`, with a CLAUDE.md conflict to resolve). Its Home "nice list" ledger is part of the Yeti design.

**Landing recipe (used for PR #5 and #6):** push the branch, open a PR (CI runs on the `xcode-27` runner),
then `git push origin <branch>:main` — fast-forward only, never a merge/rebase, so hashes here stay valid.
Pushing is Tim's call.

**Next steps, in Tim's order of interest:**
1. (done 2026-11-07 — both branches landed via PR #6.)
2. **Finish verifying Yeti on hardware:** logout wipes downloads; the **Mac** build (old plaintext downloads
   there must migrate to sealed `.yeti`; Reveal in Finder is gone). Mac local installs must be Developer
   ID-signed (see the local-install-signing memory).
3. **DECISION (Tim, 2026-11-07): Yeti becomes the ONLY design, on macOS and iOS — the five themes go**
   (reverses the Aug-2026 "keep all themes" call). Staged plan proposed: (a) land the branches; (b) design pass
   for surfaces the mockup doesn't cover (video, search, downloads, login/connection-failed, Duo two-column +
   pill-duck overlay, Mac Now Playing window, sheets, toasts); (c) add Yeti as theme #6 through the existing
   token system and verify on device; (d) make it the only theme (remove pickers, force dark); (e) delete the
   five themes, transport variants, art-color pipeline, wash/grain, ThemeID/ThemeManager (~2,300 lines); keep
   ONE token struct as the design system. The Home "nice list" ledger depends on the unmerged
   `listening-stats` branch. Spec it before building. Source design: `docs/design/yeti-theme/yeti-theme.html`
   (+ `.png`, and the three concepts it beat). It carries a token sheet that maps 1:1 onto `Theme` fields and a
   "Wiring it in" list (ThemeID `.yeti`, EqualizerBars branch, play-sticker sites, FoilSweep, BlisterBubble).
   Never quote the song's lyrics in the app or docs (copyrighted) — paraphrase only.
4. **Nightstand / tent** (Tim chose all three: propped-open player with clock + night dimming, tent-pose
   landscape player that auto-opens, StandBy Now Playing widget). Start with a DEBUG pose probe (hinge
   status/angle, division regions, display) Tim screenshots in each pose. See the NEXT block below.
5. Small follow-ups: regenerate the README banner SVGs (`scripts/generate-banner.swift` still writes
   "APPLENUGS") and re-shoot `docs/images`; decide the `.app`/`PRODUCT_NAME` rename (DISTRIBUTION.md lays out
   the Sparkle trade-off); goosealmanac's deep-link doc should mention `yeti://`; `VideoPlayerService` still
   pushes Now Playing every 0.5 s during video; consider asking nugs.net for an official OAuth client (the
   one thing honesty can't fix unilaterally).

**Session gotchas:** the claude-artifacts publishing tools stopped working mid-session on 2026-11-07 (restart
fixes it). The worktree-isolation shell guard rejects compound commands with variables/loops and `git -C`
outside the worktree — use plain commands or a `zsh` script in the scratchpad. Disk on this Mac runs tight
(~10 GB free): always delete DerivedData after a gate. Local-only specs for all of the above live in
`docs/superpowers/specs/2026-11-0{5,6}-*.md` (gitignored — they die with the worktree; the decisions are
copied into this file).

## Pick up here — state as of 2026-08-18

### iPhone Duo layout — MERGED to `main` (`805d766`, PR #5, 2026-11-06); CI green on `xcode-27`

**Landed:** pushed as `iphone-duo`, PR #5's CI passed (first run on the `xcode-27` runner, 2m24s — the
label resolves and Xcode 27.1 builds both schemes + tests), and `origin/main` was FAST-FORWARDED to
`805d766` (`git push origin worktree-iphone-duo:main`; GitHub then marked the PR merged) — no merge or
rebase commit, so every hash below is on `main`. `listening-stats` is still unmerged and based on the OLD
`main`; it now needs a rebase onto `805d766`, resolving this CLAUDE.md section against its own.

### Yeti — compliance pass (2026-11-06/07), branch `yeti` stacked on `pill-duck`, NOT pushed

The app is now **Yeti** ("an unofficial player for nugs.net", named for the Goose song) and follows nugs.net's
Terms (https://www.nugs.net/terms.html) where it matters. Spec (local): `docs/superpowers/specs/2026-11-06-yeti-compliance-design.md`.
Commits: `f7378f7` personal IDs out of CLAUDE.md · `a9dd016` `NugsIdentity` seam + DEBUG Network Probe ·
`cc8d54a` honest identity / tier 7 / browser-only sign-in / polite networking · `993ce03` Yeti rename +
disclaimers · `2db580f` encrypted downloads. **302 tests.** Rules that fail silently if broken:
- **Identity is honest everywhere:** `NugsIdentity.current` = `Yeti/<ver> (unofficial; +github; <OS>)`, NO
  Referer. The old Android UA strings exist ONLY as the DEBUG probe's control (`legacyAndroidForProbe`) — never
  reintroduce them in production. Live probe (Tim's Duo, 2026-11-07) proved nugs accepts the honest UA on
  subscriptions, api.aspx, subPlayer (all tiers), the CDN, and id.nugs.net refresh. The OAuth client ID +
  `nugsnet://oauth2/callback` are still the official app's — unavoidable without a nugs-issued client (NOTICE says so).
- **Streams: tier 7 (ALAC 16) first, other tiers ONE AT A TIME** (`StreamTierPlan`); never re-parallelize.
  Tier map: 1 FLAC16, 4 MQA24, 7 ALAC16, 10 MQA24. Token bucket 4 req/s (burst 8) on API/resolver calls.
- **Browser sign-in only** — the ROPC password screen is gone; don't bring it back.
- **Downloads are sealed `.yeti` files** (64 KiB AES-GCM chunks, per-install Keychain key `download-key`,
  `yeti-local://` + `SealedAssetLoader`). Never write or keep plaintext; logout deletes all downloads + the key;
  offline play needs `downloads.lastVerifiedAt` ≤ 30 days, renewed ONLY by a fresh subscription answer
  (re-fetched on each token refresh). No Reveal in Finder / export.
- **Display-only rename:** bundle ids `com.timvbs.applenugs*`, `Application Support/AppleNugs/`, Keychain
  service, Sparkle feed + EdDSA key, the repo, and `PRODUCT_NAME` (`AppleNugs.app`) are DELIBERATELY unchanged;
  `yeti://` added, `applenugs://` kept (goosealmanac). Follow-ups: regenerate the banner SVGs
  (`scripts/generate-banner.swift`), re-shoot `docs/images`, decide the `.app` rename, update goosealmanac's
  deep-link doc.
- **Verified on Tim's Duo:** honest identity (signed in, plays), Yeti name, encrypted download → seek + gapless
  ("even better than streaming"); **performance** (`8c3c0d7`): locked-screen playback of a downloaded show
  peaked at **60.9 MB for the whole app** (3.24 GB jetsam headroom), **0 background ticks**. The key is
  `isEntireLengthAvailableOnDemand = true` in `SealedAssetLoader` — without it AVFoundation buffers the whole
  file (134 MB per FLAC track); a test fails if it's removed. The 0.25 s player tick is removed in the
  background (once-a-minute resume save only) — don't reintroduce periodic background work.
  Unverified: logout wipe, the Mac migration.

**NEXT (queued, specced locally):** (1) the pill ducks out of the way on scroll on the Duo — **BUILT
`ed6770d` and VERIFIED by Tim on the real Duo 2026-11-06 ("nailed it"), 197 tests; not yet pushed** — branch
`pill-duck` in the same worktree; spec `docs/superpowers/specs/2026-11-05-pill-duck-on-scroll-design.md`;
probe verdict: the system accessory can't be animated (toggling `isEnabled` pops/crossfades AND reflows the
content 38–56pt), so where `\.toolbarVerticalEdge != nil` (iOS 27.1+) the pill becomes our own glass overlay
with a constant bottom content margin. (2) nightstand/tent — spec
`docs/superpowers/specs/2026-11-05-duo-nightstand-tent-design.md`: propped-open player (art + title +
clock above the fold, dims at night), tent-pose landscape player (auto-opens; app otherwise stays portrait),
and an interactive StandBy Now Playing widget (first widget extension + App Group). No posture enum exists —
`onHingeChange` gives only status (closed/partiallyOpen/fullyOpen) + angle.

Worktree `.claude/worktrees/iphone-duo`, based on `origin/main` `c0de287` — deliberately NOT on the
unmerged `listening-stats` branch.
Spec/plan/probe evidence are local-only under `docs/superpowers/` (`specs/2026-11-05-iphone-duo-layout-design.md`,
`plans/2026-11-05-iphone-duo-layout.md`, `duo-artifacts/`). The decisions they hold, so they survive the worktree:

- **Scope (Tim):** compatibility fixes + a two-column inner-display now-playing (player primary, `DashboardPanel`
  queue secondary via iOS 27.1 `ArrangementView`, `.split.axes(.horizontal)`). NOT sidebar-instead-of-tabs,
  two-column browse, multi-window, outer-display landscape, `ReservedRegion`, hinge effects, or any macOS change.
- **iOS floor stays 26.1**; every 27.1 API behind `if #available(iOS 27.1, *)`. **CI moves to Xcode ≥ 27.1**
  with a loud `xcodebuild -version` assertion (26.6 can't compile 27.1 symbols even behind `#available`).
- **Upright inner display:** first "player alone"; Tim REVERSED it after the real-Duo pass — the queue column sits beside the player upright too.
- **Phase 0 probe of the UNCHANGED app (Duo simulator, 27.2 SDK), verdicts:** outer display — tab bar goes
  VERTICAL on the trailing edge; the pill survives at the bottom but ~290pt wide while still `.expanded`, so
  all five controls leave the title at "Aw…" (`PillLayout` sheds controls by placement only — defect).
  Inner display — **landscape when unfolded flat (2853×2007 px ≈ 951×669pt)**, NOT the quoted 626×890;
  pill fine; **the full-screen player overflows vertically in Soundboard/Tape Room/Shoebox/Click Wheel**
  (header + bottom row off-screen — no queue, no dismiss button). Only The Receiver fits. Caveat: all
  probe shots show the MONOGRAM (rigid `MonogramTile(size: 280)`); real artwork is unprobed.
- **BUILT (2026-11-05)** — gate green at `4f88075` (later `805d766`, 175 tests): both schemes warning-free,
  `AppleNugsTests` **149**. Commits: CI → `xcode-27` runner pinned to `Xcode_27.1.app` with a version
  assertion (`016a991`, **never run — first push verifies the label**); pill sheds controls by measured
  width (`25086ad`); placeholder monogram scales so the Standard player fits (`8ea1533` — this ALSO fixed a
  pre-existing ~15pt overflow on portrait iPhones whenever a track had no art); Click Wheel fits
  (`e577df3`, pure `NowPlayingFit`); groundwork (`3e7ee68`); `NowPlayingArrangement` (`722a46c`); review
  fixes (`4f88075`: playback error kept in the queue column, secondary counted not flagged).
- **Measured in the split (Duo sim, unfolded flat):** an even 50/50 of the safe area, two 433.5×635pt
  columns, each COMPACT — so the 520pt readable-width cap only fires when the player is alone on regular
  width (upright inner display). Art in the split ≈84–112pt (smallest: Click Wheel, Tape Room).
- **VERIFIED on the Duo simulator at `4f88075` (Tim folding in Device Hub, no relaunch between shots):**
  fold with the cover open → player alone on the outer display with its queue button BACK, state kept —
  **the arrangement REMOVES the secondary when it can't split** (the assumption behind
  `nowPlayingQueueBeside`; keep the counter); unfold → split and hidden button restored; folded tab root
  → pill reads "Away From th…" with prev/play/next + chevron (was "Aw…").
- **Installed on Tim's REAL Duo 2026-11-05** (`iPhone19,4`, iOS 27.2; UDID in the local `applenugs-iphone-duo` memory).
  Device-install recipe that worked, in order: Developer Mode ON (Settings → Privacy & Security; the
  phone restarts, and CoreDevice shows it `unavailable` for a minute after — wait, don't re-pair);
  build against the SPECIFIC device — `-destination 'platform=iOS,id=<udid>' -allowProvisioningUpdates
  -allowProvisioningDeviceRegistration` — because a `generic/platform=iOS` build never registers a new
  phone and the install then fails with `0xe8008012 … profile cannot be installed on this device`; and a
  pending Program License Agreement blocks device registration outright ("PLA Update available") until
  Tim accepts it at developer.apple.com/account. `xctrace` kept listing the phone "offline" while
  `devicectl list devices` correctly showed it `available (paired)` — trust `devicectl` for this.
- **Real-Duo pass (Tim, 2026-11-05):** ✓ split with real art + ALAC; ✓ upright (then player-alone);
  ✓ pill panel; ✓ Split View beside another app (player alone at half width); ✗ swipe-down never worked
  on any iPhone → **added** (`e51c771`). Tim then asked for the **queue column upright too** → `fd2aa01`
  (sim upright 669×951pt → 409 + 260pt columns; every player verified at a forced 300pt column; also fixed
  Click Wheel's pad never shrinking below 330pt — a max-only frame reports max(child, proposal)). 173 tests.
- **Still unverified:** swipe-down on hardware (esp. drags that START on a slider thumb or a button);
  upright columns on the real Duo (its status strip is on the trailing edge, so ~535pt → 300 + 235);
  rotating upright↔flat with the cover open (rebuilds the player — documented trade-off); book pose;
  the queue sheet on the inner display; CI's first run.
- **Simulator facts:** the Duo needs its OWN runtime, iOS 27.1 `24A94425` (Duo-only; the general 27.2
  runtime can't create a Duo). Xcode 27 has no Simulator.app — Device Hub; folding/rotating are on-screen
  controls only (no `simctl` posture command), so pose changes need Tim. `simctl io … screenshot` needs
  `--display=1` (outer) or `--display=3` (inner). The iOS 26.2 runtime was deleted 2026-11-05 to free disk.

**v1.5 (build 6) is RELEASED** (bump `943f573`, appcast `305b64f`): the clickable now-playing
metadata (`22aab49` artist/show line, `cfe9957` pill + Home hero) and the inspector Signal
constant-shape fix (`9c5e8d3`). The Sparkle 1.4→1.5 loop was not re-validated in-session;
the pipeline is the same validated Path B as v1.3/v1.4 below.

**`DeepLinkMatch.normalize` now carries the SITE's venue rule** (`59efbd1`, pushed, CI green
at 131 tests): apostrophes (ASCII + U+2019) deleted outright, every other non-alphanumeric
run collapsed to one space — so "Slim's" matches a hint of "Slims" and "St-Denis" keeps
matching "St Denis". The rule ALSO feeds `bestTrackIndex` (an improvement there: "Hót-Tea!"
→ "hot tea"). Decision + evidence live in goosealmanac's
`docs/superpowers/specs/2026-08-18-nugs-web-links-design.md`; don't "simplify" it back to
delete-all-punctuation — that was the old, weaker rule.

**Cross-repo, same day (matters to this app's deep-link story):** goosealmanac shipped
exact nugs.net web links (nightly catalog import → `shows.nugs_container_id`;
`play.nugs.net/release/<id>` fallbacks; an "Open on nugs.net" chip) and a `/listen-links`
page documenting the whole button family including `applenugs://` — merged as PR #12
(`ee4ec13`), live in production, first import verified (476 of 855 shows resolved,
2026-08-18). The deep-link contract doc (`docs/integrations/applenugs-deeplink.md` there)
was corrected: its web-fallback section, and the fictional "presents the matches" picker —
**this app has no picker; `DeepLinkRouter` takes the first same-date match when no usable
venue hint is given.** If a picker ever gets built, update that doc and the site's
`/listen-links` copy. Residue: Tim verified the app-less
fallback on 2026-08-18 — a machine without AppleNugs forwards to nugs.net after the ~1.2s
race, as designed. Still owed: signed-in spot-check of `play.nugs.net/release/46887|46884|46883`.

### Earlier state (2026-08-10 → 2026-08-17, still-true details below)

**The iOS now-playing pill is SHIPPED — merged and pushed.** `main` == `origin/main` == `11dae49`, tree clean, no worktrees, no stale branches. The 10-task plan (`docs/superpowers/plans/2026-08-10-ios-nowplaying-pill.md`, spec `docs/superpowers/specs/2026-08-10-ios-nowplaying-pill-design.md`, both gitignored/local-only) replaced the iOS full-width bottom transport bar with a Liquid Glass pill hosted in `tabViewBottomAccessory`. Both defects the iOS parity review diagnosed are structurally gone: the pill lives on the `TabView`, so it rides above pushed detail screens for free, and the toast's hardcoded `.padding(.bottom, 78)` is replaced by a plain `8` anchored to the NavigationStack.

**The pill's progress ring is MERGED and PUSHED** (2026-08-11; `main` == `origin/main` == `7d2c318`, tree clean, branch deleted). Reviewed clean; **device verification is PARTIAL — see below.** Spec `docs/superpowers/specs/2026-08-10-pill-progress-ring-design.md`, plan `docs/superpowers/plans/2026-08-10-pill-progress-ring.md` (both gitignored/local-only). `PillSeekEdge` is deleted entirely (drag, 20pt hit strip, hairline) — scrubbing belongs to the expanded panel and the full-screen player, both of which have real sliders. In its place `PillProgressRing` draws a 2pt arc around the 32pt leading slot, tinted `theme.effectiveAccent(art:)`, empty when `duration <= 0` (a full ring on a no-duration stream would read as "finished" — same defect `11dae49` fixed on the sliders). **`PillLeadingSlot` collapsed from five themed variants to one uniform `ArtChip`**; **no themes were removed** (considered and explicitly rejected) — theme identity stays in the full-screen player, palette, type and the Mac miniplayer. `PillLayout.seekEdgeHeight` / `seekHitHeight` / `controlsTrailingInset` and their three tests are gone; `ringLineWidth`/`ringGap`/`artChipSize(slot:)`/`progressFraction(currentTime:duration:)` replace them. Gate at HEAD: both schemes `** BUILD SUCCEEDED **` warning-free, `AppleNugsTests` `** TEST SUCCEEDED **` at **98 tests**.

**One design decision worth not re-deriving: the art chip is clipped to a CIRCLE.** `artChipSize` yields 26pt as an *inscribed-circle diameter*, but `ArtChip` renders a rounded square whose corners reach r≈16.9 against the ring's inner edge at r=14 — so a square chip put the accent arc on top of the cover across roughly half its circumference, worst on the art-driven themes where the arc *is* the cover's dominant color. `.clipShape(Circle())` (applied before the 32pt `.frame`, so it clips the 26pt chip) holds the 1pt `ringGap` at every angle. The rejected alternatives were a ~20pt square (clears the ring but wastes the slot) and a rounded-rect track (non-uniform angular speed).

**Device verification — what's CONFIRMED on a real iPhone 16 Pro (iOS 27.0, real logged-in session, 2026-08-11):** the circular art chip renders clean with **no keyline slivers** at 12/3/6/9 — that computed-remnant worry is closed, `ArtChip` needs no `shape` parameter; the **background track ring renders** with its gap holding all the way around (no arc-on-artwork, which was the whole point of the circle clip); chevron → `ExpandedPlayerPanel` still reaches scrub row, five controls, favorite star, ALAC badge, AirPlay and Queue. `\.artColor` is reaching the app generally — the tab tint picked up the cover's magenta, not the amber fallback.

**Still UNCONFIRMED, and the one that matters:** the **accent arc itself**. Every screenshot so far was taken seconds into a 25-minute track, where the fraction is ~0.013 → an arc of about 4.6°, i.e. a pixel and a half. **The test is: scrub to ~50%, then look at the pill.** Half the ring in the cover's accent = the arc advances AND `effectiveAccent(art:)` resolves inside the tab accessory (which nothing had ever read there before). Half the ring in amber = `\.artColor` is not propagating into `tabViewBottomAccessory` and needs fixing. Also still owed: ring **empty, not full**, on a no-duration stream (livestream/webcast — the one case with a real defect behind it); legibility at `.inline`; the ~0.25s stepping (the trim has no `.animation` by design — add one if it stutters); gestures (the pill now has NO drag gesture at all, so a vertical swipe should go straight to the tab bar's scroll-to-minimize); and the offline Downloads sheet mount.

**Known accepted cost:** VoiceOver loses the pill's at-a-glance position *value* — the deleted seek edge exposed "Playback position" + a formatted `accessibilityValue`, and the ring is `accessibilityHidden`. Nothing became unreachable (both accessibility actions are applied unconditionally on the `onExpand != nil` path, including at `.inline`, and both destinations have real sliders), but the announcement is genuinely gone.

**iOS deployment floor is 26.1** (raised from 17.0 — `tabViewBottomAccessory(isEnabled:)`, the overload that reclaims the slot when nothing is playing, is 26.1+; the plain `content:` overload is 26.0 but can't free the 48pt slot. See the comment in `project.yml`). `TransportBar`'s iOS `compactBar`/`MiniProgressStrip`/`compactNowPlayingBlock` are deleted; `TransportBar` renders `EmptyView` on iOS. `TransportBar.format(seconds:)` and `NowPlayingFavorite` stay — used on both platforms.

**What the pill is:** a glass capsule in `AppleNugs/iOS/NowPlayingPill/` (`PillLayout` is pure policy, SwiftUI-free, compiled into `AppleNugsTests` directly): a 32pt leading slot (one uniform `ArtChip`, circle-clipped, wrapped in `PillProgressRing`), title + artist, five transport controls, and a trailing chevron. No seek affordance — see the ring note above. Tap opens the full-screen `NowPlayingScreen`; the chevron opens `ExpandedPlayerPanel` (art, title, venue, favorite star, scrub row, five controls, AirPlay, format badge, Queue → `DashboardPanel`). At `.inline` it degrades to title-only + play/pause + next per `PillLayout`'s pure degradation table. The offline Downloads sheet mounts the pill by hand with `onExpand: nil` (sheets can't host a tab accessory) — the one legitimate duplicate.

**Three hard-won facts, don't re-derive them.** (1) **`tabViewBottomAccessory` measures 360×48pt expanded, 284×48pt inline; the height is system-owned with no API knob** — see the `applenugs-ios-tab-accessory-geometry` memory. (2) **A `.sheet` attached INSIDE the accessory runs its content's body but never appears** — the accessory is a system-hosted container, not a presentation context; the shell presents the panel and the pill takes an injected `onExpand`. (3) **The drag-up gesture loses to the tab bar's own scroll-to-minimize handling** — that's why there's a chevron. Also: `TabBarMinimizeBehavior` has only `.automatic/.onScrollDown/.onScrollUp/.never` — there is no "always minimized", so a permanently one-row bottom is not reachable without abandoning the accessory.

**Verified on a real iPhone 16 Pro (iOS 27.0), with a real logged-in session:** the pill survives a push to `ArtistDetailView` (the core fix); tap opens the full-screen player; the transport buttons keep their own taps (the container tap does NOT steal them — measured both ways); the chevron opens the panel and its Queue button reaches `DashboardPanel`; the panel is legible with real art and an art-driven accent; drag-to-seek on the pill's edge worked (that affordance has since been **replaced by the progress ring** — see above, so this line is history, not current behaviour); and **the `.inline` collapse works and looks good** — tab bar shrinks to the Home button with the pill folded in beside it. All five themes verified at the tab root in the simulator. Gate: both schemes `** BUILD SUCCEEDED **` warning-free under `SWIFT_STRICT_CONCURRENCY=complete` bar the known `appintentsmetadataprocessor` one; `AppleNugsTests` `** TEST SUCCEEDED **` at **94 tests**.

**Still unverified, honestly:** the offline Downloads sheet's pill (needs a real `.connectionFailed` state), VoiceOver behaviour anywhere in the pill, Dynamic Type at accessibility sizes against the panel's fixed `.height(250)` detent, and the keyboard-up triple-stacked-chrome risk carried over from the parity review. Evidence ledger + screenshots + all task briefs/reports/review diffs: `docs/superpowers/pill-artifacts/` (gitignored, local-only).

**`11dae49` fixed a cross-cutting scrub bug:** `sliderMax = max(duration, 1)` meant a stream reporting no duration pinned the thumb hard right, reading as "finished". Fixed on four iOS surfaces (`NowPlayingScreen`, `ClickWheelScreen`, `TouchFaceplate`, `ExpandedPlayerPanel`), and **the two macOS surfaces are now fixed too** — `FaceplateTransport` and `TransportBar.seekBlock` (`be51ccf`, merged to main). **All six scrub surfaces now carry the same guard**; grep `player.duration > 0 ? min(player.currentTime, sliderMax) : 0` to confirm the count is still six if you add a seventh slider.

**TOOLCHAIN — check it, don't assume it.** **As of 2026-11-05 `xcode-select` points at Xcode 27.2** (`/Applications/Xcode.app`, iOS SDK 27.2, Swift 6.4.2); unchanged `origin/main` builds both schemes warning-free on it. The 26.6 note that follows is history. As of 2026-08-17 `xcode-select` points at the **stable** `/Applications/Xcode.app/Contents/Developer` (Xcode 26.6, build 17F113), which is also what CI now uses, so local and CI agree. The durable fact behind the old warning still holds: **CoreDevice's developer disk image comes from the *selected* Xcode, not from `DEVELOPER_DIR`**, so installing to Tim's iPhone while it runs a newer iOS than the stable SDK supports means selecting the beta first — and switching back before any release work, since the notarized DMG and Sparkle build from the same `project.yml`:

```sh
xcode-select -p                                                    # check first
sudo xcode-select -s /Applications/Xcode-beta.app/Contents/Developer   # device install
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer        # back for releases
```

**Device-install recipe that actually worked** (`APPLENUGS_TEAM_ID=<team> xcodegen generate`, then `xcodebuild -destination 'generic/platform=iOS' -allowProvisioningUpdates`, then `xcrun devicectl device install app`): `devicectl list devices` showed a **stale identifier stuck at `connecting` forever** and every call against it hung. `xcrun xctrace list devices` reveals the **real** UDID (`00008140-…`) and the device's iOS version. The actual unblocker was **untrust + retrust on the phone**, which rebuilt the pairing record; a connected VPN turned out NOT to be the problem.

**v1.4 (build 5) is RELEASED and live (2026-08-13).** Payload for Mac users is exactly one thing: `be51ccf`, the duration-less scrub fix ported to `FaceplateTransport` and `TransportBar.seekBlock`. (The pill/ring work is in the same tag but is iOS-only, and iOS is personal-install — a v1.4 was **held** on 2026-08-11 precisely because there was no macOS payload yet.) Pipeline ran clean end to end: bump `49f69d6` → `xcodegen` → `verify-sparkle-config.sh` green → archive → export → app notarize **Accepted** + staple + `spctl` (`accepted, source=Notarized Developer ID`, `flags=0x10000(runtime)`) → DMG → codesign DMG → notarize **Accepted** + staple + `spctl -t open` → push bump BEFORE `gh release create v1.4` → `AppleNugs-1.4.dmg` uploaded (4,043,765 bytes, state=uploaded) → `sparkle-appcast.sh` → appcast `048ea45` pushed. Raw feed served build 5 immediately, enclosure `length` byte-matching the asset, download URL `HTTP 200`. **The Sparkle loop WAS then exercised for real and works** (2026-08-13, same session): the installed v1.3 offered 1.4 ("AppleNugs 1.4 is now available\u2014you have 1.3"), downloaded, installed and relaunched on 1.4 \u2014 third end-to-end validation of the update path after v1.0\u2192v1.1 and v1.2\u2192v1.3. **And the payload itself is verified on the shipped build:** with a real duration-less track ("So Ready", elapsed 3:56, remaining `--:--`), the transport thumb sat pinned hard right on 1.3 and rests at 0 on 1.4 \u2014 same track, same session, before/after in one pass. `be51ccf` is confirmed working in production, not just building.

**Two release-pipeline gotchas that cost time on v1.4 — don't rediscover them.** (1) **`ExportOptions-DeveloperID.plist` in the repo is a TEMPLATE with a literal `TEAMID` placeholder**, so `-exportArchive` fails with the very misleading `No signing certificate "Developer ID Application" found` even though `security find-identity` lists the cert fine. Generate a resolved copy into gitignored `build/` (`sed 's|<string>TEAMID</string>|<string>$APPLENUGS_TEAM_ID</string>|'`) and point `-exportOptionsPlist` at that; leave the template alone. (2) **`rm -rf build` before archiving also deletes Sparkle's `generate_appcast`**, and `sparkle-appcast.sh` then dies with "generate_appcast not found at build/sparkle-tools/bin". SPM restores it during the archive at `build/SourcePackages/artifacts/sparkle/Sparkle/bin` — pass it via the script's `SPARKLE_TOOLS` env override rather than hunting (a bare `find /` for it takes >5 minutes).

**v1.3 (build 4) is RELEASED and live (2026-08-10).** Same validated Path-B pipeline, clean end to end: bump `c862d0c` → `xcodegen` → `verify-sparkle-config.sh` green → Developer ID archive → export → app notarize **Accepted** + staple + `spctl` → `hdiutil` DMG → codesign DMG → notarize **Accepted** + staple + `spctl -t open` → push bump BEFORE `gh release create v1.3` → `AppleNugs-1.3.dmg` uploaded (asset 200) → `sparkle-appcast.sh` → appcast `82f228d` pushed; the raw feed served build 4 immediately, enclosure `length` matching the asset byte-for-byte. **The Sparkle loop was then exercised for real and works:** the installed v1.2 offered 1.3 ("AppleNugs 1.3 is now available—you have 1.2"), downloaded, installed, and relaunched on 1.3 — signature, feed, and build-number comparison all validated in the actual client, not just via `curl`.

**Contents of v1.3 — the macOS video full-screen toggle** ([PR #3](https://github.com/tsvb/applenugs/pull/3), merged `454c49c`+`e39222d`). `AVPlayerView.showsFullScreenToggleButton` defaults to NO and was never set, so the Mac video surface had no full-screen affordance at all. Second commit defers the end-of-playback arbiter hand-back while full screen — otherwise a video finishing there resumes the audio queue behind a window the viewer can't see past. **AVKit gives macOS no programmatic full-screen control**: no enter method, no exit method, no state property, only the four `AVPlayerViewDelegate` notifications — so there is no macOS equivalent of iOS's `exitsFullScreenWhenPlaybackEnds`, and app-drawn chrome would need the unrelated `NSView.enterFullScreenMode` path. Don't re-litigate this without re-reading the header.

**Verification on v1.3, and what's still open.** Tim confirmed the full-screen button works and playback keeps running across the transition — first on the signed pre-release build, then again on the installed 1.3 after updating — so the `onDisappear`-teardown risk did NOT materialize. Two things were never exercised and remain unproven: **layout/LIVE-badge restore on exit**, and **the end-in-full-screen audio case** (video finishes full screen with the audio queue previously playing → nothing should start underneath, and audio should resume on exit). That deferral logic also has **no unit test** — `VideoPlayerService` pulls in `PlayerService`/`NugsClient`/`VideoProgressStore` and `AppleNugsTests` is host-free. Note the harness limitation recorded in the `applenugs-swiftui-hypothesis-testing` memory: **AVKit renders its floating controls out-of-process**, so subview walks, AX walks, and `cacheDisplay` PNGs are all blind to them — don't burn time re-deriving that.

**Previously — the miniplayer visual-verification campaign (2026-08-01) is CLOSED.** All 15 checklist items got verdicts (evidence ledger: `docs/superpowers/miniplayer-artifacts/reports/verification-campaign-report.md`; contact sheet beside it; renders in `../renders/`). It was run three ways: an offscreen `swiftc`+`NSHostingView` harness extended to **PNG capture** via `NSWindow.cacheDisplay` (41 renders — needs no login or Screen Recording, and reaches states the live app can't), a seeded live walkthrough, and a real-playback session on a Developer ID-signed local build with the real session (real art, VU sway, drag-to-seek, 4Hz, stability, CPU all verified live). **One real defect found and fixed (`ef33039`):** ReelHub's splines were textPrimary-on-textPrimary, so reel rotation was invisible at any speed — exactly the class of bug the campaign existed to catch. A short human-residue checklist for Tim (VoiceOver, focus rings, divider/drag feel, window floor) is the last section of the ledger.

**The iOS parity review's now-playing-bar findings are RESOLVED by the pill work above, on this branch.** Original brief: `docs/superpowers/specs/2026-08-01-ios-parity-review-brief.md` (screenshots in `docs/superpowers/ios-parity-artifacts/`) diagnosed **two real defects + one risk** in the old full-width bar: the toast's hardcoded `.padding(.bottom, 78)` drew it ON the bar; the bar vanished on every pushed detail screen (the `safeAreaInset` wrapped the NavigationStack root, not the stack); and keyboard-up likely triple-stacked chrome (was unverified then — needs taps, and is **still unverified now**, not exercised by this pass either). The pill's `tabViewBottomAccessory` placement fixes the first two structurally (see "This worktree" above) and also answers the review's design question — ~138-144pt of flush bottom chrome against iOS 26's floating tab capsule — by replacing the flush bar with a floating capsule instead of trying to slim the old shape down. The keyboard-up interaction remains the one open item from that review this branch didn't specifically re-check.

**Also parked:** `docs/superpowers/miniplayer-artifacts/` holds the spec, plan, all task reports, the SDD ledger, and the brainstorm mockups (gitignored, local only). Known follow-ups with no owner: shuffle and repeat (which should first collapse the *three* partial transport-control implementations — see the player-backlog memory), a buffering state for the faceplate's knurled play button, and a `!isUITestRun` guard for `PlaybackStateStore` (see the nowplaying-clobber memory — a seeded launch already ate the real resume queue once).

**When verifying UI here:** launching the app is fine, but always quit it afterward, don't grind on stuck GUI automation, and never enter credentials at a Keychain prompt — see the `applenugs-no-gui-automation` memory. Screenshot capture works when the Claude app has Screen Recording; synthetic split-divider drags and AX window-width resizes remain unreliable. **Magnet's invisible overlay swallows synthetic clicks** — quit it for the session (relaunch after). For live runs: build Developer ID-signed (ad-hoc crashes on Sparkle AND prompts for the Keychain), launch the built app by explicit path, and back up `nowplaying.json` first (Tim must copy it — the container is TCC-blocked for the shell; Finder driven via `open -R` + allowlisted copy/paste works too). For pure layout questions the `swiftc` + `NSHostingView` harness is usually the better tool — and it can render PNGs now (recipe in the verification ledger; remember `.themed()` does NOT set the `\.theme` environment key, and use `cacheDisplay`, not `ImageRenderer`).
