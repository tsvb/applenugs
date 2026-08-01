# AppleNugs — guide for Claude

Native **macOS + iOS SwiftUI** client for nugs.net. Public repo `tsvb/applenugs`. Unofficial client (talks nugs.net's reverse-engineered API) — Developer ID / direct-download distribution, not App Store (5.2.2). Shipped: **v1.1** (Developer ID notarized DMG + Sparkle auto-update + iOS personal-install).

## Read first
- **Claude Code auto-memory:** this project's memory index at `~/.claude/projects/<project-slug>/memory/MEMORY.md` (loaded automatically at session start) holds the deep, current project context — parity program, distribution/release runbook, iOS port, theme system, player backlog, gotchas. Skim the notes relevant to your task before acting.

## Workflow (how every feature here is built)
`superpowers:brainstorming` → spec in `docs/superpowers/specs/` → `superpowers:writing-plans` → `superpowers:subagent-driven-development` (fresh implementer per task + per-task spec/quality review + whole-branch review). Don't skip the design/spec step, even for "simple" changes.

## Environment & build
- Work in the git **worktree** you were started in; **don't `cd` to the main checkout** (the repo-root clone). Merge to `main` via a fast-forward from the main checkout using `git -C`, then push (releases/pushes are the maintainer's call).
- `xcodegen generate` after any `project.yml` edit (`AppleNugs.xcodeproj/` is **gitignored**). Regenerate before building/opening.
- Schemes: `AppleNugs` (macOS, `-destination 'platform=macOS'`), `AppleNugs-iOS` (`-destination 'generic/platform=iOS Simulator'` or a device id), `AppleNugsTests` (host-free unit tests, 81 currently).
- **Always build/verify with a fresh `-derivedDataPath`** — incremental builds can report a false "clean". Project must stay warning-free under `SWIFT_STRICT_CONCURRENCY=complete` on **both** schemes. SourceKit "No such module 'UIKit'" on iOS-only files = per-target index noise; `xcodebuild` is authoritative.
- `docs/superpowers/` is **gitignored** (specs, plans, reports — local only, and therefore NOT a safe place for handoff state: a worktree removal deletes it. Durable session state belongs in this file plus the auto-memory index).
- Visual verify without a login: launch with `-UITEST -UITestSeedQueue` (bypasses login, seeds a now-playing queue). Theme switcher = account menu (person icon). Dashboard = `sidebar.right` toolbar button / ⌥⌘I.
- iOS device install: `DEVELOPMENT_TEAM=U44N9ZPFP2` (paid team) + `-allowProvisioningUpdates`; **the iPhone must be UNLOCKED** or the developer disk image won't mount. Notary profile `rapple-notary`; Developer ID `…(U44N9ZPFP2)`. Full release runbook: `DISTRIBUTION.md` + the `applenugs-distribution` memory.

## Conventions worth knowing
- **Themes** (5: Soundboard, Tape Room, Shoebox, The Receiver, Click Wheel) drive personality via `theme.transport` (a `TransportSignature` enum in `AppleNugs/Theme/Theme.swift`) plus `theme.palette/type/copy/caps/washStyle`. Now-playing surfaces dispatch on it (see `AppleNugs/Views/NowPlaying/`). Reusable themed parts live in `AppleNugs/Theme/Components/` (VUMeter/KnurledButton in `FaceplateParts`, `EqualizerBars`, `ArtWashBackground`, `MonogramTile`).
- **macOS vs iOS:** `AppleNugs/macOS/` and `AppleNugs/iOS/` are per-platform (excluded from the other target); everything else is shared. Keep the untouched platform building.
- **Dashboard inspector perf:** `DashboardPanel` is a `ScrollView`+`VStack` (NOT a `List` — macOS-26 `NSTableView` reentrancy). The ~4Hz playback tick (`currentTime`) is isolated in **leaf views** so the panel body / queue `ForEach` don't re-diff every frame. The only views permitted to read `currentTime` are `MiniPlayerScrubTrack`, `MiniPlayerClock`, `CassetteReels`, and the iOS-only `ElapsedTimeLine`/`BufferedRow` — follow this pattern for any live-updating inspector content, and never hoist the read into a host or variant body.
- **`DashboardPanel.swift` is SHARED, not macOS code.** It lives in `AppleNugs/Views/`, and iOS presents the same panel as a sheet from `ClickWheelScreen`, `NowPlayingScreen`, and `TouchFaceplate`. Anything under `AppleNugs/macOS/` called from it MUST sit behind `#if os(macOS)` or the iOS build breaks — the macOS build won't catch it.
- **Dashboard miniplayer** (`AppleNugs/macOS/MiniPlayer/`, macOS only): `DashboardMiniPlayer` dispatches on `theme.transport` to `MiniPlayerStandard` (Soundboard + Shoebox share one token-driven view), `MiniPlayerCassette`, `MiniPlayerFaceplate`, `MiniPlayerClickWheel`; shared leaves in `MiniPlayerParts.swift`, pure reel math in `TapeGeometry.swift`. The inspector column is pinned `min: 340, ideal: 340, max: 380` because a real 44-char venue string clips below 340. Tape Room's cassette holds a true **25:16** ratio with only ~19pt of slack — growing the label, the play puck, the clock font, or the reels silently yields the ratio (it has already regressed twice); the budget arithmetic is commented in `MiniPlayerCassette.swift`.
- Catalog dates are UTC-midnight instants — use `CrateSection.catalogCalendar`, not `Calendar.current` (see the `applenugs-catalog-dates-are-utc` memory).

## Pick up here — state as of 2026-08-01

**Repo:** `main` == `origin/main` == `a6d5793`, working tree clean, nothing unpushed. Worktrees present: `parity` and `livestream-surfacing` (both pre-existing, unrelated). Builds clean on both schemes; 81 tests green. The only build warning is `appintentsmetadataprocessor` ("No AppIntents.framework dependency found") — **confirmed pre-existing at `fb308c8`**, not a regression, don't chase it.

**Last shipped:** the macOS Dashboard miniplayer (`fb308c8..c29b3d7`), then a `CLAUDE.md` refresh and two `AudioFormat` cleanups (`isLossless` extracted; `impliedBitDepth` made exhaustive). Architecture is in the miniplayer bullet under Conventions.

**The one open thread — visual verification of the miniplayer.** Nothing has been seen with real cover art or during live playback: the agent sandbox has no nugs.net login and can't screenshot. So reel motion, pause-freeze, VU meters, tape-strip drag-to-seek, the 340↔380 reflow, and a VoiceOver/focus pass are all unverified by eye. A 15-item checklist is at `docs/superpowers/miniplayer-artifacts/reports/task-7-report.md`.

Treat that as real risk, not paperwork: the two worst bugs on that branch were both invisible to green builds and tests. One only surfaced when a layout harness measured the shell (340pt against a 217.6pt target); the other was a fixed literal that would have rendered `POSITION HIG…` in every Tape Room session.

**Also parked:** `docs/superpowers/miniplayer-artifacts/` holds the spec, plan, all task reports, the SDD ledger, and the brainstorm mockups (gitignored, local only). Known follow-ups with no owner: shuffle and repeat (which should first collapse the *three* partial transport-control implementations — see the player-backlog memory), and a buffering state for the faceplate's knurled play button.

**When verifying UI here:** launching the app is fine, but always quit it afterward, don't grind on stuck GUI automation (screenshot capture and synthetic split-divider drags are both unreliable on this machine), and never enter credentials at a Keychain prompt — see the `applenugs-no-gui-automation` memory. For pure layout questions a standalone `swiftc` + `NSHostingView` harness needs no GUI at all and is usually the better tool.
