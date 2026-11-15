#!/usr/bin/env python3
"""校验 GitHub Release 请求并输出 Actions 所需的版本值。"""

import argparse
import json
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEMVER = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+(?:[.-][0-9A-Za-z.-]+)?$")


def command(*args: str) -> str:
    result = subprocess.run(args, cwd=ROOT, text=True, capture_output=True, check=False)
    return result.stdout.strip() if result.returncode == 0 else ""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("version")
    parser.add_argument("--prerelease", choices=("true", "false"), default="false")
    args = parser.parse_args()
    version = args.version.removeprefix("v")
    if not SEMVER.fullmatch(version):
        print(f"invalid version: {args.version}")
        return 2
    if args.prerelease == "false" and not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        print("stable releases require a plain major.minor.patch version")
        return 2

    tag = f"v{version}"
    if command("git", "rev-parse", "--verify", f"refs/tags/{tag}"):
        print(f"tag already exists: {tag}")
        return 1
    if os.environ.get("GH_TOKEN") and os.environ.get("GITHUB_REPOSITORY"):
        release = subprocess.run(
            ["gh", "release", "view", tag, "--repo", os.environ["GITHUB_REPOSITORY"]],
            cwd=ROOT,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if release.returncode == 0:
            print(f"release already exists: {tag}")
            return 1

    config = json.loads((ROOT / "Config/Release.json").read_text(encoding="utf-8"))
    if config.get("version") != version:
        print(f"Config/Release.json version {config.get('version')!r} does not match {version!r}")
        return 1
    build = str(config.get("build", ""))
    if not build:
        print("Config/Release.json build is empty")
        return 1
    source_sha = command("git", "rev-parse", "HEAD")
    print(json.dumps({"version": version, "build": build, "tag": tag, "source_sha": source_sha}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
