#!/bin/zsh
# Installs the miroe experimental engine (ARM64 Wine + FEX + Mullion with miroe's patches) into Miro's engine folder,
# where Miro finds it as "miroe (실험)". The engine is built in the miroe lab (Engine/miroe/scripts); this copies it
# with APFS clones (no extra disk space on the same volume) and bundles the FreeType it loads, so it needs no Homebrew.
#
# usage: Scripts/install_miroe_engine.sh [built engine folder]   (default: /Users/Shared/miroe-lab/engines/mullion-muma)
#
# For now this engine is 64-bit only: without Apple's cross-architecture entitlement (a paid developer account and a
# provisioning profile) the loader cannot reserve memory below 4 GB, so it uses Hadron's "dev" layout.
set -euo pipefail
src=${1:-/Users/Shared/miroe-lab/engines/mullion-muma}
dest="$HOME/Library/Application Support/app.miro.Miro/Libraries/Engines/miroe"
[[ -x "$src/bin/wine" && -f "$src/lib/wine/aarch64-windows/d3d12.dll" ]] || { echo "not a built miroe engine: $src"; exit 1; }

if pgrep -f "$dest/" >/dev/null; then echo "the miroe engine is running: quit its games first"; exit 1; fi
mkdir -p "${dest:h}"
if [[ -d "$dest" ]]; then mv "$dest" "$dest.old-$$"; fi
cp -c -R "$src" "$dest"

# FreeType (win32u dlopens libfreetype.6.dylib) and what it links, made relative and signed again
lib="$dest/miro/lib"; mkdir -p "$lib"
brew=$(brew --prefix 2>/dev/null || echo /opt/homebrew)
for name in freetype/lib/libfreetype.6.dylib libpng/lib/libpng16.16.dylib brotli/lib/libbrotlidec.1.dylib brotli/lib/libbrotlicommon.1.dylib; do
  cp -L "$brew/opt/$name" "$lib/"
done
for f in "$lib"/*.dylib; do
  chmod u+w "$f"
  install_name_tool -id "@loader_path/${f:t}" "$f" 2>/dev/null
  for dep in $(otool -L "$f" | awk 'NR>1 {print $1}' | grep "^$brew/"); do
    install_name_tool -change "$dep" "@loader_path/${dep:t}" "$f" 2>/dev/null
  done
  codesign -f -s - "$f" 2>/dev/null
done
if otool -L "$lib"/*.dylib | grep -q "$brew/"; then echo "a bundled library still points into Homebrew"; exit 1; fi

# What Miro reads to know the engine is there, and what it was built from
cat > "$dest/miro/miroe.json" <<JSON
{
  "id": "miroe-dev-$(date +%Y%m%d)",
  "source": "$src",
  "wine": "$(cat "$src/share/wine/version" 2>/dev/null || "$src/bin/wine" --version 2>/dev/null || echo unknown)",
  "graphics": "Mullion 0f22b2c + Engine/miroe/patches/mullion",
  "installedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
[[ -d "$dest.old-$$" ]] && rm -rf "${dest:?}.old-$$"
echo "miroe engine installed: $dest"
