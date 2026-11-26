# miroe lab scripts

These build the miroe research engine in `/Users/Shared/miroe-lab` (a short path: Wine breaks on long ones). They never touch Miro's engines or C: drives.

| Script | What it does |
| --- | --- |
| `stage1.sh` | llvm-mingw (SHA-256 checked against the GitHub release), the sources pinned in `../sources.conf` with Hadron's patches, LLVM 15 for DXMT's shader compiler |
| `stage2.sh` | ARM64 Wine (aarch64 host; arm64ec, aarch64 and i386 PE), FEX, DXMT |
| `stage2-dev.sh` | The same as a "dev" engine: shared user data above 4GB, so it runs without the restricted cross-architecture entitlement (64-bit programs only) |
| `build-wine.sh` | Wine, with llvm-mingw's clang/lld for the Windows side (Hadron uses Homebrew LLVM) |
| `build-dxmt-variant.sh <name> <source>` | Clones the dev engine and builds a DXMT source tree into it, for A/B tests |
| `run.sh <log> <program>` | Runs a Windows program on the engine with every window kept off screen |

Needs: Xcode with its Metal Toolchain, Homebrew `cmake ninja meson pkg-config bison freetype`.

`stage1.sh`, `stage2*.sh` and `build-wine.sh` call or adapt [Hadron](https://github.com/Broyojo/hadron)'s build scripts, Copyright (c) 2026 David Andrews, under the license in `LICENSE.hadron`.

## The 4GB limit

Windows programs need memory below 4GB. macOS gives that to a native ARM64 process only when it is signed with `com.apple.developer.cross-architecture-support`, a restricted entitlement that must come from an Apple Developer provisioning profile. Ad-hoc signed loaders carrying it are killed. Without it, use the dev engine (64-bit only).
