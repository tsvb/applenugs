# Inside-the-Jam Navigation — Design

**Date:** 2026-06-13
**Status:** Approved (design); pending implementation
**Component:** AppleNugs — playback controls

## Goal

Fine-grained navigation *within* a track — the right granularity for this app's
content (20-minute jams, 3-hour shows). Today the only in-track control is a
~90px drag slider (~30s/pixel on a long jam) and whole-track prev/next. Add
relative seek reachable from mouse, keyboard, and Control Center.

## Scope

**In scope:**
- A `seek(by:)` relative-seek primitive on `PlayerService`.
- **Skip buttons** flanking play/pause in both transports: back **15s** /
  forward **30s** (asymmetric, podcast convention).
- **Keyboard seek** in the existing key monitor: `←`/`→` = ∓10s, `⇧←`/`⇧→` =
  ∓30s, digits `1`–`9` = jump to that decile, `0` = restart.
- **Control Center / AirPods** skip commands (`skipBackward` 15 / `skipForward`
  30).

**Out of scope (separate backlog items):** repeat, shuffle, sleep timer,
menu-bar controller, click-to-seek bar, queue reorder, track-count metadata.
Playback **speed** and **crossfade** are deliberate non-goals (wrong for
continuous lossless live recordings).

**Deliberate deviation from the review's suggestion:** no heavy "shared
transport subview" extraction in this slice. The standard bar (borderless SF
Symbols) and the Receiver faceplate (`KnurledButton`) are visually divergent, so
forcing one parameterized subview costs more than it saves for two skip buttons.
The skip buttons are added directly to each `controls` block. The shared
extraction is deferred to the repeat/shuffle slice, where shared toggle UI pays
off.

## Behavior

- `seek(by:)` clamps `currentTime + delta` to `0...duration` and routes through
  the existing `seek(to:)` (zero-tolerance CMTime seek + Now Playing refresh).
  No-op when `duration <= 0`.
- Skip buttons and keyboard seek are disabled / no-op when nothing is loaded.
- Keyboard: bare arrows are currently unclaimed (`⌘⌃←/→` already own whole-track
  prev/next and are untouched). Text-field passthrough is preserved — typing in
  search never triggers seek.
- Decile jump (`1`–`9`) uses `duration * n / 10`, guarded on `duration > 0`.

## Files

- `AppleNugs/Player/PlayerService.swift` — add `seek(by:)`; register
  `skipBackwardCommand`/`skipForwardCommand`.
- `AppleNugs/Views/TransportBar.swift` — two skip buttons in `controls`.
- `AppleNugs/Theme/Transport/FaceplateTransport.swift` — two knurled skip buttons in `controls`.
- `AppleNugs/App/KeyboardShortcuts.swift` — arrow + digit seek.

## Verification

No test target; verify by clean build + manual: skip buttons jump ∓15/30s;
arrows ∓10s, shift ∓30s, digits jump to deciles, 0 restarts; Control Center
shows skip controls; typing in search is unaffected; controls disabled when idle.
