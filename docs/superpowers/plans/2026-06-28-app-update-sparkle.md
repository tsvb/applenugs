# Sparkle In-App Auto-Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire one-click in-app auto-update into AppleNugs using the Sparkle framework, end-to-end from the SwiftUI menu item to the signed appcast release flow.

**Architecture:** Add Sparkle 2.x via SPM. `AppleNugsApp` owns an `SPUStandardUpdaterController` (started at launch) and exposes a "Check for Updates…" menu item whose enabled state mirrors the updater via a small `ObservableObject`. Updates are EdDSA-signed; the public key ships in Info.plist, the private key stays in the maintainer's Keychain. A `generate_appcast`-based release step signs each DMG and writes the `appcast.xml` feed.

**Tech Stack:** Swift 5 / SwiftUI / Combine, Sparkle 2.x (SPM), XcodeGen, `xcodebuild`, Sparkle CLI tools (`generate_keys`, `generate_appcast`).

## Global Constraints

These apply to **every** task (copied from the spec and `project.yml`):

- **Deployment target:** macOS 14.0. **Language:** `SWIFT_VERSION = 5.0`.
- **`SWIFT_STRICT_CONCURRENCY = complete`** — the build must stay warning-free for `AppleNugs/` sources (external package warnings excluded).
- **Generated artifacts are git-ignored — never hand-edit or commit them:** `AppleNugs.xcodeproj`, `AppleNugs/Info.plist`, `AppleNugs/AppleNugs.entitlements`. Edit `project.yml` and run `xcodegen generate`.
- **Bundle identifier:** `com.timvbs.applenugs`.
- **Sparkle version floor:** `2.6.0` (SPM `from: "2.6.0"`, i.e. `>=2.6.0 <3.0.0`).
- **Sandbox is preserved:** keep `com.apple.security.app-sandbox` + `com.apple.security.network.client`; add only the Sparkle mach-lookup exception.
- **App Store is a non-goal** — the `temporary-exception` entitlement is intentional and fine for Developer ID.
- **`build/` is git-ignored** — all keys, tools, logs, and enclosures live there and never enter git.
- **Repo:** `tsvb/applenugs`, private now → public soon. The feed is dormant until public; do not treat a 404 feed as a failure.
- **Pushes/releases are gated on the maintainer (Tim).** Tasks commit locally; no `git push`.

**Verification model:** No XCTest target exists. "Tests" are clean builds + structural assertions on generated files. The clean-build command used throughout (fresh derived-data dir so an incremental build can't fake a clean result):

```bash
xcodegen generate
rm -rf build/ddp-sparkle
xcodebuild -project AppleNugs.xcodeproj -scheme AppleNugs -configuration Debug \
  -derivedDataPath build/ddp-sparkle clean build 2>&1 | tee build/ddp-sparkle.log | tail -8
# Warnings in OUR sources only (exclude the Sparkle package):
grep "warning:" build/ddp-sparkle.log | grep -v "SourcePackages" || echo "no AppleNugs warnings"
```

---

### Task 1: Generate and back up the EdDSA signing keys

One-time setup. **Run in the main checkout interactively (NOT an isolated worktree)** — `generate_keys` writes to the login Keychain and may show a Keychain prompt that Tim must approve. Produces the public key the later tasks embed.

**Files:**
- Create (git-ignored, under `build/`): `build/sparkle-tools/` (extracted CLI tools), `build/sparkle-public-key.txt`, `build/sparkle-private-key-BACKUP.txt`
- Modify: none
- Test: command output assertions

**Interfaces:**
- Consumes: nothing
- Produces: **`SPARKLE_PUBLIC_KEY`** — the base64 Ed25519 public key string (~44 chars) saved to `build/sparkle-public-key.txt`. Task 3 embeds this verbatim as `SUPublicEDKey`. The private key lives in the login Keychain (and a backup file) and is consumed by `generate_appcast` in Task 5.

- [ ] **Step 1: Download the Sparkle CLI tools into `build/`**

```bash
SPARKLE_VERSION=2.6.4   # use the latest 2.x from https://github.com/sparkle-project/Sparkle/releases
mkdir -p build/sparkle-tools
curl -L -o build/sparkle.tar.xz \
  "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
tar -xf build/sparkle.tar.xz -C build/sparkle-tools
ls build/sparkle-tools/bin   # expect: generate_keys generate_appcast sign_update ...
```

- [ ] **Step 2: Generate the keypair (creates it in the login Keychain)**

```bash
build/sparkle-tools/bin/generate_keys
```
Expected: prints a success message and a line containing your **public** key (a `<string>…</string>` you can paste into Info.plist). If a key already exists, it says so and reprints the public key. Approve any Keychain access prompt.

- [ ] **Step 3: Capture the public key to a file**

```bash
build/sparkle-tools/bin/generate_keys -p | tee build/sparkle-public-key.txt
```
Expected: the same ~44-char base64 public key, now saved. Verify it is non-empty:
```bash
test -s build/sparkle-public-key.txt && echo OK
```

- [ ] **Step 4: Export a backup of the PRIVATE key (out-of-band safekeeping)**

```bash
build/sparkle-tools/bin/generate_keys -x build/sparkle-private-key-BACKUP.txt
echo "ACTION: move build/sparkle-private-key-BACKUP.txt into a password manager, then delete the file."
```
Expected: backup file written. **This is the single point of failure** — losing the private key means no future update can ever be signed. Confirm `build/` is git-ignored:
```bash
git check-ignore build/sparkle-private-key-BACKUP.txt   # expect the path echoed back (it IS ignored)
```

- [ ] **Step 5: No commit**

Nothing in this task is committed (all outputs are under git-ignored `build/`). The public key string flows to Task 3 by hand.

---

### Task 2: Add the Sparkle SPM dependency

Wire Sparkle into the project and prove it resolves and links with no code using it yet.

**Files:**
- Modify: `project.yml` (add `packages:` section + target dependency)
- Test: clean build

**Interfaces:**
- Consumes: nothing
- Produces: the `Sparkle` module, importable in Task 4.

- [ ] **Step 1: Add the package and dependency to `project.yml`**

Add a top-level `packages:` block (sibling of `targets:`) and a dependency under the `AppleNugs` target:

```yaml
packages:
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    from: "2.6.0"
```

```yaml
targets:
  AppleNugs:
    # …existing keys…
    dependencies:
      - package: Sparkle
```

- [ ] **Step 2: Regenerate and build (resolves the package — needs network)**

```bash
xcodegen generate
rm -rf build/ddp-sparkle
xcodebuild -project AppleNugs.xcodeproj -scheme AppleNugs -configuration Debug \
  -derivedDataPath build/ddp-sparkle clean build 2>&1 | tee build/ddp-sparkle.log | tail -8
```
Expected: `** BUILD SUCCEEDED **`. First run resolves Sparkle into `build/ddp-sparkle/SourcePackages`.

- [ ] **Step 3: Confirm Sparkle resolved and linked**

```bash
ls build/ddp-sparkle/SourcePackages/checkouts/Sparkle >/dev/null && echo "Sparkle checked out"
grep "warning:" build/ddp-sparkle.log | grep -v "SourcePackages" || echo "no AppleNugs warnings"
```
Expected: "Sparkle checked out" and no AppleNugs warnings.

- [ ] **Step 4: Commit**

```bash
git add project.yml
git commit -m "build: add Sparkle 2.x as an SPM dependency"
```

---

### Task 3: Add Sparkle Info.plist keys and the sandbox entitlement

Declare the feed, public key, installer XPC service, and the mach-lookup exception that lets the sandboxed app reach it.

**Files:**
- Modify: `project.yml` (under `targets.AppleNugs.info.properties` and `targets.AppleNugs.entitlements.properties`)
- Test: clean build + structural assertions on the generated files

**Interfaces:**
- Consumes: **`SPARKLE_PUBLIC_KEY`** from Task 1 (`build/sparkle-public-key.txt`)
- Produces: a runtime-configured Sparkle feed + trust anchor.

- [ ] **Step 1: Add the Info.plist properties**

Under `targets.AppleNugs.info.properties`, add (replace `<SPARKLE_PUBLIC_KEY>` with the exact string from `build/sparkle-public-key.txt`):

```yaml
        SUFeedURL: https://raw.githubusercontent.com/tsvb/applenugs/main/appcast.xml
        SUPublicEDKey: <SPARKLE_PUBLIC_KEY>
        SUEnableInstallerLauncherService: true
```

Do **not** add `SUEnableDownloaderService` (we have `network.client`) and do **not** add `SUEnableAutomaticChecks` (leaving it unset is what gives the first-launch "check automatically?" prompt).

- [ ] **Step 2: Add the mach-lookup entitlement**

Under `targets.AppleNugs.entitlements.properties` (alongside the existing sandbox + network keys), add:

```yaml
        com.apple.security.temporary-exception.mach-lookup.global-name:
          - $(PRODUCT_BUNDLE_IDENTIFIER)-spks
          - $(PRODUCT_BUNDLE_IDENTIFIER)-spki
```

- [ ] **Step 3: Regenerate and build**

```bash
xcodegen generate
rm -rf build/ddp-sparkle
xcodebuild -project AppleNugs.xcodeproj -scheme AppleNugs -configuration Debug \
  -derivedDataPath build/ddp-sparkle clean build 2>&1 | tee build/ddp-sparkle.log | tail -8
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Assert the keys landed in the generated files**

```bash
plutil -extract SUFeedURL raw AppleNugs/Info.plist
plutil -extract SUPublicEDKey raw AppleNugs/Info.plist
plutil -extract SUEnableInstallerLauncherService raw AppleNugs/Info.plist          # expect: true
plutil -p AppleNugs/AppleNugs.entitlements | grep -A3 "mach-lookup.global-name"     # expect both -spks / -spki
```
Expected: the feed URL, the public key, `true`, and both global-name entries.

- [ ] **Step 5: Commit**

```bash
git add project.yml
git commit -m "build: declare Sparkle feed, public key, and sandbox installer entitlement"
```

---

### Task 4: SwiftUI integration — updater controller + "Check for Updates…" menu item

Own the updater in the app and surface the manual check. Automatic checks + first-launch prompt come for free from `startingUpdater: true` with `SUEnableAutomaticChecks` unset.

**Files:**
- Create: `AppleNugs/Updates/CheckForUpdates.swift`
- Modify: `AppleNugs/App/AppleNugsApp.swift`
- Test: clean build, warning-free

**Interfaces:**
- Consumes: the `Sparkle` module (Task 2); the Info.plist config (Task 3)
- Produces: `UpdaterViewModel` (main-actor `ObservableObject`, `@Published var canCheckForUpdates: Bool`, `init(updater: SPUUpdater)`); a "Check for Updates…" command.

- [ ] **Step 1: Create the view-model**

`AppleNugs/Updates/CheckForUpdates.swift`:

```swift
import Combine
import Sparkle

/// Mirrors Sparkle's `canCheckForUpdates` so the menu item enables/disables
/// correctly. Main-actor-confined — Sparkle's updater is only touched on the
/// main actor, which keeps this clean under SWIFT_STRICT_CONCURRENCY=complete.
@MainActor
final class UpdaterViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
    }
}
```

- [ ] **Step 2: Wire the updater into `AppleNugsApp`**

In `AppleNugs/App/AppleNugsApp.swift`, add the import, the two stored properties, the `init()` construction, and the command group. Resulting file:

```swift
import SwiftUI
import Sparkle

@main
struct AppleNugsApp: App {
    @State private var app = AppModel()
    @State private var ui = UIState()
    @State private var themes = ThemeManager()

    private let updaterController: SPUStandardUpdaterController
    @StateObject private var updaterModel: UpdaterViewModel

    init() {
        // Size the shared HTTP cache so the nugs CDN's cover art and video
        // posters are reused across scroll and navigation instead of re-fetched
        // — AsyncImage loads through URLSession.shared → URLCache.shared, which
        // defaults to a tiny in-memory cache.
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 256 << 20)

        // Start Sparkle at launch. With SUEnableAutomaticChecks unset, the
        // first check prompts the user to enable automatic update checks.
        let controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        updaterController = controller
        _updaterModel = StateObject(wrappedValue: UpdaterViewModel(updater: controller.updater))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(ui)
                .environment(themes)
                .environment(\.theme, themes.theme)
                .frame(minWidth: 960, minHeight: 560)
        }
        .defaultSize(width: 1220, height: 760)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updaterController.checkForUpdates(nil)
                }
                .disabled(!updaterModel.canCheckForUpdates)
            }
            CommandGroup(after: .toolbar) {
                Picker("Theme", selection: Binding(
                    get: { themes.selected },
                    set: { newValue in
                        withAnimation(.easeInOut(duration: 0.35)) { themes.selected = newValue }
                    }
                )) {
                    ForEach(ThemeID.allCases) { id in
                        Text(id.displayName).tag(id)
                    }
                }
                Divider()
            }
            CommandMenu("Playback") {
                Button(app.player.isPlaying ? "Pause" : "Play") {
                    app.player.togglePlayPause()
                }
                .disabled(app.player.current == nil)

                Button("Next Track") { app.player.next() }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .control])
                    .disabled(!app.player.hasNext)

                Button("Previous Track") { app.player.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .control])
                    .disabled(!app.player.hasPrevious)

                Divider()

                Button("Clear Queue") { app.player.clear() }
                    .disabled(app.player.queue.isEmpty)
            }
            CommandGroup(after: .sidebar) {
                Button("Search") { ui.requestSearchFocus() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Button(ui.inspectorOpen ? "Hide Dashboard" : "Show Dashboard") {
                    ui.inspectorOpen.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
    }
}
```

- [ ] **Step 3: Regenerate (pick up the new file) and build**

```bash
xcodegen generate
rm -rf build/ddp-sparkle
xcodebuild -project AppleNugs.xcodeproj -scheme AppleNugs -configuration Debug \
  -derivedDataPath build/ddp-sparkle clean build 2>&1 | tee build/ddp-sparkle.log | tail -8
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Confirm warning-free for our sources**

```bash
grep "warning:" build/ddp-sparkle.log | grep -v "SourcePackages" || echo "no AppleNugs warnings"
```
Expected: "no AppleNugs warnings". If the Combine `assign(to:)` line is flagged under strict concurrency despite the `@MainActor` + `.receive(on:)`, the fix is bounded: keep `@MainActor`, and if needed store the subscription instead — `updater.publisher(for: \.canCheckForUpdates).receive(on: DispatchQueue.main).sink { [weak self] in self?.canCheckForUpdates = $0 }.store(in: &cancellables)` (add `private var cancellables = Set<AnyCancellable>()`). Re-run Step 3–4.

- [ ] **Step 5: Commit**

```bash
git add project.yml AppleNugs/Updates/CheckForUpdates.swift AppleNugs/App/AppleNugsApp.swift
git commit -m "feat: Sparkle updater + Check for Updates menu item"
```

---

### Task 5: Release tooling and documentation

Make signing + appcast generation a one-command step and document the full release flow, including the verified footguns.

**Files:**
- Create: `scripts/sparkle-appcast.sh`
- Modify: `DISTRIBUTION.md`, `README.md`
- Test: `shellcheck` + doc-content assertions

**Interfaces:**
- Consumes: the private key in the Keychain (Task 1); the Sparkle tools in `build/sparkle-tools/bin` (Task 1)
- Produces: a repeatable per-release appcast step.

- [ ] **Step 1: Write the appcast helper script**

`scripts/sparkle-appcast.sh` (single-item appcast: each release advertises only the newest DMG, which is all Sparkle needs to offer an update — this sidesteps per-tag URL-prefix mismatches):

```bash
#!/usr/bin/env bash
# Sign the release DMG with the Sparkle EdDSA key and (re)write appcast.xml.
#
# Run AFTER the DMG is built, notarized, and stapled, AND AFTER the GitHub
# Release asset is uploaded (so the feed never points at a 404).
#
# Usage: scripts/sparkle-appcast.sh <dir-with-only-the-new-dmg> <git-tag>
#   e.g. scripts/sparkle-appcast.sh build/sparkle-enclosure v1.1
set -euo pipefail

ENCLOSURE_DIR="${1:?usage: sparkle-appcast.sh <enclosure-dir> <git-tag>}"
TAG="${2:?usage: sparkle-appcast.sh <enclosure-dir> <git-tag>}"
TOOLS="${SPARKLE_TOOLS:-build/sparkle-tools/bin}"

[ -x "$TOOLS/generate_appcast" ] || { echo "generate_appcast not found at $TOOLS (see Task 1)"; exit 1; }

"$TOOLS/generate_appcast" \
  --download-url-prefix "https://github.com/tsvb/applenugs/releases/download/${TAG}/" \
  "$ENCLOSURE_DIR"

cp "$ENCLOSURE_DIR/appcast.xml" appcast.xml
echo "appcast.xml updated at repo root. Commit and push it to make the update live."
```

```bash
chmod +x scripts/sparkle-appcast.sh
```

- [ ] **Step 2: Lint the script**

```bash
shellcheck scripts/sparkle-appcast.sh && echo "shellcheck clean"
```
Expected: "shellcheck clean" (no warnings). If `shellcheck` is absent, `bash -n scripts/sparkle-appcast.sh` for a syntax check.

- [ ] **Step 3: Document the Sparkle release flow in `DISTRIBUTION.md`**

Append a "Sparkle auto-update releases" section to `DISTRIBUTION.md` that states, as explicit steps:
- Bump **`CURRENT_PROJECT_VERSION`** every release — Sparkle compares **build numbers**, and a static build number silently disables update detection (the #1 Sparkle footgun).
- Build → notarize → staple the **DMG** (formalize this as the release artifact; the DMG, not the `.zip`, is what Sparkle consumes).
- During archive/export, let `xcodebuild` sign the nested Sparkle framework + XPC services — **never** run `codesign --deep` by hand.
- Upload the DMG to the GitHub Release **first**, then run `scripts/sparkle-appcast.sh <dir> <tag>`, then commit + push `appcast.xml`.
- The feed (`raw.githubusercontent`) only resolves once the repo is **public**, and GitHub's CDN caches it ~5 min.
- The EdDSA private key lives in the Keychain and must be backed up (Task 1); `generate_appcast` must run on the machine that holds it.

- [ ] **Step 4: Mention auto-update in `README.md`**

Add a Features bullet, e.g.:
> - **Auto-update.** Built-in Sparkle updater — the app checks for new releases and installs them in place with one click; "Check for Updates…" lives under the app menu.

- [ ] **Step 5: Assert the docs were updated**

```bash
grep -q "CURRENT_PROJECT_VERSION" DISTRIBUTION.md && grep -qi "sparkle" DISTRIBUTION.md && echo "DISTRIBUTION ok"
grep -qi "auto-update\|Check for Updates" README.md && echo "README ok"
```
Expected: "DISTRIBUTION ok" and "README ok".

- [ ] **Step 6: Commit**

```bash
git add scripts/sparkle-appcast.sh DISTRIBUTION.md README.md
git commit -m "docs: Sparkle release flow + appcast helper script"
```

---

### Task 6: End-to-end update verification (interactive acceptance)

The real proof Sparkle works. **Executed interactively by Tim on his machine** (a GUI update cycle + signing identity) — not an automated subagent. Uses a local `file://` feed so it does not depend on the repo being public.

**Files:**
- Temporary, under git-ignored `build/` only
- Test: a live update is detected, verified, installed, and relaunched

**Interfaces:**
- Consumes: everything from Tasks 1–5
- Produces: confidence the feed/sign/install loop is correct before the real feed goes live.

- [ ] **Step 1: Build two versions**

Build and export a **Developer ID-signed, notarized, stapled** DMG at the current `CURRENT_PROJECT_VERSION` (call it build N) per `DISTRIBUTION.md`. Then bump `CURRENT_PROJECT_VERSION` to N+1, rebuild a second DMG. Put **only the build N+1 DMG** in `build/sparkle-enclosure/`.

- [ ] **Step 2: Generate a local appcast pointing at the N+1 DMG**

```bash
build/sparkle-tools/bin/generate_appcast build/sparkle-enclosure
# appcast.xml now sits in build/sparkle-enclosure/ with a file:// or relative enclosure URL
```
Confirm `build/sparkle-enclosure/appcast.xml` exists and contains a `sparkle:edSignature` and the N+1 version.

- [ ] **Step 3: Point a test build N at the local feed**

Temporarily set the feed in `project.yml` to the local appcast, then regenerate and build/sign **build N** as a Developer ID build (the install path + signature-continuity check only fully exercise on a signed build):

```yaml
        # TEMPORARY for the E2E test — revert in Step 5:
        SUFeedURL: file:///ABSOLUTE/PATH/TO/build/sparkle-enclosure/appcast.xml
```
```bash
xcodegen generate
# …archive/export build N as Developer ID per DISTRIBUTION.md…
```
Launch build N. (Sparkle 2.x reads `SUFeedURL` from Info.plist, not from `defaults`, so a temporary Info.plist value is the reliable override. A throwaway public gist raw URL works too if you prefer testing over the network.)

- [ ] **Step 4: Run the update**

In build N: app menu → **Check for Updates…**. Expected: Sparkle reports version N+1 available, downloads it, verifies the EdDSA signature **without error**, installs into `/Applications`, and relaunches as N+1.

- [ ] **Step 5: Confirm and clean up**

Verify the relaunched app reports N+1 (About box / `CFBundleVersion`). Revert the temporary feed in `project.yml` back to the real `raw.githubusercontent` URL, regenerate, and clean up:
```bash
# restore SUFeedURL in project.yml to https://raw.githubusercontent.com/tsvb/applenugs/main/appcast.xml
xcodegen generate
rm -rf build/sparkle-enclosure
git diff --stat project.yml   # expect: no changes (the temporary edit is fully reverted)
```
Expected: clean state; the real `SUFeedURL` (raw.githubusercontent) is what ships. No commit (all artifacts were under `build/`).

---

## Post-implementation (maintainer-gated)

- Reset `CURRENT_PROJECT_VERSION` to the intended ship value if the E2E test bumped it.
- The feed goes live when the repo is flipped public and the first real Release + `appcast.xml` are pushed (gated on Tim).
