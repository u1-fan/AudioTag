#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG_VERSION="$(python3 -c 'import json; print(json.load(open("Config/Release.json"))["version"])')"
CONFIG_BUILD="$(python3 -c 'import json; print(json.load(open("Config/Release.json"))["build"])')"
VERSION_INPUT="${1:-$CONFIG_VERSION}"
VERSION="${VERSION_INPUT#v}"
IDENTITY="${SIGNING_IDENTITY:--}"
DIST_DIR="${DIST_DIR:-$ROOT/dist/release}"
ARCH="$(uname -m)"

if [[ "$VERSION" != "$CONFIG_VERSION" ]]; then
  echo "发行版本 $VERSION 与 Config/Release.json 的 $CONFIG_VERSION 不一致" >&2
  exit 1
fi
if [[ "$ARCH" != "arm64" ]]; then
  echo "AudioTag 当前发行包仅支持 Apple Silicon，当前架构：$ARCH" >&2
  exit 2
fi
for tool in swift python3 ditto hdiutil shasum codesign; do
  command -v "$tool" >/dev/null || { echo "缺少发行工具：$tool" >&2; exit 1; }
done
[[ -x "$ROOT/.venv/bin/pyinstaller" ]] || {
  echo "缺少 .venv/bin/pyinstaller，请先安装发行依赖" >&2
  exit 1
}

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/audiotag-package.XXXXXX")"
DMG_ROOT="$WORK_DIR/dmg-root"
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$DIST_DIR" "$ROOT/.build/release-tools"
for archive in ffmpeg-9.0.2.tar.xz lame-4.0.tar.gz; do
  if [[ ! -f "$ROOT/.build/release-tools/$archive" ]]; then
    cp "$ROOT/site/sources/$archive" "$ROOT/.build/release-tools/$archive"
  fi
done

swift build -c release --product AudioTag
SWIFT_BIN="$(swift build -c release --show-bin-path)/AudioTag"

ENGINE_DIR="$WORK_DIR/engine"
mkdir -p "$ENGINE_DIR"
"$ROOT/.venv/bin/pyinstaller" --noconfirm --clean --onefile \
  --codesign-identity "$IDENTITY" --name audiotag \
  --distpath "$ENGINE_DIR" --workpath "$WORK_DIR/python" --specpath "$WORK_DIR" \
  --paths "$ROOT" "$ROOT/script/engine_entry.py"

bash "$ROOT/script/build_release_tools.sh"
APP_BUNDLE="$WORK_DIR/AudioTag.app"
ENGINE_BINARY="$ENGINE_DIR/audiotag" \
TOOLS_BUNDLE="$ROOT/.build/release-tools/bundle-encoder-only" \
  python3 "$ROOT/script/stage_app.py" "$SWIFT_BIN" "$APP_BUNDLE" "$IDENTITY"
python3 "$ROOT/script/verify_engine_bundle.py" "$APP_BUNDLE"

DMG_NAME="AudioTag-v${VERSION}-macOS-${ARCH}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
CHECKSUM_PATH="$DMG_PATH.sha256"
rm -f "$DMG_PATH" "$CHECKSUM_PATH"
mkdir -p "$DMG_ROOT"
ditto "$APP_BUNDLE" "$DMG_ROOT/AudioTag.app"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create -volname "AudioTag $VERSION" -srcfolder "$DMG_ROOT" -ov -format ULMO "$DMG_PATH"

if [[ "$IDENTITY" != "-" ]]; then
  codesign --force --sign "$IDENTITY" --timestamp "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
fi
hdiutil verify "$DMG_PATH"
(cd "$DIST_DIR" && shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256")
echo "已生成：$DMG_PATH"
echo "构建号：$CONFIG_BUILD"
