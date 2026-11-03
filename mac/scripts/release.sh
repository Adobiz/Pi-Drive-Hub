#!/usr/bin/env bash
# Build, sign, notarize, staple and verify locally. Does not upload to GitHub.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${1:-}" == "--check" ]]; then
  echo 'Required: DEVELOPER_ID_APPLICATION, NOTARYTOOL_PROFILE'
  echo 'No signing or notarization will run in --check mode.'
  security find-identity -v -p codesigning
  exit 0
fi
: "${DEVELOPER_ID_APPLICATION:?Set the Developer ID Application identity from Keychain}"
: "${NOTARYTOOL_PROFILE:?Set a notarytool Keychain profile name}"
[[ "$DEVELOPER_ID_APPLICATION" == "Developer ID Application:"* ]] || {
  echo 'A Developer ID Application identity is required; ad-hoc signing is not accepted.' >&2
  exit 1
}
# Confirm prerequisites before creating any distribution package.
if ! security find-identity -v -p codesigning | grep -F -- "$DEVELOPER_ID_APPLICATION" >/dev/null; then
  echo 'The requested Developer ID Application identity is not available in Keychain.' >&2
  exit 1
fi
xcrun notarytool history --keychain-profile "$NOTARYTOOL_PROFILE" --output-format json >/dev/null

FLUTTER="$(command -v flutter || true)"
if [[ -z "$FLUTTER" && -x "$HOME/development/flutter/bin/flutter" ]]; then
  FLUTTER="$HOME/development/flutter/bin/flutter"
fi
[[ -n "$FLUTTER" ]] || { echo 'Flutter SDK not found.' >&2; exit 1; }
"$FLUTTER" pub get
"$FLUTTER" analyze --no-pub
"$FLUTTER" test --no-pub
./build.sh "${1:-}"

OUTPUT="build/distribution"
STAGE="$(mktemp -d "$OUTPUT/.signed-XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/pi_pan.app"
ditto build/macos/Build/Products/Release/pi_pan.app "$APP"

./scripts/sign-app.sh "$APP" "$DEVELOPER_ID_APPLICATION"

notarize() {
  xcrun notarytool submit "$1" --keychain-profile "$NOTARYTOOL_PROFILE" \
    --wait --output-format json > "$2"
  python3 - "$2" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('Notarization failed. Submission ID: ' + str(result.get('id')))
PY
}
# Both ZIP and DMG are distribution assets. Staple the app before placing it
# in either one, so a copied-out app carries its ticket independently of DMG.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGE/app-notarize.zip"
notarize "$STAGE/app-notarize.zip" "$STAGE/app-notary.json"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict "$APP"
spctl --assess --type execute --verbose=4 "$APP"

./scripts/package-dmg.sh "$APP" "$STAGE/release.dmg"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")"
codesign --force --sign "$DEVELOPER_ID_APPLICATION" --timestamp \
  --identifier "$BUNDLE_ID.dmg" "$STAGE/release.dmg"
notarize "$STAGE/release.dmg" "$STAGE/dmg-notary.json"
xcrun stapler staple "$STAGE/release.dmg"
xcrun stapler validate "$STAGE/release.dmg"
codesign --verify --strict "$STAGE/release.dmg"
spctl --assess --type open --context context:primary-signature --verbose=4 "$STAGE/release.dmg"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/pi_pan")"
ARCH="$(echo "$ARCHS" | xargs | tr ' ' '-')"
if [[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]]; then ARCH=universal; fi
ZIP="$OUTPUT/Pi-Drive-Hub-macos-$ARCH-$VERSION.zip"
DMG="$OUTPUT/Pi-Drive-Hub-macos-$ARCH-$VERSION.dmg"
# Only replace the final asset after all distribution checks have passed.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGE/final.zip"
mv "$STAGE/final.zip" "$ZIP"
mv "$STAGE/release.dmg" "$DMG"
for ASSET in "$ZIP" "$DMG"; do
  (cd "$OUTPUT" && shasum -a 256 "$(basename "$ASSET")" > "$(basename "$ASSET").sha256")
done
cp "$STAGE/app-notary.json" "$ZIP.notary.json"
cp "$STAGE/dmg-notary.json" "$DMG.notary.json"
echo "Verified Release asset: $ZIP"
echo "Verified Release asset: $DMG"
echo 'Test a browser-downloaded copy on a clean Mac before publishing a stable Release.'
