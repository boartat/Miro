#!/bin/bash
# miroe lab: the --dev engine (64-bit only, no restricted entitlement): Wine dev build, FEX and DXMT into dist-dev
set -euo pipefail
H=/Users/Shared/miroe-lab/ref/hadron S=/Users/Shared/miroe-lab/scripts
echo "== wine (dev) $(date +%T)"; "$S/build-wine.sh" --dev
echo "== fex (dev) $(date +%T)"; bash "$H/scripts/build-fex.sh" --dev 2>&1 | tail -3
W="$H/dist-dev/lib/wine/aarch64-windows"; rm -f "$W/xtajit.dll" "$W/xtajit64.dll"; cp "$W/libwow64fex.dll" "$W/xtajit.dll"; cp "$W/libarm64ecfex.dll" "$W/xtajit64.dll"
echo "== dxmt (dev) $(date +%T)"; bash "$H/scripts/build-dxmt.sh" --dev 2>&1 | tail -3
echo "STAGE2-DEV DONE $(date +%T)"
