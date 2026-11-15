#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE="${1:?用法：sign_macos_app.sh <AudioTag.app> [签名身份]}"
IDENTITY="${2:-${SIGNING_IDENTITY:--}}"

is_developer_id() {
  [[ "$IDENTITY" == "Developer ID Application:"* ]] && return 0
  security find-identity -v -p codesigning 2>/dev/null \
    | grep -Eq "^ *[0-9]+\) *${IDENTITY} *\"Developer ID Application:"
}

SIGN_ARGS=(--force --sign "$IDENTITY")
if [[ "$IDENTITY" != "-" ]] && is_developer_id; then
  SIGN_ARGS+=(--options runtime --timestamp)
fi

sign_path() {
  local path="$1"
  [[ -e "$path" ]] || return 0
  codesign "${SIGN_ARGS[@]}" --preserve-metadata=entitlements "$path"
}

is_macho() {
  file -b "$1" 2>/dev/null | grep -q 'Mach-O'
}

SPARKLE_FRAMEWORK="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERSION="$SPARKLE_FRAMEWORK/Versions/B"

# 先签名资源中的可执行文件和动态库。Sparkle 自带的 XPC 与 Updater
# 在下面按框架要求的内到外顺序单独处理。
while IFS= read -r -d '' file_path; do
  if [[ "$file_path" != "$SPARKLE_FRAMEWORK"/* ]] && is_macho "$file_path"; then
    sign_path "$file_path"
  fi
done < <(find "$APP_BUNDLE/Contents" -type f -print0)

if [[ -d "$SPARKLE_VERSION" ]]; then
  sign_path "$SPARKLE_VERSION/XPCServices/Installer.xpc"
  sign_path "$SPARKLE_VERSION/XPCServices/Downloader.xpc"
  sign_path "$SPARKLE_VERSION/Autoupdate"
  sign_path "$SPARKLE_VERSION/Updater.app"
  sign_path "$SPARKLE_VERSION"
fi

# 处理其他嵌套 bundle，跳过 Sparkle 顶层符号链接，避免新版 codesign 报
# ambiguous format；具体版本目录已经在上一步签名。
while IFS= read -r -d '' bundle; do
  case "$bundle" in
    "$SPARKLE_FRAMEWORK"|"$SPARKLE_FRAMEWORK"/*) continue ;;
  esac
  sign_path "$bundle"
done < <(find "$APP_BUNDLE/Contents" -type d \( -name '*.app' -o -name '*.xpc' -o -name '*.framework' \) -print0)

codesign "${SIGN_ARGS[@]}" "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
