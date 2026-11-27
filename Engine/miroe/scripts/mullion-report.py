#!/usr/bin/env python3
"""Compares scripts/mullion-matrix.sh runs (default: stock Mullion and Mullion + MUMA): regression tests, small
discards, purgeable spares kept 60 s, and the game-like test (memory at phase ends, peaks, frame times)."""
import csv, os, re, statistics as st, sys
L = "/Users/Shared/miroe-lab/logs"
names = sys.argv[1:] or ["mullion", "mullion-muma"]
def last(d):
    rows = [r for r in csv.DictReader(open(os.path.join(d, "memory.tsv")), delimiter="\t") if r["phase"].startswith("phase")]
    return rows[-1] if rows else None
for n in names:
    O = os.path.join(L, n)
    print("== %s" % n)
    for t in ("buf", "idle", "tex", "keep60", "keep60-nopurge"):
        d = os.path.join(O, t)
        if not os.path.exists(os.path.join(d, "memory.tsv")):
            continue
        r = last(d); log = open(os.path.join(d, "wine.log"), errors="replace").read()
        v = re.search(r"verify ok|FAIL[^\n]*", log)
        print("  %-15s last %5s MB footprint, %5s MB GPU  %s" % (t, r["footprint_mb"], r["gpu_mb"], v.group(0) if v else ""))
    xs = []
    for i in (1, 2, 3):
        f = os.path.join(O, "small-%d.log" % i)
        m = os.path.exists(f) and re.search(r"([\d.]+) ms/frame", open(f).read())
        if m: xs.append(float(m.group(1)))
    if xs: print("  small discards  %.3f ms/frame %s" % (st.mean(xs), xs))
    mem = {"normal2": [], "menu": []}; gpu = {"normal2": [], "menu": []}; peak = {"fight1": [], "fight2": []}; ft = {"fight1": [], "fight2": []}; ok = 0
    for i in (1, 2, 3):
        d = os.path.join(O, "game-r%d" % i)
        if not os.path.exists(os.path.join(d, "wine.log")): continue
        log = open(os.path.join(d, "wine.log"), errors="replace").read()
        m = re.search(r"phase end t=([\d.]+)", log)
        if not m or float(m.group(1)) > 90: continue
        ok += 1; endp, endg, pk = {}, {}, {}
        for r in csv.DictReader(open(os.path.join(d, "memory.tsv")), delimiter="\t"):
            p = re.match(r"phase (\w+)", r["phase"] or "")
            if not p: continue
            k = p.group(1); endp[k] = int(r["footprint_mb"] or 0); endg[k] = int(r["gpu_mb"] or 0); pk[k] = max(pk.get(k, 0), endp[k])
        for k in mem: mem[k].append(endp.get(k, 0)); gpu[k].append(endg.get(k, 0))
        for k in peak: peak[k].append(pk.get(k, 0))
        for k in ft:
            s = re.search(r"stats %s\s+frames\s+\d+\s+avg\s+([\d.]+) ms\s+p50\s+[\d.]+\s+p95\s+[\d.]+\s+p99\s+([\d.]+)\s+max\s+([\d.]+)" % k, log)
            if s: ft[k].append(tuple(float(x) for x in s.groups()))
    f = lambda xs: "%.0f" % st.mean(xs) if xs else "-"
    g = lambda xs, i: "%.2f" % st.mean(x[i] for x in xs) if xs else "-"
    print("  game runs %d | after fight1 %s (GPU %s), menu %s (GPU %s) MB | peaks %s / %s MB" % (ok, f(mem["normal2"]), f(gpu["normal2"]), f(mem["menu"]), f(gpu["menu"]), f(peak["fight1"]), f(peak["fight2"])))
    print("            | fight1 avg/p99 %s/%s ms | fight2 avg/p99/max %s/%s/%s ms" % (g(ft["fight1"], 0), g(ft["fight1"], 1), g(ft["fight2"], 0), g(ft["fight2"], 1), g(ft["fight2"], 2)))
