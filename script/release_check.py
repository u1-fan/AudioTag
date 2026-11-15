#!/usr/bin/env python3
"""检查 AudioTag 的版本、Sparkle 和公证发布不变量。"""

import base64
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEMVER = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+(?:[.-][0-9A-Za-z.-]+)?$")
FEED_URL = "https://audiotag.u1.fan/updates/appcast.xml"


def validate(tag: str | None) -> list[str]:
    errors: list[str] = []
    config = json.loads((ROOT / "Config/Release.json").read_text(encoding="utf-8"))
    version = config.get("version", "")
    if not SEMVER.fullmatch(version):
        errors.append(f"版本号不是合法语义版本：{version!r}")
    if tag and tag != f"v{version}":
        errors.append(f"标签 {tag!r} 与版本 {version!r} 不一致")
    if config.get("feedURL") != FEED_URL:
        errors.append(f"更新源必须为 {FEED_URL}")
    try:
        if len(base64.b64decode(config.get("publicEDKey", ""), validate=True)) != 32:
            errors.append("Config/Release.json 的 Sparkle 公钥不是 32 字节 Ed25519 公钥")
    except Exception:
        errors.append("Config/Release.json 的 Sparkle 公钥不是有效 Base64")

    package = (ROOT / "Package.swift").read_text(encoding="utf-8")
    for required in ("sparkle-project/Sparkle", 'product(name: "Sparkle"'):
        if required not in package:
            errors.append(f"Package.swift 缺少 {required}")

    workflow = ROOT / ".github/workflows/release-dmg.yml"
    if not workflow.is_file():
        errors.append("缺少 Release DMG workflow")
    else:
        workflow_text = workflow.read_text(encoding="utf-8")
        for required in ("notarytool submit", "generate_appcast", "SPARKLE_EDDSA_PRIVATE_KEY", "hdiutil verify"):
            if required not in workflow_text:
                errors.append(f"Release workflow 缺少 {required}")

    for relative in (
        "Config/sparkle-public-key.txt",
        "script/configure_sparkle_keys.sh",
        "script/package_dmg.sh",
        "script/sign_macos_app.sh",
        "script/verify_appcast.py",
        "script/verify_published_appcast.py",
    ):
        if not (ROOT / relative).is_file():
            errors.append(f"缺少发布辅助文件：{relative}")

    public_key = ROOT / "Config/sparkle-public-key.txt"
    if public_key.is_file() and public_key.read_text(encoding="utf-8").strip() != config.get("publicEDKey"):
        errors.append("Config/sparkle-public-key.txt 与 Config/Release.json 的公钥不一致")
    return errors


def main() -> int:
    tag = sys.argv[1] if len(sys.argv) > 1 else None
    errors = validate(tag)
    if errors:
        for error in errors:
            print(f"release-check: {error}", file=sys.stderr)
        return 1
    print("release-check: metadata is consistent")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
