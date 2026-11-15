#!/usr/bin/env python3
"""轮询公开 Sparkle appcast，直到当前版本可见。"""

import argparse
import sys
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET

from verify_appcast import verify_document


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("url")
    parser.add_argument("version")
    parser.add_argument("artifact")
    parser.add_argument("--attempts", type=int, default=12)
    parser.add_argument("--delay", type=int, default=10)
    args = parser.parse_args()
    if args.attempts < 1 or args.delay < 0:
        parser.error("--attempts 必须为正数，--delay 不能为负数")

    for attempt in range(1, args.attempts + 1):
        try:
            with urllib.request.urlopen(args.url, timeout=30) as response:
                if response.status != 200:
                    raise urllib.error.HTTPError(args.url, response.status, "unexpected HTTP status", response.headers, None)
                verify_document(response.read(), args.version, args.artifact)
            print(f"published appcast verified: {args.url}")
            return 0
        except (OSError, ValueError, urllib.error.URLError, ET.ParseError) as error:
            if attempt == args.attempts:
                print(f"appcast 在 {args.attempts} 次尝试后仍未就绪：{error}", file=sys.stderr)
                return 1
            print(f"appcast 检查 {attempt}/{args.attempts} 未就绪：{error}")
            time.sleep(args.delay)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
