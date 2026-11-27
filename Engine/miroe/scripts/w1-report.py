#!/usr/bin/env python3
"""Summarizes scripts/w1-matrix.sh: frames per run and frame time per phase, per engine and NX_COMPAT setting."""
import glob, os, re, statistics as st
O = "/Users/Shared/miroe-lab/logs/w1/matrix"
rows = {}
for f in sorted(glob.glob(os.path.join(O, "*-r*.log"))):
    name = re.sub(r"-r\d+\.log$", "", os.path.basename(f))
    log = open(f, errors="replace").read()
    m = re.search(r"phase end t=([\d.]+)s frames=(\d+)", log)
    if not m:
        continue
    r = rows.setdefault(name, {"frames": [], "stalls": [], "phases": {}})
    r["frames"].append(int(m.group(2)))
    for s in re.finditer(r"stats (\w+)\s+frames\s+\d+\s+avg\s+([\d.]+) ms\s+p50\s+[\d.]+\s+p95\s+[\d.]+\s+p99\s+([\d.]+)\s+max\s+([\d.]+)", log):
        r["phases"].setdefault(s.group(1), []).append(tuple(float(x) for x in s.groups()[1:]))
print("%-12s %5s %-22s %-28s %-28s %-24s" % ("run", "runs", "frames (each)", "normal1 avg/p99/max ms", "fight1 avg/p99/max ms", "menu avg/max ms"))
for name in sorted(rows):
    r = rows[name]
    def ph(p, n=3):
        xs = r["phases"].get(p, [])
        if not xs: return "-"
        return "/".join("%.2f" % st.mean(x[i] for x in xs) for i in range(3) if n == 3 or i != 1)
    print("%-12s %5d %-22s %-28s %-28s %-24s" % (name, len(r["frames"]), "%.0f %s" % (st.mean(r["frames"]), r["frames"]),
          ph("normal1"), ph("fight1"), ph("menu", 2)))
