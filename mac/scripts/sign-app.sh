#!/usr/bin/env bash
# Seal nested native code before the app. '-' is for local testing only.
set -euo pipefail
APP="${1:?Usage: sign-app.sh APP IDENTITY}"
IDENTITY="${2:?Usage: sign-app.sh APP IDENTITY}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FLAGS=(--force --sign "$IDENTITY")
if [[ "$IDENTITY" != '-' ]]; then FLAGS+=(--options runtime --timestamp); fi
while IFS= read -r -d '' binary; do
  if file -b "$binary" | grep -q 'Mach-O'; then
    codesign "${FLAGS[@]}" "$binary"
  fi
done < <(find "$APP/Contents/Frameworks" -type f -print0)
while IFS= read -r -d '' framework; do
  codesign "${FLAGS[@]}" "$framework"
done < <(find "$APP/Contents/Frameworks" -depth -type d -name '*.framework' -print0)
codesign "${FLAGS[@]}" --entitlements "$ROOT/macos/Runner/Release.entitlements" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
