# Inside-the-Jam Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add relative seek (skip ±15/30s, keyboard seek, Control Center skip) for fine in-track navigation.

**Architecture:** One `seek(by:)` primitive on `PlayerService` that all surfaces ride; skip buttons added directly to each transport's `controls`; arrow/digit handling in the existing key monitor; `MPSkip*Command` registration. No shared-subview refactor in this slice.

**Tech Stack:** Swift 5 / SwiftUI (macOS 14), AVFoundation, MediaPlayer.

**Testing approach:** No XCTest target. Verify each task with:
```bash
cd /Users/tim/applenugs && xcodegen generate >/dev/null 2>&1 && xcodebuild -project AppleNugs.xcodeproj -scheme AppleNugs -configuration Debug build 2>&1 | grep -E "(error:|warning: .*Swift|BUILD SUCCEEDED|BUILD FAILED)" | tail -15
```
Expected: `** BUILD SUCCEEDED **`, no `error:` / Swift `warning:` lines.

**Branch:** `player-inside-the-jam`. Commit after every task.

---

## Task 1: Relative seek primitive + Control Center skip commands

**Files:** Modify `AppleNugs/Player/PlayerService.swift`

- [ ] **Step 1: Add `seek(by:)`**

After the existing `seek(to:)` method:

```swift
    func seek(to seconds: Double) {
        let t = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = max(0, seconds)
        pushNowPlayingInfo()
    }
```

add:

```swift
    /// Relative seek, shared by the skip buttons, keyboard, and Control Center.
    /// No-op until a duration is known.
    func seek(by delta: Double) {
        guard duration > 0 else { return }
        seek(to: min(max(currentTime + delta, 0), duration))
    }
```

- [ ] **Step 2: Register skip commands**

In `registerRemoteCommands()`, before the closing `}` of the method (after the `changePlaybackPositionCommand` block):

```swift
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  let event = event as? MPChangePlaybackPositionCommandEvent
            else { return .commandFailed }
            self.seek(to: event.positionTime)
            return .success
        }

        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self, self.current != nil else { return .noActionableNowPlayingItem }
            self.seek(by: -15)
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [30]
        center.skipForwardCommand.addTarget { [weak self] _ in
            guard let self, self.current != nil else { return .noActionableNowPlayingItem }
            self.seek(by: 30)
            return .success
        }
    }
```

- [ ] **Step 3: Build.** Run the standard build command. Expected `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit.**
```bash
git add AppleNugs/Player/PlayerService.swift
git commit -m "Add relative seek(by:) and Control Center skip commands"
```

---

## Task 2: Skip buttons in the standard transport

**Files:** Modify `AppleNugs/Views/TransportBar.swift`

- [ ] **Step 1: Add skip buttons to `controls`**

Replace the `controls` computed property:

```swift
    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
            }
            .disabled(!player.hasPrevious)
            .help("Previous (p)")

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 24)
            }
            .disabled(player.current == nil)
            .help("Play / pause (space)")

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
            }
            .disabled(!player.hasNext)
            .help("Next (n)")
        }
        .buttonStyle(.borderless)
    }
```

with:

```swift
    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
            }
            .disabled(!player.hasPrevious)
            .help("Previous (p)")

            Button {
                player.seek(by: -15)
            } label: {
                Image(systemName: "gobackward.15")
            }
            .disabled(player.current == nil)
            .help("Back 15s (←)")

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 24)
            }
            .disabled(player.current == nil)
            .help("Play / pause (space)")

            Button {
                player.seek(by: 30)
            } label: {
                Image(systemName: "goforward.30")
            }
            .disabled(player.current == nil)
            .help("Forward 30s (→)")

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
            }
            .disabled(!player.hasNext)
            .help("Next (n)")
        }
        .buttonStyle(.borderless)
    }
```

- [ ] **Step 2: Build.** Expected `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit.**
```bash
git add AppleNugs/Views/TransportBar.swift
git commit -m "Add skip back-15/forward-30 buttons to the standard transport"
```

---

## Task 3: Skip buttons in the faceplate transport

**Files:** Modify `AppleNugs/Theme/Transport/FaceplateTransport.swift`

- [ ] **Step 1: Add knurled skip buttons to `controls`**

Replace the `controls` computed property:

```swift
    private var controls: some View {
        HStack(spacing: 12) {
            KnurledButton(system: "backward.fill", size: 30, glow: false) { player.previous() }
                .disabled(!player.hasPrevious)
            KnurledButton(
                system: player.isPlaying ? "pause.fill" : "play.fill",
                size: 40, glow: player.isPlaying) { player.togglePlayPause() }
                .disabled(player.current == nil)
            KnurledButton(system: "forward.fill", size: 30, glow: false) { player.next() }
                .disabled(!player.hasNext)
        }
    }
```

with:

```swift
    private var controls: some View {
        HStack(spacing: 12) {
            KnurledButton(system: "backward.fill", size: 30, glow: false) { player.previous() }
                .disabled(!player.hasPrevious)
            KnurledButton(system: "gobackward.15", size: 26, glow: false) { player.seek(by: -15) }
                .disabled(player.current == nil)
            KnurledButton(
                system: player.isPlaying ? "pause.fill" : "play.fill",
                size: 40, glow: player.isPlaying) { player.togglePlayPause() }
                .disabled(player.current == nil)
            KnurledButton(system: "goforward.30", size: 26, glow: false) { player.seek(by: 30) }
                .disabled(player.current == nil)
            KnurledButton(system: "forward.fill", size: 30, glow: false) { player.next() }
                .disabled(!player.hasNext)
        }
    }
```

- [ ] **Step 2: Build.** Expected `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit.**
```bash
git add AppleNugs/Theme/Transport/FaceplateTransport.swift
git commit -m "Add knurled skip buttons to the faceplate transport"
```

---

## Task 4: Keyboard seek (arrows + digits)

**Files:** Modify `AppleNugs/App/KeyboardShortcuts.swift`

- [ ] **Step 1: Add arrow + digit seek to `handle`**

The current code after the modifier guard is:

```swift
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
            return event
        }

        switch event.charactersIgnoringModifiers {
        case " ":
            app.player.togglePlayPause()
            return nil
        case "n":
            app.player.next()
            return nil
        case "p":
            app.player.previous()
            return nil
        case "/":
            ui.requestSearchFocus()
            return nil
        default:
            return event
        }
```

Replace it with (arrows by keyCode so Shift can modify the step; digits via characters):

```swift
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
            return event
        }

        // Arrow-key seek (bare = ±10s, Shift = ±30s). cmd-ctrl-arrows already
        // own whole-track prev/next and are excluded by the guard above.
        let shift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 123:  // left arrow
            app.player.seek(by: shift ? -30 : -10)
            return nil
        case 124:  // right arrow
            app.player.seek(by: shift ? 30 : 10)
            return nil
        default:
            break
        }

        switch event.charactersIgnoringModifiers {
        case " ":
            app.player.togglePlayPause()
            return nil
        case "n":
            app.player.next()
            return nil
        case "p":
            app.player.previous()
            return nil
        case "/":
            ui.requestSearchFocus()
            return nil
        case "0":
            app.player.seek(to: 0)
            return nil
        case "1", "2", "3", "4", "5", "6", "7", "8", "9":
            if let n = event.charactersIgnoringModifiers.flatMap(Int.init), app.player.duration > 0 {
                app.player.seek(to: app.player.duration * Double(n) / 10)
            }
            return nil
        default:
            return event
        }
```

- [ ] **Step 2: Build.** Expected `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit.**
```bash
git add AppleNugs/App/KeyboardShortcuts.swift
git commit -m "Add arrow and digit keyboard seek"
```

---

## Task 5: Verification

- [ ] **Step 1: Clean build.** Standard build command → `** BUILD SUCCEEDED **`, zero errors/warnings.
- [ ] **Step 2: Manual checks.** Play a show, then: skip buttons jump ∓15/30s in both the standard bar and (Receiver theme) the faceplate; `←`/`→` move ∓10s, `⇧←`/`⇧→` ∓30s, `1`–`9` jump to deciles, `0` restarts; typing in the Filter/Search field does NOT seek; controls are disabled with an empty queue; Control Center shows skip-15/30 controls.
- [ ] **Step 3:** Hand back for merge.

---

## Self-review

- `seek(by:)` defined in Task 1; used by Tasks 2/3 (buttons) and Task 4 (arrows). Consistent signature.
- `seek(to:)` (existing) used by Task 4 digits/0. Consistent.
- Skip amounts back-15/forward-30 consistent across transports and Control Center; keyboard arrows ±10/±30 per spec.
- No placeholders; full code in every step.
- Scope matches spec; no shared-subview refactor (deliberate, documented).
