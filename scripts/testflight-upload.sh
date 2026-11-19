#!/bin/zsh
# Archive the iOS app and upload it to App Store Connect for INTERNAL TestFlight.
#
#   YETI_TEAM_ID=<TEAMID> scripts/testflight-upload.sh
#
# Needs: Xcode signed into the team's Apple ID (Settings → Accounts); the App Store
# Connect record for com.timvbs.yeti.ios; a CURRENT_PROJECT_VERSION in project.yml
# that App Store Connect hasn't seen yet. Signing is automatic (cloud-managed Apple
# Distribution certificate); the export options mark the build internal-only.
# See DISTRIBUTION.md → Internal TestFlight.
set -euo pipefail

cd "$(dirname "$0")/.."
: "${YETI_TEAM_ID:?set YETI_TEAM_ID to your Apple Developer Team ID}"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "✗ Working tree is dirty. Commit first so the build matches a commit." >&2
  exit 1
fi

version=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
build=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: "\(.*\)"/\1/p' project.yml)
echo "→ Yeti $version ($build) for internal TestFlight, from $(git rev-parse --short HEAD)"

out=build/testflight
rm -rf "$out"
mkdir -p "$out"
sed "s/TEAMID/$YETI_TEAM_ID/" ExportOptions-TestFlight.plist > "$out/ExportOptions.plist"

xcodegen generate --quiet

xcodebuild -project Yeti.xcodeproj -scheme Yeti-iOS -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$out/DerivedData" \
  -archivePath "$out/Yeti.xcarchive" \
  DEVELOPMENT_TEAM="$YETI_TEAM_ID" \
  -allowProvisioningUpdates \
  archive | tail -n 3

xcodebuild -exportArchive \
  -archivePath "$out/Yeti.xcarchive" \
  -exportOptionsPlist "$out/ExportOptions.plist" \
  -exportPath "$out/export" \
  -allowProvisioningUpdates | tail -n 5

rm -rf "$out/DerivedData"   # disk is tight; the archive keeps the dSYMs
echo "✓ Uploaded $version ($build). App Store Connect processes it (usually 5–30 min),"
echo "  then it appears under TestFlight → Internal Testing. Bump CURRENT_PROJECT_VERSION"
echo "  before the next upload."
