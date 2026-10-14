#!/usr/bin/env python3
"""Download public CC0 sample DNGs (Leica M10 and Q2) from raw.pixls.us for the integration test.

Only files whose license is CC0 are used (older uploads there may have stricter licenses).
Files go to testdata/downloaded/ (git-ignored). Used in CI and optionally locally.

usage: scripts/fetch-samples.py [target-dir]
"""
import json
import os
import sys
import urllib.parse
import urllib.request

API = "https://raw.pixls.us/json/getall.json"
WANTED = [("Leica", "M10"), ("Leica", "Q2")]
MAX_BYTES = 120 * 1024 * 1024


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "pano-squeezer-integration-test"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def main():
    target = sys.argv[1] if len(sys.argv) > 1 else "testdata/downloaded"
    os.makedirs(target, exist_ok=True)
    try:
        listing = json.loads(fetch(API))
    except Exception as e:  # noqa: BLE001
        print(f"warning: cannot read {API}: {e}")
        return 0
    rows = listing.get("data", listing) if isinstance(listing, dict) else listing
    if rows and isinstance(rows, list):
        print(f"{len(rows)} entries, keys of first entry: {sorted(rows[0].keys()) if isinstance(rows[0], dict) else rows[0]}")

    def field(row, *names):
        for n in names:
            for k, v in row.items():
                if k.lower() == n:
                    return str(v)
        return ""

    got = 0
    for make, model in WANTED:
        candidates = [r for r in rows if isinstance(r, dict)
                      and field(r, "make").lower() == make.lower()
                      and field(r, "model").strip().lower() == model.lower()]
        print(f"{make} {model}: {len(candidates)} sample(s)")
        for r in candidates:
            lic = field(r, "license")
            name = field(r, "filename", "file")
            print(f"  {name!r} license={lic!r}")
            if "cc0" not in lic.lower().replace(" ", "").replace("-", "") or not name.lower().endswith(".dng"):
                continue
            url = field(r, "url", "raw_url", "download")
            if not url:
                url = "https://raw.pixls.us/data/" + "/".join(urllib.parse.quote(p) for p in (make, model, name))
            dest = os.path.join(target, f"{make}-{model}-{name}".replace(" ", "_"))
            if not os.path.exists(dest):
                print(f"  downloading {url}")
                try:
                    data = fetch(url)
                except Exception as e:  # noqa: BLE001
                    print(f"  warning: download failed: {e}")
                    continue
                if len(data) > MAX_BYTES:
                    continue
                with open(dest, "wb") as f:
                    f.write(data)
            got += 1
            break  # one file per camera is enough
    print(f"{got} sample(s) available in {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
