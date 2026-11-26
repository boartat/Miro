#!/bin/zsh
# Samples a Windows program's memory from the Mac side while it runs.
#
#   memwatch.sh <out folder> <prefix> <interval s> -- <runner ...>
#
# Like profile.sh, the runner starts the program and writes Wine's output to {log}. Every interval this
# records the process footprint, its GPU (IOAccelerator) part and the program's latest "phase" line, so a
# test like Engine/tests/d3d11-memory-test.cs shows whether memory comes back after a burst.
set -eu
out=$1 prefix=$2 interval=$3; shift 3
[ "$1" = "--" ] && shift
target=${TARGET:-memtest.exe}
mkdir -p "$out"
log="$out/wine.log" samples="$out/memory.tsv"
runner=("${@//\{log\}/$log}")

export WINEPREFIX="$prefix"
"${runner[@]}" &
runner_pid=$!

pid=""
for i in {1..120}; do
  pid=$(pgrep -f "^[^ ]*${target//./\\.}( |\$)" | head -1 || true)
  [ -n "$pid" ] && break
  python3 -I -c 'import time; time.sleep(0.25)'
done
[ -n "$pid" ] || { echo "memwatch.sh: $target did not start"; wait $runner_pid; exit 1; }

printf "seconds\tfootprint_mb\tgpu_mb\tphase\n" > "$samples"
start=$(date +%s)
while kill -0 "$pid" 2>/dev/null; do
  report=$(footprint -p "$pid" 2>/dev/null || true)
  total=$(print -r -- "$report" | awk '/Footprint:/ { for (i = 1; i <= NF; i++) if ($i == "Footprint:") { v = $(i+1); u = $(i+2) } }
    END { if (u == "GB") v *= 1024; else if (u == "KB") v /= 1024; else if (u == "B") v /= 1048576; printf "%.0f", v }')
  gpu=$(print -r -- "$report" | awk '/IOAccelerator/ { v = $1; u = $2; if (u == "GB") v *= 1024; else if (u == "KB") v /= 1024; else if (u == "B") v /= 1048576; s += v }
    END { printf "%.0f", s }')
  phase=$(grep -a -E '^(phase|DONE)' "$log" 2>/dev/null | tail -1 | cut -d' ' -f1-2 || true)
  printf "%d\t%s\t%s\t%s\n" $(( $(date +%s) - start )) "$total" "$gpu" "$phase" >> "$samples"
  python3 -I -c "import time; time.sleep($interval)"
done
wait $runner_pid || true

grep -a -E '^(device|phase|DONE|FAIL)' "$log" || true
grep -a -c 'forced to allocate new block' "$log" | sed 's/^/DXMT "forced to allocate new block" warnings: /' || true
# Peak of each phase, then the last sample
python3 -I - "$samples" <<'PY'
import csv, sys
rows = list(csv.DictReader(open(sys.argv[1]), delimiter="\t"))
peaks = {}
for r in rows:
    key = r["phase"] or "start"
    peaks[key] = max(peaks.get(key, 0), int(r["footprint_mb"] or 0))
for key, value in peaks.items():
    print("peak footprint during %-12s %6d MB" % (key, value))
if rows:
    print("last sample: %s MB footprint, %s MB GPU (%s)" % (rows[-1]["footprint_mb"], rows[-1]["gpu_mb"], rows[-1]["phase"]))
PY
