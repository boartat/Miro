#!/bin/sh
#
# Builds Miro's winemac.so for the modern engine: Wine 11.21 Staging (the same source as the Gcenx
# macOS build Miro downloads) plus winemac-dxmt.patch, which lets DXMT draw into Wine windows.
#
#     Engine/winemac-dxmt/build.sh [work folder]
#
# Needs Xcode (clang), Rosetta 2 and bison 3 or newer (`brew install bison`). Only the Unix-side
# winemac.so is built, so no PE cross compiler is needed: pe-stub/clang only lets configure finish.
# Keep the work folder path short and without spaces.
#
set -eu

WINE_VERSION=11.21
WINE_SHA256=5a40f593432d81fd3a1646db503f21ce42b8894d6d80c34c3a48b886edc54e3d
STAGING_SHA256=a6174c005f549717f5329a952dcf2de0948b5faec310c2416d3cb7fad56f1645

HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${1:-/tmp/miro-winemac}
# .so.bin: under the app target Xcode would try to link a .so instead of copying it
OUT="$HERE/../../Miro/Engine/winemac-$WINE_VERSION-dxmt.so.bin"
BISON_DIR=$(brew --prefix bison 2>/dev/null || echo /opt/homebrew/opt/bison)

mkdir -p "$WORK"
cd "$WORK"

fetch() { # url file sha256
    [ -f "$2" ] || curl -fL --retry 3 -o "$2" "$1"
    echo "$3  $2" | shasum -a 256 -c -
}
fetch "https://dl.winehq.org/wine/source/11.x/wine-$WINE_VERSION.tar.xz" "wine-$WINE_VERSION.tar.xz" "$WINE_SHA256"
fetch "https://codeload.github.com/wine-staging/wine-staging/tar.gz/refs/tags/v$WINE_VERSION" \
      "wine-staging-$WINE_VERSION.tar.gz" "$STAGING_SHA256"

rm -rf "wine-$WINE_VERSION" "wine-staging-$WINE_VERSION" build
tar -xf "wine-$WINE_VERSION.tar.xz"
tar -xzf "wine-staging-$WINE_VERSION.tar.gz"
python3 "wine-staging-$WINE_VERSION/staging/patchinstall.py" DESTDIR="$WORK/wine-$WINE_VERSION" \
    --all --backend=patch --no-autoconf > staging.log
(cd "wine-$WINE_VERSION" && patch -p1 < "$HERE/winemac-dxmt.patch")

mkdir build
cd build
# The same feature switches as the Gcenx build where they matter; the rest only affect other modules
PATH="$BISON_DIR/bin:$PATH" MACOSX_DEPLOYMENT_TARGET=10.15 arch -x86_64 "../wine-$WINE_VERSION/configure" \
    --build=x86_64-apple-darwin --enable-archs=x86_64 --with-mingw="$HERE/pe-stub/clang" \
    --disable-tests --disable-winebth_sys --without-alsa --without-capi --with-coreaudio --without-cups \
    --without-dbus --without-ffmpeg --without-freetype --without-gettext --without-gettextpo --without-gphoto \
    --without-gnutls --without-gssapi --without-gstreamer --without-inotify --without-krb5 --without-netapi \
    --without-opencl --without-opengl --without-oss --without-pcap --without-pcsclite --with-pthread \
    --without-pulse --without-sane --without-sdl --without-udev --without-usb --without-v4l2 --without-va \
    --without-vulkan --without-wayland --without-x \
    CC="clang -arch x86_64" CXX="clang++ -arch x86_64" CFLAGS="-O2" > configure.log
PATH="$BISON_DIR/bin:$PATH" MACOSX_DEPLOYMENT_TARGET=10.15 make -j"$(sysctl -n hw.ncpu)" \
    dlls/winemac.drv/winemac.so > make.log

# Same install name as the stock build, ad-hoc signed
install_name_tool -id winemac.so dlls/winemac.drv/winemac.so
codesign -f -s - dlls/winemac.drv/winemac.so
nm -gU dlls/winemac.drv/winemac.so | grep -q ' _macdrv_functions$'
cp dlls/winemac.drv/winemac.so "$OUT"
shasum -a 256 "$OUT"
