#!/bin/zsh
# usage: run.sh <log> <program> [args] — runs a Windows program on the miroe lab ARM64 engine, off screen.
# Environment as in Hadron's scripts/wine-run; windows are watched by the lab's run-offscreen.sh guard.
export WINEPREFIX=${WINEPREFIX:-/Users/Shared/miroe-lab/prefix}
export MIRO_DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib
export FEX_DISKCACHE=1 FEX_DISKCACHEMAXFILESIZE=4294967296 MTLD3D_NO_CRASH_HANDLER=1
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mshtml=};winedbg.exe=d;winemenubuilder.exe=d"
WINE_BIN=${MIROE_DIST:-/Users/Shared/miroe-lab/ref/hadron/dist-dev}/bin/wine exec /Users/Shared/MiroEngineLab/tools/run-offscreen.sh "$@"
