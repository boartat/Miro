#!/bin/zsh
# Keep the Mac awake for the whole matrix: a run the Mac sleeps through is invalid (frames of minutes).
[[ -z "$MIROE_CAFFEINATED" ]] && exec env MIROE_CAFFEINATED=1 caffeinate -i "$0" "$@"
# Runs the game-like test (Engine/tests/c/d3d11-game-test.c) on each DXMT variant with memory sampling.
T=/Users/Shared/miroe-lab/tests O=/Users/Shared/miroe-lab/logs/game E=/Users/Shared/miroe-lab/engines
MW=${0:A:h}/../tools/memwatch.sh
for cfg in "base /Users/Shared/miroe-lab/ref/hadron/dist-dev 2000" "author $E/author 2000" "v0 $E/muma-v0 2000" "v1 $E/muma-v1 2000" "v1-keep30 $E/muma-v1 30000"; do
  set -- ${=cfg}
  echo "=== $1"
  MIROE_MUMA_FREE_MS=$3 MIROE_DIST=$2 TARGET=gametest-arm64.exe WINEDLLOVERRIDES="d3d11,dxgi,d3d10core,winemetal=b" \
    "$MW" $O/$1 /Users/Shared/miroe-lab/prefix 1 -- /Users/Shared/miroe-lab/scripts/run.sh '{log}' $T/gametest-arm64.exe 1 > $O/$1.summary 2>&1
  grep -E '^stats|FAIL' $O/$1/wine.log
done
echo MATRIX DONE
