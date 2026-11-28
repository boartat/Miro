#!/bin/bash
# Builds Mullion (with miroe's patches applied in the source tree) against the upstream ARM64 Wine build and installs
# it into an engine made from that build: ARM64X DLLs + the aarch64 unix library (arm64ec cross file), and the
# i386 DLLs for 32-bit games (win32 cross file; Direct3D 12 has no 32-bit build). 32-bit callers reach the same
# aarch64 unix library through Wine's wow64 thunks.
# usage: build-mullion-upstream.sh <engine dir> [mullion source dir]
#   engine dir: an installed upstream Wine (scripts/build-wine-upstream.sh, then scripts/sign-engine.sh)
set -euo pipefail
engine=${1:?usage: build-mullion-upstream.sh <engine dir> [mullion source]}
L=/Users/Shared/miroe-lab
src=${2:-$L/src/mullion-muma}
H=$L/ref/hadron
wine_build=${MIROE_WINE_BUILD:-$L/build/wine-upstream}
export PATH="$H/toolchains/llvm-mingw/bin:$PATH"
name=$(basename "$engine")
for cross in arm64ec win32; do
  build=$L/build/mullion-$name-$cross
  [[ -f "$build/build.ninja" ]] || meson setup "$build" "$src" --cross-file "$src/build-$cross.txt" --buildtype release \
    --prefix "$engine/lib/wine" -Dnative_llvm_path="$H/toolchains/llvm15" -Dwine_build_path="$wine_build" \
    > "$build.setup.log" 2>&1 || { tail -20 "$build.setup.log"; exit 1; }
  meson compile -C "$build" > "$build.compile.log" 2>&1 || { grep -E 'error' "$build.compile.log" | head -20; exit 1; }
  meson install -C "$build" --no-rebuild > "$build.install.log" 2>&1
  echo "$cross: installed into $engine/lib/wine"
done
ls -la "$engine/lib/wine/aarch64-windows/d3d11.dll" "$engine/lib/wine/i386-windows/d3d11.dll" "$engine/lib/wine/aarch64-unix/winemetal.so"
