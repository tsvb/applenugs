# AppleNugs — guide for Claude

Native **macOS + iOS SwiftUI** client for nugs.net. Public repo `tsvb/applenugs`. Unofficial client (talks nugs.net's reverse-engineered API) — Developer ID / direct-download distribution, not App Store (5.2.2). Shipped: **v1.1** (Developer ID notarized DMG + Sparkle auto-update + iOS personal-install).

## Read first
- **Claude Code auto-memory:** this project's memory index at `~/.claude/projects/<project-slug>/memory/MEMORY.md` (loaded automatically at session start) holds the deep, current project context — parity program, distribution/release runbook, iOS port, theme system, player backlog, gotchas. Skim the notes relevant to your task before acting.

## Workflow (how every feature here is built)
`superpowers:brainstorming` → spec in `docs/superpowers/specs/` → `superpowers:writing-plans` → `superpowers:subagent-driven-development` (fresh implementer per task + per-task spec/quality review + whole-branch review). Don't skip the design/spec step, even for "simple" changes.

## Environment & build
- Work in the git **worktree** you were started in; **don't `cd` to the main checkout** (the repo-root clone). Merge to `main` via a fast-forward from the main checkout using `git -C`, then push (releases/pushes are the maintainer's call).
- `xcodegen generate` after any `project.yml` edit (`AppleNugs.xcodeproj/` is **gitignored**). Regenerate before building/opening.
- Schemes: `AppleNugs` (macOS, `-destination 'platform=macOS'`), `AppleNugs-iOS` (`-destination 'generic/platform=iOS Simulator'` or a device id), `AppleNugsTests` (host-free unit tests, 75 currently).
- **Always build/verify with a fresh `-derivedDataPath`** — incremental builds can report a false "clean". Project must stay warning-free under `SWIFT_STRICT_CONCURRENCY=complete` on **both** schemes. SourceKit "No such module 'UIKit'" on iOS-only files = per-target index noise; `xcodebuild` is authoritative.
- `docs/superpowers/` is **gitignored** (specs, plans, handoffs — local only).
- Visual verify without a login: launch with `-UITEST -UITestSeedQueue` (bypasses login, seeds a now-playing queue). Theme switcher = account menu (person icon). Dashboard = `sidebar.right` toolbar button / ⌥⌘I.
- iOS device install: `DEVELOPMENT_TEAM=U44N9ZPFP2` (paid team) + `-allowProvisioningUpdates`; **the iPhone must be UNLOCKED** or the developer disk image won't mount. Notary profile `rapple-notary`; Developer ID `…(U44N9ZPFP2)`. Full release runbook: `DISTRIBUTION.md` + the `applenugs-distribution` memory.

## Conventions worth knowing
- **Themes** (5: Soundboard, Tape Room, Shoebox, The Receiver, Click Wheel) drive personality via `theme.transport` (a `TransportSignature` enum in `AppleNugs/Theme/Theme.swift`) plus `theme.palette/type/copy/caps/washStyle`. Now-playing surfaces dispatch on it (see `AppleNugs/Views/NowPlaying/`). Reusable themed parts live in `AppleNugs/Theme/Components/` (VUMeter/KnurledButton in `FaceplateParts`, `EqualizerBars`, `ArtWashBackground`, `MonogramTile`).
- **macOS vs iOS:** `AppleNugs/macOS/` and `AppleNugs/iOS/` are per-platform (excluded from the other target); everything else is shared. Keep the untouched platform building.
- **Dashboard inspector perf:** `DashboardPanel` is a `ScrollView`+`VStack` (NOT a `List` — macOS-26 `NSTableView` reentrancy). The ~4Hz playback tick (`currentTime`) is isolated in **leaf views** so the panel body / queue `ForEach` don't re-diff every frame. The only views permitted to read `currentTime` are `MiniPlayerScrubTrack`, `MiniPlayerClock`, `CassetteReels`, and the iOS-only `ElapsedTimeLine`/`BufferedRow` — follow this pattern for any live-updating inspector content, and never hoist the read into a host or variant body.
- **`DashboardPanel.swift` is SHARED, not macOS code.** It lives in `AppleNugs/Views/`, and iOS presents the same panel as a sheet from `ClickWheelScreen`, `NowPlayingScreen`, and `TouchFaceplate`. Anything under `AppleNugs/macOS/` called from it MUST sit behind `#if os(macOS)` or the iOS build breaks — the macOS build won't catch it.
- **Dashboard miniplayer** (`AppleNugs/macOS/MiniPlayer/`, macOS only): `DashboardMiniPlayer` dispatches on `theme.transport` to `MiniPlayerStandard` (Soundboard + Shoebox share one token-driven view), `MiniPlayerCassette`, `MiniPlayerFaceplate`, `MiniPlayerClickWheel`; shared leaves in `MiniPlayerParts.swift`, pure reel math in `TapeGeometry.swift`. The inspector column is pinned `min: 340, ideal: 340, max: 380` because a real 44-char venue string clips below 340. Tape Room's cassette holds a true **25:16** ratio with only ~19pt of slack — growing the label, the play puck, the clock font, or the reels silently yields the ratio (it has already regressed twice); the budget arithmetic is commented in `MiniPlayerCassette.swift`.
- Catalog dates are UTC-midnight instants — use `CrateSection.catalogCalendar`, not `Calendar.current` (see the `applenugs-catalog-dates-are-utc` memory).

## Active work — macOS Dashboard miniplayer (BUILT, awaiting visual sign-off)
Merged to local `main` @ `c29b3d7` (2026-08-01, 13 commits) and **not pushed** — that's the maintainer's call. Replaces the inspector's text-only now-playing section with a per-theme miniplayer; see the miniplayer bullet under Conventions for the architecture.

**What's left:** nothing was ever seen with real cover art or during live playback (the agent sandbox has no nugs.net login and can't screenshot), so reel motion, pause-freeze, VU meters, tape-strip drag-to-seek, and the 340↔380 reflow are all unverified. A 15-item checklist is at `docs/superpowers/miniplayer-artifacts/reports/task-7-report.md`, alongside the spec, plan, every task report, the SDD ledger, and the brainstorm mockups.

**When verifying UI here:** launching the app is fine, but always quit it afterward, don't grind on stuck GUI automation, and never enter credentials at a Keychain prompt (see the `applenugs-no-gui-automation` memory). For pure layout questions a standalone `swiftc` + `NSHostingView` harness is faster and needs no GUI — it caught two real sizing bugs on this feature that builds could not.
