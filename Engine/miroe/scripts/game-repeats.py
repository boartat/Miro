#!/usr/bin/env python3
"""Averages the game-like test over runs (run 1 = <variant>/, runs 2-3 = <variant>-r2/, -r3/)."""
import csv, os, re, statistics as st
O = "/Users/Shared/miroe-lab/logs/game"
def runs(v):
    """Valid runs only: a run the Mac slept through (program end after 90 s) is left out"""
    out = []
    for d in [v] + [v + "-r%d" % i for i in range(2, 6)]:
        log = os.path.join(O, d, "wine.log")
        if not os.path.exists(log):
            continue
        m = re.search(r"phase end t=([\d.]+)", open(log, errors="replace").read())
        if m and float(m.group(1)) <= 90:
            out.append(d)
    return out[:3]
def mem(d):
    out = {}
    for r in csv.DictReader(open(os.path.join(O, d, "memory.tsv")), delimiter="\t"):
        m = re.match(r"phase (\w+)", r["phase"] or "")
        if m:
            out[m.group(1)] = (int(r["footprint_mb"] or 0), int(r["gpu_mb"] or 0))
    return out
def stats(d):
    out = {}
    for line in open(os.path.join(O, d, "wine.log"), errors="replace"):
        m = re.match(r"stats (\w+)\s+frames\s+(\d+)\s+avg\s+([\d.]+) ms\s+p50\s+([\d.]+)\s+p95\s+([\d.]+)\s+p99\s+([\d.]+)\s+max\s+([\d.]+)", line)
        if m:
            out[m.group(1)] = [float(x) for x in m.groups()[1:]]
    return out
for v in ["base", "v1", "v1-keep30"]:
    rs = runs(v)
    ms = [mem(d) for d in rs]; ss = [stats(d) for d in rs]
    def m_(p, i): return st.mean(x[p][i] for x in ms if p in x)
    def s_(p, i): vals = [x[p][i] for x in ss if p in x]; return st.mean(vals), (max(vals) - min(vals)) / 2
    print("%-10s runs=%d (%s) | end of normal2 %4.0f MB (GPU %3.0f) | end of menu %4.0f MB (GPU %3.0f)" %
          (v, len(rs), ",".join(rs), m_("normal2", 0), m_("normal2", 1), m_("menu", 0), m_("menu", 1)))
    for p in ["fight1", "fight2", "normal2"]:
        a, ad = s_(p, 1); q, qd = s_(p, 4); x, xd = s_(p, 5)
        print("           %-8s avg %.2f ±%.2f  p99 %.2f ±%.2f  max %5.1f ±%.1f ms" % (p, a, ad, q, qd, x, xd))
