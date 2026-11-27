# SM 6 test shaders

HLSL for `../d3d12-sm6-test.c`. Compile them to DXIL with Microsoft's [DXC](https://github.com/microsoft/DirectXShaderCompiler) (tested with v1.9.2609, `dxc_2026_09_29.zip`, SHA-256 `ad31b1fc8443175d204f77a611fdb3ef2ec42759bdc2f1167368de24a4a7e7f1`), with `dxil.dll` next to `dxc.exe` so the output is signed:

```bash
./build.sh <wine binary> <folder with dxc.exe, dxcompiler.dll and dxil.dll> <output folder>
```

DXC is not part of this repository; download it from Microsoft's release. The compiled `.dxil` files are not kept here either.
