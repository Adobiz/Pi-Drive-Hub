#!/usr/bin/env bash
# Offline AppKit + Flutter integration check. Uses only a disposable app copy.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_APP="${1:-$ROOT/build/macos/Build/Products/Release/pi_pan.app}"
if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Build the macOS app first, or pass its .app path." >&2
  exit 1
fi
FLUTTER="$(command -v flutter 2>/dev/null || true)"
if [[ -z "$FLUTTER" ]]; then
  for candidate in "$HOME/development/flutter/bin/flutter" "$HOME/flutter/bin/flutter"; do
    if [[ -x "$candidate" ]]; then FLUTTER="$candidate"; break; fi
  done
fi
if [[ -z "$FLUTTER" ]]; then echo "Flutter SDK not found." >&2; exit 1; fi
SDK="$(python3 -c 'import os,sys; print(os.path.dirname(os.path.dirname(os.path.realpath(sys.argv[1]))))' "$FLUTTER")"
ENGINE="$SDK/bin/cache/artifacts/engine/darwin-x64-release/FlutterMacOS.xcframework/macos-arm64_x86_64"
WORK="$(mktemp -d /tmp/pi-workspace-smoke.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/WorkspaceSmoke.app"
ditto "$SOURCE_APP" "$APP"
EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$APP/Contents/Info.plist")"
rm "$APP/Contents/MacOS/$EXECUTABLE"
/usr/libexec/PlistBuddy -c 'Set CFBundleIdentifier com.adobiz.piPan.workspace-smoke' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set CFBundleExecutable WorkspaceSmoke' "$APP/Contents/Info.plist"
xcrun swiftc -D DEBUG \
  "$ROOT/macos/Runner/MenuBarModel.swift" \
  "$ROOT/macos/Runner/TransferPopoverView.swift" \
  "$ROOT/macos/Runner/MenuBarController.swift" \
  "$ROOT/macos/Runner/DesktopWindows.swift" \
  "$ROOT/tools/workspace_smoke.swift" \
  -F "$ENGINE" -framework FlutterMacOS \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -module-cache-path "$WORK/module-cache" \
  -o "$APP/Contents/MacOS/WorkspaceSmoke"
"$ROOT/scripts/sign-app.sh" "$APP" -
python3 - "$APP/Contents/MacOS/WorkspaceSmoke" <<'PY'
import os, subprocess, sys
subprocess.run([sys.argv[1]], env={**os.environ, 'PI_WORKSPACE_SMOKE': '1'},
               check=True, timeout=20)
PY
