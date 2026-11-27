#!/bin/bash
# miroe base: upstream Wine (ARM64 macOS support of MR !12716, macOS 27) built for aarch64 + arm64ec + i386 PE.
# usage: build-wine-upstream.sh
#   CODESIGN_IDENTITY="Apple Development: <name> (<team>)" PROVISIONING_PROFILE=<path>.provisionprofile build-wine-upstream.sh
# Without both, Wine builds but macOS kills the loader at launch: the restricted entitlement
# com.apple.developer.cross-architecture-support needs a development provisioning profile (paid developer account).
# Source: a worktree of upstream Wine at the commit in ../sources.conf (WINE_UPSTREAM), at /Users/Shared/miroe-lab/src/wine-upstream.
set -euo pipefail
L=/Users/Shared/miroe-lab
MINGW=$L/ref/hadron/toolchains/llvm-mingw/bin
BREW=$(brew --prefix)
SRC=${MIROE_WINE_SRC:-$L/src/wine-upstream} BUILD=${MIROE_WINE_BUILD:-$L/build/wine-upstream} PREFIX=${MIROE_WINE_PREFIX:-$L/engines/upstream}
mkdir -p "$BUILD"; cd "$BUILD"
export PATH="$MINGW:$BREW/opt/bison/bin:$PATH"
if [[ ! -f Makefile ]]; then
  PKG_CONFIG_PATH="$BREW/opt/freetype/lib/pkgconfig" CPPFLAGS="-I$BREW/include" LDFLAGS="-L$BREW/lib" CROSSCFLAGS="-g -O2" \
  "$SRC/configure" CC=/usr/bin/clang CXX=/usr/bin/clang++ \
    --prefix="$PREFIX" --enable-archs=arm64ec,aarch64,i386 \
    --with-mingw="$MINGW/clang" --without-x --disable-tests \
    BISON="$BREW/opt/bison/bin/bison" \
    ${CODESIGN_IDENTITY:+CODESIGN_IDENTITY="$CODESIGN_IDENTITY"} ${PROVISIONING_PROFILE:+PROVISIONING_PROFILE="$PROVISIONING_PROFILE"} \
    > configure.log 2>&1 || { tail -30 configure.log; exit 1; }
  grep -iE '^configure: (WARNING|error)' configure.log | head -20 || true
fi
make -j"$(sysctl -n hw.ncpu)" > make.log 2>&1 || { grep -E 'error' make.log | head -30; tail -20 make.log; exit 1; }
make install > install.log 2>&1
echo "WINE UPSTREAM DONE: $(ls "$PREFIX/lib/wine")"
