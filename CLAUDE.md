# AppleNugs — guide for Claude

Native **macOS + iOS SwiftUI** client for nugs.net. Public repo `tsvb/applenugs`. Unofficial client (talks nugs.net's reverse-engineered API) — Developer ID / direct-download distribution, not App Store (5.2.2). Shipped: **v1.1** (Developer ID notarized DMG + Sparkle auto-update + iOS personal-install).

## Read first
- **Claude Code auto-memory:** this project's memory index at `~/.claude/projects/<project-slug>/memory/MEMORY.md` (loaded automatically at session start) holds the deep, current project context — parity program, distribution/release runbook, iOS port, theme system, player backlog, gotchas. Skim the notes relevant to your task before acting.

## Workflow (how every feature here is built)
`superpowers:brainstorming` → spec in `docs/superpowers/specs/` → `superpowers:writing-plans` → `superpowers:subagent-driven-development` (fresh implementer per task + per-task spec/quality review + whole-branch review). Don't skip the design/spec step, even for "simple" changes.

## Environment & build
- Work in the git **worktree** you were started in; **don't `cd` to the main checkout** (`/Users/tim/applenugs`). Merge to `main` via a fast-forward from the main checkout using `git -C`, then push (releases/pushes are Tim's call).
- `xcodegen generate` after any `project.yml` edit (`AppleNugs.xcodeproj/` is **gitignored**). Regenerate before building/opening.
- Schemes: `AppleNugs` (macOS, `-destination 'platform=macOS'`), `AppleNugs-iOS` (`-destination 'generic/platform=iOS Simulator'` or a device id), `AppleNugsTests` (host-free unit tests, 64 currently).
- **Always build/verify with a fresh `-derivedDataPath`** — incremental builds can report a false "clean". Project must stay warning-free under `SWIFT_STRICT_CONCURRENCY=complete` on **both** schemes. SourceKit "No such module 'UIKit'" on iOS-only files = per-target index noise; `xcodebuild` is authoritative.
- `docs/superpowers/` is **gitignored** (specs, plans, handoffs — local only).
- Visual verify without a login: launch with `-UITEST -UITestSeedQueue` (bypasses login, seeds a now-playing queue). Theme switcher = account menu (person icon). Dashboard = `sidebar.right` toolbar button / ⌥⌘I.
- iOS device install: `DEVELOPMENT_TEAM=U44N9ZPFP2` (paid team) + `-allowProvisioningUpdates`; **the iPhone must be UNLOCKED** or the developer disk image won't mount. Notary profile `rapple-notary`; Developer ID `…(U44N9ZPFP2)`. Full release runbook: `DISTRIBUTION.md` + the `applenugs-distribution` memory.

## Conventions worth knowing
- **Themes** (5: Soundboard, Tape Room, Shoebox, The Receiver, Click Wheel) drive personality via `theme.transport` (a `TransportSignature` enum in `AppleNugs/Theme/Theme.swift`) plus `theme.palette/type/copy/caps/washStyle`. Now-playing surfaces dispatch on it (see `AppleNugs/Views/NowPlaying/`). Reusable themed parts live in `AppleNugs/Theme/Components/` (VUMeter/KnurledButton in `FaceplateParts`, `EqualizerBars`, `ArtWashBackground`, `MonogramTile`).
- **macOS vs iOS:** `AppleNugs/macOS/` and `AppleNugs/iOS/` are per-platform (excluded from the other target); everything else is shared. Keep the untouched platform building.
- **Dashboard inspector perf:** `DashboardPanel` is a `ScrollView`+`VStack` (NOT a `List` — macOS-26 `NSTableView` reentrancy). The ~4Hz playback tick (`currentTime`) is isolated in **leaf views** (`ElapsedTimeLine`, `BufferedRow`) so the panel body / queue `ForEach` don't re-diff every frame — follow this pattern for any live-updating inspector content.
- Catalog dates are UTC-midnight instants — use `CrateSection.catalogCalendar`, not `Calendar.current` (see the `applenugs-catalog-dates-are-utc` memory).

## Active work — macOS Dashboard miniplayer (IN DESIGN)
Re-introducing a "miniplayer" that lives at the **top of the macOS Dashboard inspector**, replacing the text-only now-playing section: compact art + info + full transport (scrubber + prev/play/next), with **per-theme personality** (Receiver faceplate w/ VU meters, Click Wheel iPod dial, tape-label/j-card/standard variants). Brainstorming with Tim is done through the design direction (he loved it); **the spec is not yet written.** Full state + resume instructions: **`docs/superpowers/HANDOFF-miniplayer.md`**.
