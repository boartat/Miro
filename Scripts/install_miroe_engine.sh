#!/bin/zsh
# Installs the miroe experimental engine (upstream ARM64 Wine + FEX + Mullion with miroe's patches) into Miro's engine folder,
# where Miro finds it as "miroe (실험)". The engine is built in the miroe lab (Engine/miroe/scripts); this copies it
# with APFS clones (no extra disk space on the same volume) and bundles the host libraries it loads (FreeType, GnuTLS,
# MoltenVK), so it needs no Homebrew at run time.
#
# usage: Scripts/install_miroe_engine.sh [built engine folder]   (default: /Users/Shared/miroe-lab/engines/miroe-2)
#
# The engine is made by Engine/miroe/scripts: build-wine-upstream.sh, sign-engine.sh (loader signed with a development
# provisioning profile for Apple's cross-architecture entitlement, FEX installed), build-mullion-upstream.sh and build-dxvk.sh.
# The signed loader runs only on Macs listed in that profile. The copy keeps its signature: nothing in wine.app changes.
set -euo pipefail
src=${1:-/Users/Shared/miroe-lab/engines/miroe-2}
dest=${MIROE_INSTALL_DEST:-"$HOME/Library/Application Support/app.miro.Miro/Libraries/Engines/miroe"}  # MIROE_INSTALL_DEST: a test copy
[[ -x "$src/bin/wine" && -f "$src/lib/wine/aarch64-windows/d3d12.dll" ]] || { echo "not a built miroe engine: $src"; exit 1; }
loader="$src/lib/wine/aarch64-unix/wine.app"
if [[ -d "$loader" ]]; then
  codesign --verify --strict "$loader" || { echo "the engine's loader is not validly signed: run Engine/miroe/scripts/sign-engine.sh"; exit 1; }
  [[ -f "$loader/Contents/embedded.provisionprofile" ]] || { echo "the loader has no provisioning profile: run sign-engine.sh"; exit 1; }
fi

if pgrep -f "$dest/" >/dev/null; then echo "the miroe engine is running: quit its games first"; exit 1; fi
mkdir -p "${dest:h}"
if [[ -d "$dest" ]]; then mv "$dest" "$dest.old-$$"; fi
cp -c -R "$src" "$dest"

# Host libraries Wine dlopens by name, and everything they link, copied out of Homebrew, made relative and signed again:
#   FreeType (win32u: fonts), GnuTLS (secur32 / schannel: HTTPS), MoltenVK (winevulkan: Vulkan, used by DXVK)
lib="$dest/miro/lib"; mkdir -p "$lib"
brew=$(brew --prefix 2>/dev/null || echo /opt/homebrew)
roots=(freetype/lib/libfreetype.6.dylib gnutls/lib/libgnutls.30.dylib molten-vk/lib/libMoltenVK.dylib)
queue=(); for name in $roots; do queue+=("$brew/opt/$name"); done
while (( ${#queue} )); do
  f=${queue[1]}; shift queue
  [[ -f "$lib/${f:t}" ]] && continue
  [[ -f "$f" ]] || { echo "missing host library: $f (brew install freetype gnutls molten-vk)"; exit 1; }
  cp -L "$f" "$lib/"
  for dep in $(otool -L "$f" | awk 'NR>1 {print $1}' | grep "^$brew/"); do queue+=("$dep"); done
  for dep in $(otool -L "$f" | awk 'NR>1 {print $1}' | grep '^@rpath/'); do queue+=("${f:A:h}/${dep:t}"); done  # e.g. brotli
done
for f in "$lib"/*.dylib; do
  chmod u+w "$f"
  install_name_tool -id "@loader_path/${f:t}" "$f" 2>/dev/null
  for dep in $(otool -L "$f" | awk 'NR>1 {print $1}' | grep -E "^($brew/|@rpath/)"); do
    install_name_tool -change "$dep" "@loader_path/${dep:t}" "$f" 2>/dev/null
  done
  codesign -f -s - "$f" 2>/dev/null
done
if otool -L "$lib"/*.dylib | grep -qE "$brew/|@rpath/"; then echo "a bundled library still points into Homebrew"; exit 1; fi
# Licences of what is bundled (LGPL / GPL-with-exception / Apache / zlib): kept next to the libraries
mkdir -p "$dest/miro/licenses"
for pkg in freetype gnutls molten-vk gmp nettle libtasn1 libidn2 libunistring p11-kit gettext libpng brotli; do
  for f in "$brew/opt/$pkg"/{COPYING*,LICENSE*,LICENCE*,FTL.TXT}(N) "$brew/opt/$pkg"/share/doc/*/{COPYING*,LICENSE*}(N); do
    cp -L "$f" "$dest/miro/licenses/$pkg-${f:t}"
  done
done
[[ -f "$src/lib/miroe/dxvk/LICENSE" ]] && cp "$src/lib/miroe/dxvk/LICENSE" "$dest/miro/licenses/dxvk-LICENSE"
# Default Windows font: Noto Sans CJK KR (SIL OFL 1.1, Latin + Hangul + CJK). Miro copies it into each prefix's
# C:\windows\Fonts and maps the Windows UI and CJK font names to it (Miro/Runtime/CJKFonts.swift)
fonts=${MIROE_FONTS:-/Users/Shared/miroe-lab/ref/fonts/noto-cjk}
if [[ -f "$fonts/NotoSansCJKkr-Regular.otf" ]]; then
  mkdir -p "$dest/miro/fonts"
  cp "$fonts"/NotoSansCJKkr-{Regular,Bold}.otf "$dest/miro/fonts/"
  cp "$fonts/LICENSE" "$dest/miro/licenses/noto-cjk-OFL.txt"
fi

# What Miro reads to know the engine is there, and what it was built from
cat > "$dest/miro/miroe.json" <<JSON
{
  "id": "miroe-dev-$(date +%Y%m%d)",
  "source": "$src",
  "wine": "$(cat "$src/share/wine/version" 2>/dev/null || "$src/bin/wine" --version 2>/dev/null || echo unknown)",
  "graphics": "Mullion 0f22b2c + Engine/miroe/patches/mullion (D3D10-12), $([[ -f "$src/lib/miroe/dxvk/aarch64-windows/d3d9.dll" ]] && echo "DXVK (D3D8-9), WineD3D (older)" || echo "WineD3D (D3D1-9)")",
  "dxvk": $([[ -f "$src/lib/miroe/dxvk/aarch64-windows/d3d9.dll" ]] && echo true || echo false),
  "https": $([[ -f "$lib/libgnutls.30.dylib" ]] && echo true || echo false),
  "vulkan": $([[ -f "$lib/libMoltenVK.dylib" ]] && echo true || echo false),
  "x86": "FEX (Hadron's macOS patches) as xtajit.dll / xtajit64.dll",
  "runs32Bit": $([[ -f "$src/lib/wine/aarch64-windows/xtajit.dll" && -f "$src/lib/wine/i386-windows/d3d11.dll" ]] && echo true || echo false),
  "installedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
[[ -d "$dest.old-$$" ]] && rm -rf "${dest:?}.old-$$"
echo "miroe engine installed: $dest"
