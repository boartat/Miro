#!/bin/bash
# miroe lab stage 1: cross compiler, pinned sources (Hadron's pins and patches), LLVM 15 for DXMT
set -euo pipefail
H=/Users/Shared/miroe-lab/ref/hadron
V=20260922 NAME=llvm-mingw-20260922-ucrt-macos-universal
mkdir -p "$H/toolchains"
if [[ ! -x "$H/toolchains/llvm-mingw/bin/arm64ec-w64-mingw32-clang" ]]; then
  echo "== llvm-mingw $V"
  want=$(gh api "repos/mstorsjo/llvm-mingw/releases/tags/$V" --jq ".assets[] | select(.name==\"$NAME.tar.xz\") | .digest" | sed 's/^sha256://')
  dl=/Users/Shared/miroe-lab/toolchains/dl; mkdir -p "$dl"
  curl -fL --retry 3 -o "$dl/$NAME.tar.xz" "https://github.com/mstorsjo/llvm-mingw/releases/download/$V/$NAME.tar.xz"
  got=$(shasum -a 256 "$dl/$NAME.tar.xz" | cut -d' ' -f1)
  [[ -n "$want" && "$want" == "$got" ]] || { echo "SHA-256 mismatch: want $want got $got"; exit 1; }
  echo "sha256 ok $got"
  tar -xJf "$dl/$NAME.tar.xz" -C "$H/toolchains"
  ln -sfn "$NAME" "$H/toolchains/llvm-mingw"
fi
"$H/toolchains/llvm-mingw/bin/arm64ec-w64-mingw32-clang" --version | head -1
echo "== sources (wine fex dxmt) at Hadron's pins, with Hadron's patches"
bash "$H/scripts/fetch.sh" wine fex dxmt
echo "== LLVM 15 for DXMT"
bash "$H/scripts/build-llvm15.sh"
echo "STAGE1 DONE"
