#!/bin/bash
# usage: build-dxmt-variant.sh <name> <dxmt source dir>
# Clones the dev engine (APFS clone) to engines/<name> and builds/installs that DXMT source into it.
set -euo pipefail
name=$1 src=$2
H=/Users/Shared/miroe-lab/ref/hadron L=/Users/Shared/miroe-lab
engine=$L/engines/$name build=$L/build/dxmt-$name
mkdir -p $L/engines
[[ -d "$engine" ]] || cp -c -R "$H/dist-dev" "$engine"
export PATH="$H/toolchains/llvm-mingw/bin:$PATH"
[[ -f "$build/build.ninja" ]] || meson setup "$build" "$src" --cross-file "$src/build-arm64ec.txt" --buildtype release \
  --prefix "$engine/lib/wine" -Dnative_llvm_path="$H/toolchains/llvm15" -Dwine_build_path="$H/build/wine-dev" > "$build.setup.log" 2>&1 \
  || { tail -20 "$build.setup.log"; exit 1; }
meson compile -C "$build" > "$build.compile.log" 2>&1 || { grep -E 'error' "$build.compile.log" | head -20; exit 1; }
meson install -C "$build" --no-rebuild > "$build.install.log" 2>&1
echo "$name: $(ls -la "$engine/lib/wine/aarch64-windows/d3d11.dll" | awk '{print $6, $7, $8}') d3d11.dll installed"
