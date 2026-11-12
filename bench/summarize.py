#!/usr/bin/env python3
"""Summarises bench.py results: summarize.py <dir of <mode>-<round>.json>."""
import glob, json, os, statistics, sys

rows = {}
for f in sorted(glob.glob(os.path.join(sys.argv[1], "*.json"))):
    r = json.load(open(f))
    rows.setdefault(r["mode"], []).append(r)

print("| config | runs | mean fps | worst 1 s fps | seconds below 29 fps | CPU cores | peak RAM MB |")
print("|---|---|---|---|---|---|---|")
for mode in ("port", "port-enhanced", "crossover", "crossover-dxvk"):
    rs = rows.get(mode)
    if not rs:
        continue
    fps = [x for r in rs for x in r["fps"]]
    print(f"| {mode} | {len(rs)} | {statistics.mean(fps):.1f} | {min(fps):.1f} | "
          f"{sum(x < 29 for x in fps)} of {len(fps)} | "
          f"{statistics.mean(r['cpu_cores'] for r in rs):.2f} | "
          f"{statistics.mean(r['rss_peak_mb'] for r in rs):.0f} |")
