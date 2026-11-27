#!/usr/bin/env python3
"""Summarizes scripts/v2-matrix.sh: v2 regressions, small-discard speed, the game-like match and the 800 MB budget."""
import csv, os, re, statistics as st
O = "/Users/Shared/miroe-lab/logs/v2"
def last(name):
    rows = list(csv.DictReader(open(os.path.join(O, name, "memory.tsv")), delimiter="\t"))
    rows = [r for r in rows if r["phase"].startswith("phase")]
    return rows[-1] if rows else None
for name in ("buf", "idle", "tex"):
    r = last(name); log = open(os.path.join(O, name, "wine.log"), errors="replace").read()
    v = re.search(r"verify ok|FAIL[^\n]*", log)
    print("%-5s last sample %s MB footprint, %s MB GPU  %s" % (name, r["footprint_mb"], r["gpu_mb"], v.group(0) if v else ""))
for v in ("v1", "v2"):
    xs = [float(re.search(r"([\d.]+) ms/frame", open(os.path.join(O, "small-%s-%d.log" % (v, i))).read()).group(1)) for i in (1, 2, 3)]
    print("small discards %s: %.3f ms/frame %s" % (v, st.mean(xs), xs))
def game(prefix):
    mem = {"normal2": [], "menu": []}; peak = {"fight1": [], "fight2": []}; ft = {"fight1": [], "fight2": []}; ok = 0
    for i in (1, 2, 3):
        d = os.path.join(O, "%s-r%d" % (prefix, i))
        log = open(os.path.join(d, "wine.log"), errors="replace").read()
        m = re.search(r"phase end t=([\d.]+)", log)
        if not m or float(m.group(1)) > 90: continue
        ok += 1
        endp, pk = {}, {}
        for r in csv.DictReader(open(os.path.join(d, "memory.tsv")), delimiter="\t"):
            p = re.match(r"phase (\w+)", r["phase"] or "")
            if not p: continue
            endp[p.group(1)] = int(r["footprint_mb"] or 0); pk[p.group(1)] = max(pk.get(p.group(1), 0), int(r["footprint_mb"] or 0))
        for k in mem: mem[k].append(endp.get(k, 0))
        for k in peak: peak[k].append(pk.get(k, 0))
        for k in ft:
            s = re.search(r"stats %s\s+frames\s+\d+\s+avg\s+([\d.]+) ms\s+p50\s+[\d.]+\s+p95\s+[\d.]+\s+p99\s+([\d.]+)\s+max\s+([\d.]+)" % k, log)
            ft[k].append(tuple(float(x) for x in s.groups()))
    f = lambda xs: "%.0f" % st.mean(xs) if xs else "-"
    g = lambda xs, i: "%.2f" % st.mean(x[i] for x in xs) if xs else "-"
    print("%-12s runs %d | end normal2 %s, menu %s MB | peak fight1 %s, fight2 %s MB | fight1 avg/p99 %s/%s | fight2 avg/p99/max %s/%s/%s ms" % (
        prefix, ok, f(mem["normal2"]), f(mem["menu"]), f(peak["fight1"]), f(peak["fight2"]),
        g(ft["fight1"], 0), g(ft["fight1"], 1), g(ft["fight2"], 0), g(ft["fight2"], 1), g(ft["fight2"], 2)))
for prefix in ("game-v2", "game800-v1", "game800-v2"):
    game(prefix)
