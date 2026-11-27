#!/bin/zsh
# Compiles the SM 6 test shaders to DXIL with Microsoft's DXC (signed by dxil.dll), run under any working Wine.
# usage: build.sh <wine binary> <folder with dxc.exe, dxcompiler.dll, dxil.dll> <output folder>
wine=$1 dxc=$2 out=$3; here=${0:A:h}; mkdir -p $out
c() { local src=$1 profile=$2; shift 2
  "$wine" "$dxc/dxc.exe" -nologo -T $profile -E main "$@" -Fo "$out/${src:r}.dxil" "$here/$src" || echo "FAILED $src"; }
c vs60.hlsl vs_6_0
c ps60.hlsl ps_6_0
c cs60_wave.hlsl cs_6_0
c cs62_half.hlsl cs_6_2 -enable-16bit-types
c cs66_heap.hlsl cs_6_6
ls -la $out
