# Distribution

This document covers signing and shipping AppleNugs two ways: the **Mac App
Store** and **Developer ID** (a notarized build for direct download, e.g. a
GitHub release). The repo's committed project is ad-hoc signed so it builds
anywhere; the steps below are what *you* do with your own Apple Developer
account when you're ready to ship.

## ⚠️ Read first: App Store review risk

AppleNugs is an unofficial client for a third-party subscription service whose
**unofficial/reverse-engineered API** it talks to directly. That collides with
several App Store Review Guidelines, most pointedly:

- **5.2.2 (Intellectual Property — third-party services):** an app that
  "accesses, monetizes access to, or displays content from a third-party
  service" must be "specifically permitted to do so under the service's terms."
  AppleNugs is not. nugs.net has not authorized this client.
- **2.3 / 4.0:** using a private/undocumented API of someone else's service and
  the "nugs" name/marks invites rejection on metadata and design grounds too.

Realistically, **this app is unlikely to pass App Store review** as-is. Paths
that change that calculus:

1. **Get permission.** Written authorization from nugs.net to build on their
   API is the clean fix and resolves 5.2.2 directly.
2. **Ship Developer ID instead.** Notarized direct download (below) is the
   pragmatic route for an unofficial client — no content review, just a
   malware/notarization check, which this app passes. This is what most
   tools in this category do.
3. **Submit and see.** You can submit anyway; worst case is a rejection, not a
   penalty. If you do, expect a 5.2.2 citation and have a response ready.

Everything else in this repo (icon, privacy manifest, sandbox, hardened
runtime, export compliance, versioning) is genuinely required and is done.
Nothing here is a reason not to *try* — just go in informed.

### iOS target: personal install only

`AppleNugs-iOS` is deliberately outside both distribution paths above. iOS has
no Developer ID equivalent — every distribution channel (App Store, TestFlight)
passes Apple review, where the 5.2.2 exposure applies in full. The supported
route is building from source with your own team selected and installing on
your own devices (a paid developer account keeps a personal install signed for
one year; free accounts expire after 7 days). Sparkle does not apply to iOS —
update by rebuilding.

## Prerequisites (both paths)

- **Apple Developer Program** membership ($99/yr).
- **Xcode 16+** signed into your Apple ID (Settings → Accounts).
- Bundle ID `com.timvbs.applenugs` registered to your team. (Automatic signing
  registers it for you the first time you archive; or pre-register it at
  developer.apple.com → Identifiers.)
- `xcodegen generate` has been run so `AppleNugs.xcodeproj` exists.

The project is already configured with everything review checks for:

| Requirement                       | Status                                            |
| --------------------------------- | ------------------------------------------------- |
| App icon (all sizes)              | ✅ `Assets.xcassets/AppIcon.appiconset`           |
| App Sandbox                       | ✅ `com.apple.security.app-sandbox`               |
| Hardened Runtime                  | ✅ `ENABLE_HARDENED_RUNTIME = YES`                |
| Privacy manifest                  | ✅ `PrivacyInfo.xcprivacy` (UserDefaults, no data)|
| Export compliance                 | ✅ `ITSAppUsesNonExemptEncryption = false`        |
| Category                          | ✅ Music                                          |
| Minimal entitlements              | ✅ outbound network only                          |

## Path A — Mac App Store

1. **Set your team.** Open `AppleNugs.xcodeproj`, select the AppleNugs target →
   Signing & Capabilities → check **Automatically manage signing** and pick your
   **Team**. (Or set `DEVELOPMENT_TEAM` + `CODE_SIGN_STYLE: Automatic` in
   `project.yml` and re-run `xcodegen generate`.)
2. **Create the App Store Connect record** at appstoreconnect.apple.com → Apps →
   ＋ → New App. Platform macOS, bundle ID `com.timvbs.applenugs`. Set the
   **Privacy → "Data Not Collected"** declaration (matches the privacy manifest).
3. **Archive:** Product → Destination → "Any Mac", then Product → **Archive**
   (this forces a Release build).
4. **Upload:** in the Organizer, **Distribute App → App Store Connect → Upload**.
   Xcode signs with "Apple Distribution" and a managed App Store profile.
5. Fill in screenshots, description, and submit for review in App Store Connect.

Bump `CURRENT_PROJECT_VERSION` in `project.yml` for every new build you upload.

## Path B — Developer ID (notarized direct download)

This produces a `.app` that runs on any Mac with no Gatekeeper warning, ideal
for a GitHub release. Requires an app-specific password for `notarytool`
(appleid.apple.com → Sign-In & Security → App-Specific Passwords).

```sh
# 1. Archive a Release build signed with your Developer ID.
xcodebuild -project AppleNugs.xcodeproj -scheme AppleNugs \
  -configuration Release -derivedDataPath build \
  -archivePath build/AppleNugs.xcarchive archive \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)" \
  DEVELOPMENT_TEAM=TEAMID

# 2. Export the .app from the archive (needs an export options plist —
#    method "developer-id"; see Apple's docs or generate via Organizer once).
xcodebuild -exportArchive \
  -archivePath build/AppleNugs.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist ExportOptions-DeveloperID.plist

# 3. Notarize, then staple the ticket into the app.
ditto -c -k --keepParent build/export/AppleNugs.app build/AppleNugs.zip
xcrun notarytool submit build/AppleNugs.zip \
  --apple-id "you@example.com" --team-id TEAMID \
  --password "abcd-efgh-ijkl-mnop" --wait
xcrun stapler staple build/export/AppleNugs.app

# 4. Package for release (zip the stapled app, or build a DMG).
ditto -c -k --keepParent build/export/AppleNugs.app build/AppleNugs.zip
```

Verify before shipping:

```sh
spctl -a -vvv -t install build/export/AppleNugs.app   # → "accepted, source=Notarized Developer ID"
codesign -dvvv build/export/AppleNugs.app 2>&1 | grep -i runtime  # → flags include runtime
```

## GitHub releases

The shipping app lives on `main`, and the repo is public. To cut a release,
build the notarized DMG (Path B) and publish it via the Sparkle release flow
below.

Standing notes:

- This is an unofficial nugs.net client — see the disclaimer in
  [README](README.md) and [LICENSE](LICENSE).
- There are no secrets in the tree: credentials are entered at runtime and the
  OAuth `client_id` is the public mobile-client value, not a secret.

## Sparkle auto-update releases

AppleNugs uses [Sparkle](https://sparkle-project.org) for in-app updates. The
`scripts/sparkle-appcast.sh` helper signs the release artifact and writes
`appcast.xml`. Every release must follow these steps in order:

1. **Bump `CURRENT_PROJECT_VERSION`** in `project.yml` before every build.
   Sparkle compares build numbers to decide whether an update is available — a
   static build number silently disables update detection (the #1 Sparkle
   footgun). `MARKETING_VERSION` (the human-readable version) is separate and
   does not affect Sparkle's comparison.

2. **Build → notarize → staple the DMG.** The DMG is the release artifact that
   Sparkle downloads and mounts. Follow Path B above to produce the notarized
   `.app`, then package it as a DMG rather than a zip:

   ```sh
   hdiutil create -volname AppleNugs -srcfolder build/export/AppleNugs.app \
     -ov -format UDZO build/AppleNugs-vX.Y.dmg
   xcrun notarytool submit build/AppleNugs-vX.Y.dmg \
     --apple-id "you@example.com" --team-id TEAMID \
     --password "abcd-efgh-ijkl-mnop" --wait
   xcrun stapler staple build/AppleNugs-vX.Y.dmg
   ```

3. **Let `xcodebuild` sign the nested Sparkle framework and XPC services.**
   During archive and export, Xcode re-signs every nested bundle automatically.
   Never run `codesign --deep` by hand — it signs child bundles with the wrong
   identity and breaks Gatekeeper validation on the Sparkle XPC helpers.

4. **Upload the DMG to the GitHub Release first**, then generate and commit the
   feed:

   ```sh
   # Upload the stapled DMG as the GitHub Release asset, then:
   mkdir -p build/sparkle-enclosure
   cp build/AppleNugs-vX.Y.dmg build/sparkle-enclosure/
   scripts/sparkle-appcast.sh build/sparkle-enclosure vX.Y
   git add appcast.xml && git commit -m "release: vX.Y appcast"
   git push
   ```

   The feed must never point at a 404 — uploading the asset before pushing
   `appcast.xml` guarantees that.

5. **Wait for the feed to resolve.** `appcast.xml` is served from
   `raw.githubusercontent.com`, which only resolves once the repo is **public**.
   GitHub's CDN caches raw content for approximately 5 minutes after a push, so
   "Check for Updates…" may return no update during that window — this is
   normal.

6. **Guard the EdDSA private key.** The signing key was generated once with
   Sparkle's `generate_keys` (the public half is `SUPublicEDKey` in
   `project.yml`); the private half lives in the build machine's login Keychain.
   Export a backup with `generate_keys -x sparkle-private-key.txt` and store it
   somewhere safe — losing it means you can never sign another update.
   `generate_appcast` must run on the machine that holds the private key; a
   signature generated on a different machine (or with a different key) will
   cause Sparkle to reject the update.
