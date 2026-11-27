#!/bin/zsh
# Mullion on the ARM64 engine: the MUMA regression tests and the game-like test, for one engine (default: stock Mullion).
# usage: mullion-matrix.sh <engine name under engines/> <log folder name> [rounds]
[[ -z "$MIROE_CAFFEINATED" ]] && exec env MIROE_CAFFEINATED=1 caffeinate -i "$0" "$@"
eng=${1:-mullion} name=${2:-mullion} rounds=${3:-3}
T=/Users/Shared/miroe-lab/tests O=/Users/Shared/miroe-lab/logs/$name E=/Users/Shared/miroe-lab/engines
MW=${0:A:h}/../tools/memwatch.sh; [[ -x $MW ]] || MW=/Users/Shared/Miro-src/Engine/miroe/tools/memwatch.sh
mkdir -p $O
mw() { local n=$1 exe=$2; shift 2
  MIROE_DIST=$E/$eng TARGET=$exe WINEDLLOVERRIDES="d3d11,dxgi,d3d10core,d3d12,d3d12core,winemetal=b" "$MW" $O/$n /Users/Shared/miroe-lab/prefix 1 -- \
    /Users/Shared/miroe-lab/scripts/run.sh '{log}' $T/$exe "$@" > $O/$n.summary 2>&1; echo "$(date +%T) $n done"; }
mw buf memtest-arm64.exe buffers 600 3000 5
mw idle memtest-arm64.exe buffers 600 0 15
mw tex memtest-arm64.exe textures 300 3000 5
# spares kept 60 s: purgeable on, then off (the heartbeat must not keep purgeable spares resident)
MIROE_MUMA_FREE_MS=60000 mw keep60 memtest-arm64.exe buffers 600 3000 5
MIROE_MUMA_FREE_MS=60000 MIROE_MUMA_PURGEABLE=0 mw keep60-nopurge memtest-arm64.exe buffers 600 3000 5
for r in 1 2 3; do MIROE_DIST=$E/$eng WINEDLLOVERRIDES="d3d11,dxgi,d3d10core,d3d12,d3d12core,winemetal=b" /Users/Shared/miroe-lab/scripts/run.sh $O/small-$r.log $T/memtest-arm64.exe small 300 >/dev/null 2>&1; done
for r in $(seq 1 $rounds); do mw game-r$r gametest-arm64.exe 1; done
echo MULLION MATRIX DONE
