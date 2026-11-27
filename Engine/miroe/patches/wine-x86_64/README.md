# Wine patches for the Intel (x86_64, Rosetta) engines

| Patch | Base | What it does |
| --- | --- | --- |
| `0001` lazy exec | Wine 11.21 + Staging 11.21 | With DEP off, a page gets `PROT_EXEC` on its first execute fault instead of every readable page getting it up front. Fixes the 1.2 s stalls of 32-bit D3D10/11 programs without `NX_COMPAT` under Rosetta (DXMT #161). See `../../RESEARCH.md` (W1) |

After applying the Staging patches, run `tools/make_requests` in the Wine source: the Staging patch set changes `server/protocol.def`, and an out-of-date `server_protocol.h` makes `wineserver` fail to build.

These are LGPL-2.1-or-later like Wine, written with AI assistance and not submitted upstream (a Wine contribution needs the author's real name).
