#!/bin/zsh
# MUMA v2 checks: regressions against v1, the game-like match, and a simulated Mac near its memory budget.
[[ -z "$MIROE_CAFFEINATED" ]] && exec env MIROE_CAFFEINATED=1 caffeinate -i "$0" "$@"
T=/Users/Shared/miroe-lab/tests O=/Users/Shared/miroe-lab/logs/v2 E=/Users/Shared/miroe-lab/engines
MW=${0:A:h}/../tools/memwatch.sh
mw() { local name=$1 eng=$2 exe=$3; shift 3
  MIROE_DIST=$E/$eng TARGET=$exe WINEDLLOVERRIDES="d3d11,dxgi,d3d10core,winemetal=b" "$MW" $O/$name /Users/Shared/miroe-lab/prefix 1 -- \
    /Users/Shared/miroe-lab/scripts/run.sh '{log}' $T/$exe "$@" > $O/$name.summary 2>&1; }
mw buf muma-v2 memtest-arm64.exe buffers 600 3000 5
mw idle muma-v2 memtest-arm64.exe buffers 600 0 15
mw tex muma-v2 memtest-arm64.exe textures 300 3000 5
for r in 1 2 3; do for v in v1 v2; do MIROE_DIST=$E/muma-$v WINEDLLOVERRIDES="d3d11,dxgi,d3d10core,winemetal=b" /Users/Shared/miroe-lab/scripts/run.sh $O/small-$v-$r.log $T/memtest-arm64.exe small 300 >/dev/null 2>&1; done; done
for r in 1 2 3; do
  mw game-v2-r$r muma-v2 gametest-arm64.exe 1
  MIROE_MUMA_BUDGET_MB=800 mw game800-v1-r$r muma-v1 gametest-arm64.exe 1
  MIROE_MUMA_BUDGET_MB=800 mw game800-v2-r$r muma-v2 gametest-arm64.exe 1
done
echo V2 MATRIX DONE
