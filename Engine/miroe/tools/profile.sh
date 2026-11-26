#!/bin/zsh
# Profiles a Windows program running on a Wine engine and shows which layer its CPU time goes to.
#
#   profile.sh <out folder> <prefix> <seconds> -- <runner ...>
#
# The runner command starts the program and must write Wine's output to the file given as {log}
# (for example the lab's run-offscreen.sh, which keeps every window off screen). profile.sh adds
# waits for TARGET (default bench.exe) to warm up, records SECONDS with the Instruments Time Profiler,
# saves the process's memory map, then runs frame-breakdown.py. Use neutral test programs only.
set -eu
out=$1 prefix=$2 seconds=$3; shift 3
[ "$1" = "--" ] && shift
target=${TARGET:-bench.exe} warmup=${WARMUP:-6}
here=${0:A:h}
mkdir -p "$out"
log="$out/wine.log"
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
[ -n "$pid" ] || { echo "profile.sh: $target did not start"; wait $runner_pid; exit 1; }
python3 -I -c "import time; time.sleep($warmup)"

rm -rf "$out/run.trace"
xctrace record --template 'Time Profiler' --attach "$pid" --time-limit "${seconds}s" \
  --output "$out/run.trace" --no-prompt >/dev/null
xctrace export --input "$out/run.trace" --output "$out/samples.xml" \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' >/dev/null
# Rosetta maps translated code per process, so the memory map must come from the same process
vmmap -noCoalesce "$pid" > "$out/vmmap.txt" 2>/dev/null
wait $runner_pid || true

python3 -I "$here/frame-breakdown.py" --samples "$out/samples.xml" --vmmap "$out/vmmap.txt" \
  | tee "$out/breakdown.txt"
