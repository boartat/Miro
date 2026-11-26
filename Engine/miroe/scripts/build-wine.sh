#!/bin/bash
# Builds ARM64 Wine (aarch64 host, arm64ec + i386 PE) for the miroe lab.
# Adapted from Hadron's scripts/build-wine.sh (BSD, Copyright (c) 2026 David Andrews), using llvm-mingw's
# clang/lld for the PE side instead of Homebrew LLVM.
set -euo pipefail
H=/Users/Shared/miroe-lab/ref/hadron
MINGW=$H/toolchains/llvm-mingw/bin
BREW=$(brew --prefix)
SRC=$H/src/wine BUILD=$H/build/wine PREFIX=$H/dist DEFS=
# --dev: KUSER_SHARED_DATA above 4GB (Hadron's WINE_HIGH_USER_SHARED_DATA) so the loader runs without the
# restricted cross-architecture entitlement; 64-bit programs only
if [[ "${1:-}" == --dev ]]; then BUILD=$H/build/wine-dev PREFIX=$H/dist-dev DEFS=-DWINE_HIGH_USER_SHARED_DATA; fi
mkdir -p "$BUILD"; cd "$BUILD"
export PATH="$MINGW:$BREW/opt/bison/bin:$PATH"
if [[ ! -f Makefile ]]; then
  PKG_CONFIG_PATH="$BREW/opt/freetype/lib/pkgconfig" \
  CPPFLAGS="-I$BREW/include $DEFS" LDFLAGS="-L$BREW/lib" CROSSCFLAGS="-g -O2 $DEFS" \
  "$SRC/configure" CC=/usr/bin/clang CXX=/usr/bin/clang++ \
    --prefix="$PREFIX" --enable-archs=arm64ec,aarch64,i386 \
    --with-mingw="$MINGW/clang" --without-x --disable-tests \
    BISON="$BREW/opt/bison/bin/bison" > configure.log 2>&1 || { tail -30 configure.log; exit 1; }
  grep -iE '^configure: (WARNING|error)' configure.log | head -20 || true
fi
make -j"$(sysctl -n hw.ncpu)" > make.log 2>&1 || { grep -E 'error' make.log | head -30; tail -20 make.log; exit 1; }
make install > install.log 2>&1
for loader in "$PREFIX/bin/wine" "$PREFIX/lib/wine/aarch64-unix/wine"; do
  [[ -f "$loader" ]] && codesign -f -s - --entitlements "$H/packaging/dev.entitlements" "$loader"
done
echo "WINE DONE: $(ls "$PREFIX/lib/wine")"
