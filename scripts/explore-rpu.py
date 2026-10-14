#!/usr/bin/env python3
"""Temporary diagnostic: print the structure of raw.pixls.us so fetch-samples.py can use it."""
import re
import urllib.request

def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "pano-squeezer-integration-test"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, r.read().decode("utf-8", "replace")
    except Exception as e:  # noqa: BLE001
        return None, str(e)

for url in ["https://raw.pixls.us/", "https://raw.pixls.us/data/Leica/", "https://raw.pixls.us/data/Leica/M10/",
            "https://raw.pixls.us/data/Leica/Q2/", "https://raw.pixls.us/data-unique/Leica/Q2/"]:
    status, body = get(url)
    print(f"===== {url} -> {status}, {len(body)} chars")
    print(body[:1500])
    for m in sorted(set(re.findall(r'(?:href|src)="([^"]+)"', body)))[:80]:
        print("   link:", m)
    for m in sorted(set(re.findall(r'["\']([^"\']*(?:json|api|\.php)[^"\']*)["\']', body)))[:40]:
        print("   api?:", m)
