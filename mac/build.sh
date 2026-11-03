#!/usr/bin/env bash
# 一键构建 macOS release 包
# 用法: ./build.sh [en]    （参数 en 构建英文界面，默认中文）
set -euo pipefail
cd "$(dirname "$0")"

LANG_ARG=""
if [ "${1:-}" = "en" ]; then
  LANG_ARG="--dart-define=APP_LANG=en"
fi

# 中国网络环境默认走 Flutter 官方镜像（已配置代理/海外网络可注释）
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"

# 定位 flutter：优先 PATH，其次常见安装位置（~/development/flutter、~/flutter）
FLUTTER="$(command -v flutter 2>/dev/null || true)"
if [ -z "$FLUTTER" ]; then
  for dir in "$HOME/development/flutter/bin" "$HOME/flutter/bin"; do
    if [ -x "$dir/flutter" ]; then
      FLUTTER="$dir/flutter"
      break
    fi
  done
fi
if [ -z "$FLUTTER" ]; then
  echo "错误: 未找到 flutter，请先安装 Flutter SDK（见 GUIDE.md）"
  exit 1
fi
echo "==> Flutter: $FLUTTER"

"$FLUTTER" pub get
"$FLUTTER" build macos --release $LANG_ARG

APP="build/macos/Build/Products/Release/pi_pan.app"
if [ ! -d "$APP" ]; then
  echo "错误: 未找到构建产物 $APP"
  exit 1
fi

# Fix native-asset signature structure for local Apple Silicon launches.
# Ad-hoc signing conveys no Developer ID distribution identity.
./scripts/sign-app.sh "$APP" -

# Local builds remain clearly marked UNSIGNED. Use scripts/release.sh to sign
# and notarize a distribution asset before publishing it on GitHub.
OUTPUT="build/distribution"
mkdir -p "$OUTPUT"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/pi_pan")"
ARCH="$(echo "$ARCHS" | xargs | tr ' ' '-')"
if [[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]]; then ARCH=universal; fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ZIP="$OUTPUT/UNSIGNED-Pi-Drive-Hub-macos-$ARCH-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
DMG="$OUTPUT/UNSIGNED-Pi-Drive-Hub-macos-$ARCH-$VERSION.dmg"
./scripts/package-dmg.sh "$APP" "$DMG"
for ASSET in "$ZIP" "$DMG"; do
  (cd "$OUTPUT" && shasum -a 256 "$(basename "$ASSET")" > "$(basename "$ASSET").sha256")
done
echo "构建完成: $APP"
echo "本地测试包（未做 Developer ID 签名/公证）: $ZIP"
echo "本地测试 DMG（未做 Developer ID 签名/公证）: $DMG"
echo '正式 GitHub Release 请使用 scripts/release.sh'
