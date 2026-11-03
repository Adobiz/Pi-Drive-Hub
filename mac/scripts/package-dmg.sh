#!/usr/bin/env bash
# Package an already-built app. Signing/notarization belong to release.sh.
set -euo pipefail
SOURCE_APP="${1:?Usage: package-dmg.sh APP OUTPUT.dmg}"
OUTPUT="${2:?Usage: package-dmg.sh APP OUTPUT.dmg}"
[[ -d "$SOURCE_APP/Contents" && "$OUTPUT" == *.dmg ]] || {
  echo 'Provide an existing .app and a .dmg output path.' >&2; exit 1;
}
codesign --verify --deep --strict "$SOURCE_APP"
mkdir -p "$(dirname "$OUTPUT")"
OUTPUT_DIR="$(cd "$(dirname "$OUTPUT")" && pwd)"
OUTPUT="$OUTPUT_DIR/$(basename "$OUTPUT")"
STAGE="$(mktemp -d "$OUTPUT_DIR/.dmg-XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
mkdir "$STAGE/contents"
ditto "$SOURCE_APP" "$STAGE/contents/PI 网盘.app"
ln -s /Applications "$STAGE/contents/Applications"
cat > "$STAGE/contents/安装说明.txt" <<'INSTALL'
PI 网盘 / Pi Drive Hub

1. 先完成旧版本中的传输并退出旧版。
2. 将「PI 网盘.app」拖到 Applications（应用程序）。
3. 从「应用程序」打开 PI 网盘，再推出此磁盘映像。

关闭窗口不等于退出应用。使用 ⌘Q 或菜单中的「退出 PI 网盘」。
进程退出后，内存中的传输任务不会迁移到新版本。

Quit the previous version, drag the app to Applications, then launch it
from Applications and eject this image.
INSTALL
hdiutil create -quiet -fs HFS+ -format UDZO -volname 'PI 网盘' \
  -srcfolder "$STAGE/contents" "$STAGE/package.dmg"
hdiutil verify -quiet "$STAGE/package.dmg"
mv "$STAGE/package.dmg" "$OUTPUT"
echo "DMG created: $OUTPUT"
