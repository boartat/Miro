#!/bin/bash
# miroe base: upstream Wine (ARM64 macOS support of MR !12716, macOS 27) built for aarch64 + arm64ec + i386 PE.
# usage: build-wine-upstream.sh   (MIROE_RECONFIGURE=1 to run configure again, e.g. after installing gnutls / molten-vk)
# Optional Homebrew libraries it picks up: gnutls (schannel, so HTTPS works) and molten-vk (Vulkan through winemac.drv).
#   CODESIGN_IDENTITY="Apple Development: <name> (<team>)" PROVISIONING_PROFILE=<path>.provisionprofile build-wine-upstream.sh
# Without both, Wine builds but macOS kills the loader at launch: the restricted entitlement
# com.apple.developer.cross-architecture-support needs a development provisioning profile (paid developer account).
# Source: a worktree of upstream Wine at the commit in ../sources.conf (WINE_UPSTREAM), at /Users/Shared/miroe-lab/src/wine-upstream.
set -euo pipefail
L=/Users/Shared/miroe-lab
MINGW=$L/ref/hadron/toolchains/llvm-mingw/bin
BREW=$(brew --prefix)
SRC=${MIROE_WINE_SRC:-$L/src/wine-upstream} BUILD=${MIROE_WINE_BUILD:-$L/build/wine-upstream} PREFIX=${MIROE_WINE_PREFIX:-$L/engines/upstream}
# miroe's own Wine patches (../patches/wine), applied once on a "miroe" branch of the worktree
PATCHES=$(cd "$(dirname "$0")/../patches/wine" && pwd)
for p in "$PATCHES"/*.patch; do
  git -C "$SRC" apply -q --reverse --check "$p" 2>/dev/null && continue   # already in the tree
  git -C "$SRC" switch -q miroe 2>/dev/null || git -C "$SRC" switch -q -c miroe
  git -C "$SRC" -c user.name=miroe -c user.email=miroe@localhost am -q "$p" || { echo "patch failed: $p"; exit 1; }
done
mkdir -p "$BUILD"; cd "$BUILD"
export PATH="$MINGW:$BREW/opt/bison/bin:$PATH"
if [[ ! -f Makefile || -n "${MIROE_RECONFIGURE:-}" ]]; then
  PKG_CONFIG_PATH="$BREW/opt/freetype/lib/pkgconfig:$BREW/opt/gnutls/lib/pkgconfig:$BREW/lib/pkgconfig" CPPFLAGS="-I$BREW/include" LDFLAGS="-L$BREW/lib" CROSSCFLAGS="-g -O2" \
  "$SRC/configure" CC=/usr/bin/clang CXX=/usr/bin/clang++ \
    --prefix="$PREFIX" --enable-archs=arm64ec,aarch64,i386 \
    --with-mingw="$MINGW/clang" --without-x --disable-tests \
    BISON="$BREW/opt/bison/bin/bison" \
    ${CODESIGN_IDENTITY:+CODESIGN_IDENTITY="$CODESIGN_IDENTITY"} ${PROVISIONING_PROFILE:+PROVISIONING_PROFILE="$PROVISIONING_PROFILE"} \
    > configure.log 2>&1 || { tail -30 configure.log; exit 1; }
  grep -iE '^configure: (WARNING|error)' configure.log | head -20 || true
  grep -E 'checking for (gnutls/gnutls.h|-lMoltenVK)' configure.log || true
fi
make -j"$(sysctl -n hw.ncpu)" > make.log 2>&1 || { grep -E 'error' make.log | head -30; tail -20 make.log; exit 1; }
make install > install.log 2>&1
echo "WINE UPSTREAM DONE: $(ls "$PREFIX/lib/wine")"
