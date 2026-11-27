#!/bin/zsh
# miroe W1: the 32-bit game-like test with and without NX_COMPAT, on the Intel lab engine (WineHQ 11.21 + DXMT v0.80,
# Rosetta) and on its clone with the lazy-exec ntdll.so (WINE_LAZY_EXEC=0 is the same build with the old behaviour).
# Off screen; neutral test program only.
[[ -z "$MIROE_CAFFEINATED" ]] && exec env MIROE_CAFFEINATED=1 caffeinate -i "$0" "$@"
L=/Users/Shared/MiroEngineLab O=/Users/Shared/miroe-lab/logs/w1/matrix T=/Users/Shared/miroe-lab/tests
mkdir -p $O
for r in $(seq 1 ${ROUNDS:-3}); do
  for cfg in "stock $L/engine/bin/wine 0" "lazy0 /Users/Shared/miroe-lab/engines/x64-lazy/bin/wine 0" "lazy1 /Users/Shared/miroe-lab/engines/x64-lazy/bin/wine 1"; do
    set -- ${=cfg}
    for v in nonx nx; do
      WINE_LAZY_EXEC=$3 WINEPREFIX=$L/prefix WINEDLLOVERRIDES="d3d11,dxgi,d3d10core,winemetal=b;winedbg.exe=d;winemenubuilder.exe=d" WINE_BIN=$2 \
        $L/tools/run-offscreen.sh $O/$1-$v-r$r.log $T/gametest-x86-$v.exe ${SCALE:-0.25}
      echo "$(date +%T) $1-$v-r$r $(grep -o 'phase end.*' $O/$1-$v-r$r.log)"
    done
  done
done
echo W1 MATRIX DONE
