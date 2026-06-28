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
