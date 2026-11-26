#!/usr/bin/env python3
"""Summarizes the game-like test matrix: memory (peak, end of phase) and frame times per phase and variant."""
import csv, os, re, sys
O = sys.argv[1] if len(sys.argv) > 1 else "/Users/Shared/miroe-lab/logs/game"
variants = ["base", "author", "v0", "v1", "v1-keep30"]
phases = ["warmup", "normal1", "fight1", "normal2", "fight2", "menu"]
mem, stats = {}, {}
for v in variants:
    tsv = os.path.join(O, v, "memory.tsv")
    if not os.path.exists(tsv):
        continue
    rows = list(csv.DictReader(open(tsv), delimiter="\t"))
    per = {}
    for r in rows:
        m = re.match(r"phase (\w+)", r["phase"] or "")
        if not m:
            continue
        name = m.group(1)
        fp, gpu = int(r["footprint_mb"] or 0), int(r["gpu_mb"] or 0)
        d = per.setdefault(name, {"peak": 0, "end": 0, "end_gpu": 0})
        d["peak"] = max(d["peak"], fp)
        d["end"], d["end_gpu"] = fp, gpu
    mem[v] = per
    for line in open(os.path.join(O, v, "wine.log"), errors="replace"):
        m = re.match(r"stats (\w+)\s+frames\s+(\d+)\s+avg\s+([\d.]+) ms\s+p50\s+([\d.]+)\s+p95\s+([\d.]+)\s+p99\s+([\d.]+)\s+max\s+([\d.]+)", line)
        if m:
            stats.setdefault(v, {})[m.group(1)] = [float(x) for x in m.groups()[1:]]
print("MEMORY: footprint at the end of each phase in MB (GPU part), peak footprint in brackets")
print("%-10s" % "variant" + "".join("%-20s" % p for p in phases))
for v in variants:
    if v not in mem: continue
    cells = []
    for p in phases:
        d = mem[v].get(p)
        cells.append("%-20s" % ("%d (%d) [%d]" % (d["end"], d["end_gpu"], d["peak"]) if d else "-"))
    print("%-10s" % v + "".join(cells))
print("\nFRAME TIME ms: avg / p99 / max")
print("%-10s" % "variant" + "".join("%-20s" % p for p in phases))
for v in variants:
    if v not in stats: continue
    cells = []
    for p in phases:
        s = stats[v].get(p)
        cells.append("%-20s" % ("%.2f / %.2f / %.1f" % (s[1], s[4], s[5]) if s else "-"))
    print("%-10s" % v + "".join(cells))
