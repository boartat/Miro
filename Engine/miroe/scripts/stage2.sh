#!/bin/bash
# miroe lab stage 2: ARM64 Wine (our llvm-mingw variant of Hadron's script), then FEX and DXMT with Hadron's scripts
set -euo pipefail
H=/Users/Shared/miroe-lab/ref/hadron
S=/Users/Shared/miroe-lab/scripts
echo "== wine $(date +%T)"; "$S/build-wine.sh"
echo "== fex $(date +%T)"; bash "$H/scripts/build-fex.sh" 2>&1 | tail -4
W="$H/dist/lib/wine/aarch64-windows"; ls -la "$W"/xtajit*.dll
echo "== dxmt $(date +%T)"; bash "$H/scripts/build-dxmt.sh" 2>&1 | tail -6
ls "$H/dist/lib/wine/aarch64-windows" | grep -iE 'd3d11|dxgi|winemetal' || true
ls "$H/dist/lib/wine/aarch64-unix" | grep -iE 'winemetal' || true
echo "STAGE2 DONE $(date +%T)"
