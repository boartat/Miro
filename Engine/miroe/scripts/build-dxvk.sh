#!/bin/bash
# miroe D3D8 / D3D9 backend: DXVK (zlib licence, https://github.com/doitsujin/dxvk), Vulkan through MoltenVK.
# Only d3d8.dll and d3d9.dll are built; D3D10-12 stay on Mullion + MUMA, older Direct3D and DirectDraw on WineD3D.
#   arm64x:  64-bit games, native ARM64 code (an ARM64X DLL also serves ARM64EC processes, so x86_64 games under FEX
#            call it without emulating DXVK itself)
#   i386:    32-bit games (runs under FEX through wow64)
# usage: build-dxvk.sh [engine dir]   (default /Users/Shared/miroe-lab/engines/upstream-signed)
# Source: /Users/Shared/miroe-lab/ref/dxvk at the tag in ../sources.conf (dxvk), with submodules.
# Needs: meson, ninja, glslang (Homebrew; build-time only), llvm-mingw from Hadron's toolchain.
set -euo pipefail
L=/Users/Shared/miroe-lab
SRC=${MIROE_DXVK_SRC:-$L/ref/dxvk}
ENGINE=${1:-$L/engines/upstream-signed}
OUT=${MIROE_DXVK_BUILD:-$L/build/dxvk}
export PATH="$L/ref/hadron/toolchains/llvm-mingw/bin:$(brew --prefix)/bin:$PATH"
opts=(--buildtype release --strip -Denable_dxgi=false -Denable_d3d10=false -Denable_d3d11=false -Denable_d3d8=true -Denable_d3d9=true)
build() {  # build <name> <cross file>
  local dir="$OUT/$1"
  [[ -f "$dir/build.ninja" ]] || meson setup "${opts[@]}" --cross-file "$SRC/$2" --prefix "$OUT/install-$1" "$dir" "$SRC" > "$OUT/$1-setup.log" 2>&1 \
    || { tail -30 "$OUT/$1-setup.log"; exit 1; }
  ninja -C "$dir" install > "$OUT/$1-build.log" 2>&1 || { grep -E 'error' "$OUT/$1-build.log" | head -20; exit 1; }
}
mkdir -p "$OUT"
build arm64x build-arm64x.txt
build x32 build-win32.txt
dst="$ENGINE/lib/miroe/dxvk"
mkdir -p "$dst/aarch64-windows" "$dst/i386-windows"
cp "$OUT"/install-arm64x/bin/d3d{8,9}.dll "$dst/aarch64-windows/"
cp "$OUT"/install-x32/bin/d3d{8,9}.dll "$dst/i386-windows/"
cp "$SRC/LICENSE" "$dst/LICENSE"
echo "DXVK $(git -C "$SRC" describe --tags) installed in $dst"
file "$dst"/*/*.dll
