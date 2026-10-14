#!/usr/bin/env python3
"""Download public CC0 sample DNGs (Leica M10 and Q2) from raw.pixls.us for the integration test.

Only files whose license is CC0 are used (older uploads there may have stricter licenses).
Files go to testdata/downloaded/ (git-ignored). Used in CI and optionally locally.

usage: scripts/fetch-samples.py [target-dir]
"""
import json
import os
import re
import sys
import urllib.parse
import urllib.request

BASE = "https://raw.pixls.us"
REPOSITORY = BASE + "/json/getrepository.php?set=all"
CAMERAS = [("Leica", "M10"), ("Leica", "Q2")]
MAX_BYTES = 150 * 1024 * 1024


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "pano-squeezer-integration-test"})
    with urllib.request.urlopen(req, timeout=300) as r:
        return r.read()


def rows_of(listing):
    """The repository JSON is a list of rows (or {"data": [...]}); rows can be lists or dicts."""
    if isinstance(listing, dict):
        for key in ("data", "rows", "aaData"):
            if key in listing:
                return listing[key]
        return list(listing.values())
    return listing


def main():
    target = sys.argv[1] if len(sys.argv) > 1 else "testdata/downloaded"
    os.makedirs(target, exist_ok=True)
    try:
        rows = rows_of(json.loads(fetch(REPOSITORY)))
    except Exception as e:  # noqa: BLE001
        print(f"warning: cannot read {REPOSITORY}: {e}")
        return 0
    print(f"repository: {len(rows)} entries")

    got = 0
    for make, model in CAMERAS:
        folder = f"{BASE}/data/{urllib.parse.quote(make)}/{urllib.parse.quote(model)}/"
        try:
            index = fetch(folder).decode("utf-8", "replace")
        except Exception as e:  # noqa: BLE001
            print(f"warning: cannot list {folder}: {e}")
            continue
        files = [urllib.parse.unquote(f) for f in re.findall(r'href="([^"?/][^"]*\.dng)"', index, re.IGNORECASE)]
        for name in files:
            matches = [r for r in rows if name in json.dumps(r, ensure_ascii=False)]
            text = json.dumps(matches, ensure_ascii=False)
            print(f"{make} {model} {name}: {text[:400]}")
            if not matches or "cc0" not in text.lower():
                print(f"  skipped: license is not CC0 (or unknown)")
                continue
            dest = os.path.join(target, f"{make}-{model}-{name}".replace(" ", "_"))
            if os.path.exists(dest):
                print(f"  cached: {dest}")
            else:
                print(f"  downloading {folder}{name}")
                try:
                    data = fetch(folder + urllib.parse.quote(name))
                except Exception as e:  # noqa: BLE001
                    print(f"  warning: download failed: {e}")
                    continue
                if len(data) > MAX_BYTES:
                    print("  skipped: too large")
                    continue
                with open(dest, "wb") as f:
                    f.write(data)
            got += 1
            break  # one file per camera is enough
    print(f"{got} sample(s) available in {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
