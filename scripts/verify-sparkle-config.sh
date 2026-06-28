#!/usr/bin/env bash
# Guard the Sparkle auto-update configuration against accidental regressions on
# future project.yml edits. Run AFTER `xcodegen generate` (it reads the
# generated Info.plist + entitlements). Used by CI; runnable locally too:
#
#   xcodegen generate && ./scripts/verify-sparkle-config.sh
#
set -euo pipefail

INFO="AppleNugs/Info.plist"
ENT="AppleNugs/AppleNugs.entitlements"
EXPECTED_KEY="WKOnGAu8QlsO9cDxBQ8peCSLDuVRTmx+p5MsruHqUFE="
EXPECTED_FEED="https://raw.githubusercontent.com/tsvb/applenugs/main/appcast.xml"

fail() { echo "❌ sparkle-config: $1" >&2; exit 1; }
pass() { echo "✅ $1"; }

[ -f "$INFO" ] || fail "missing $INFO — run 'xcodegen generate' first"
[ -f "$ENT" ]  || fail "missing $ENT — run 'xcodegen generate' first"

# --- Info.plist: required keys + exact values -------------------------------
# (these keys contain no dots, so plutil -extract keypaths work directly)
key=$(plutil -extract SUPublicEDKey raw "$INFO" 2>/dev/null) || fail "SUPublicEDKey missing from $INFO"
[ "$key" = "$EXPECTED_KEY" ] || fail "SUPublicEDKey changed: got '$key', expected '$EXPECTED_KEY' (a wrong key silently breaks signature verification)"
pass "SUPublicEDKey matches"

feed=$(plutil -extract SUFeedURL raw "$INFO" 2>/dev/null) || fail "SUFeedURL missing from $INFO"
[ "$feed" = "$EXPECTED_FEED" ] || fail "SUFeedURL changed: got '$feed'"
pass "SUFeedURL matches"

svc=$(plutil -extract SUEnableInstallerLauncherService raw "$INFO" 2>/dev/null) || fail "SUEnableInstallerLauncherService missing (mandatory for sandboxed Sparkle)"
[ "$svc" = "true" ] || fail "SUEnableInstallerLauncherService must be true, got '$svc'"
pass "SUEnableInstallerLauncherService=true"

# --- Info.plist: intentional omissions must stay absent --------------------
if plutil -extract SUEnableDownloaderService raw "$INFO" >/dev/null 2>&1; then
  fail "SUEnableDownloaderService must be ABSENT — network.client is present, so the Downloader XPC is intentionally skipped"
fi
pass "SUEnableDownloaderService absent (intentional)"

if plutil -extract SUEnableAutomaticChecks raw "$INFO" >/dev/null 2>&1; then
  fail "SUEnableAutomaticChecks must be ABSENT — leaving it unset is what gives Sparkle's first-launch prompt"
fi
pass "SUEnableAutomaticChecks absent (intentional)"

# --- Entitlements ----------------------------------------------------------
# The mach-lookup key contains dots, so plutil -extract keypaths don't apply;
# match against the human-readable dump instead. The XPC names must remain
# LITERAL $(PRODUCT_BUNDLE_IDENTIFIER)-… (Xcode expands them at signing time).
ent_dump=$(plutil -p "$ENT")
grep -q 'PRODUCT_BUNDLE_IDENTIFIER)-spks' <<<"$ent_dump" || fail "mach-lookup entitlement missing \$(PRODUCT_BUNDLE_IDENTIFIER)-spks"
grep -q 'PRODUCT_BUNDLE_IDENTIFIER)-spki' <<<"$ent_dump" || fail "mach-lookup entitlement missing \$(PRODUCT_BUNDLE_IDENTIFIER)-spki"
pass "mach-lookup installer entitlements present (-spks, -spki)"

grep -q 'com.apple.security.app-sandbox' <<<"$ent_dump"     || fail "app-sandbox entitlement missing"
grep -q 'com.apple.security.network.client' <<<"$ent_dump"  || fail "network.client entitlement missing"
pass "sandbox + network.client intact"

echo "✅ sparkle-config: all assertions passed"
