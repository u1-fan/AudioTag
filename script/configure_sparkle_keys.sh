#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUBLIC_KEY_FILE="$ROOT/Config/sparkle-public-key.txt"
RELEASE_CONFIG="$ROOT/Config/Release.json"
MODE="${1:-setup}"
SPARKLE_KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-audiotag}"
KEY_ARGS=(--account "$SPARKLE_KEY_ACCOUNT")

GENERATE_KEYS="$(find "$ROOT/.build/artifacts" -type f -path '*/Sparkle/bin/generate_keys' -print -quit 2>/dev/null || true)"
if [[ -z "$GENERATE_KEYS" ]]; then
  swift build -c release --product AudioTag
  GENERATE_KEYS="$(find "$ROOT/.build/artifacts" -type f -path '*/Sparkle/bin/generate_keys' -print -quit 2>/dev/null || true)"
fi
[[ -x "$GENERATE_KEYS" ]] || { echo "找不到 Sparkle generate_keys" >&2; exit 1; }

case "$MODE" in
  setup)
    public_key="$("$GENERATE_KEYS" "${KEY_ARGS[@]}" -p 2>/dev/null || true)"
    if [[ -z "$public_key" ]]; then
      output="$("$GENERATE_KEYS" "${KEY_ARGS[@]}")"
      public_key="$(printf '%s\n' "$output" | sed -n 's/.*<string>\([^<]*\)<\/string>.*/\1/p' | head -n 1)"
    fi
    [[ "$public_key" =~ ^[A-Za-z0-9+/]+=*$ ]] || { echo "Sparkle 未返回有效公钥" >&2; exit 1; }
    mkdir -p "$(dirname "$PUBLIC_KEY_FILE")"
    printf '%s\n' "$public_key" > "$PUBLIC_KEY_FILE"
    python3 - "$RELEASE_CONFIG" "$public_key" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
data["publicEDKey"] = sys.argv[2]
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
PY
    echo "Sparkle 公钥已写入 Config/sparkle-public-key.txt 与 Config/Release.json"
    echo "私钥仍保存在 macOS 钥匙串；CI 请配置 SPARKLE_EDDSA_PRIVATE_KEY。"
    ;;
  check)
    keychain_key="$("$GENERATE_KEYS" "${KEY_ARGS[@]}" -p 2>/dev/null)"
    file_key="$(tr -d '[:space:]' < "$PUBLIC_KEY_FILE" 2>/dev/null || true)"
    [[ -n "$keychain_key" && "$keychain_key" == "$file_key" ]] || {
      echo "文件公钥与 macOS 钥匙串不一致" >&2
      exit 1
    }
    echo "Sparkle 公钥与 macOS 钥匙串一致"
    ;;
  export-private)
    PRIVATE_PATH="${2:?用法：configure_sparkle_keys.sh export-private <输出路径>}"
    umask 077
    mkdir -p "$(dirname "$PRIVATE_PATH")"
    "$GENERATE_KEYS" "${KEY_ARGS[@]}" -x "$PRIVATE_PATH"
    chmod 600 "$PRIVATE_PATH"
    echo "私钥已导出到 $PRIVATE_PATH；上传到 GitHub Secret SPARKLE_EDDSA_PRIVATE_KEY 后立即删除。"
    ;;
  *)
    echo "用法：$0 [setup|check|export-private <输出路径>]" >&2
    exit 2
    ;;
esac
