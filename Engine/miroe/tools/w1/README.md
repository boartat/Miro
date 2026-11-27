# W1 probes: writable+executable memory under Metal (DXMT #161)

Small macOS programs, no Wine involved, that isolate why 32-bit games without `NX_COMPAT` stall under Rosetta.
Build them as x86_64 so they run under Rosetta, like an Intel Wine:

```bash
clang -arch x86_64 -O2 -o rwx-probe-x64 rwx-probe.c
clang -arch x86_64 -O2 -fobjc-arc -framework Metal -framework Foundation -o metal-rwx-x64 metal-rwx-probe.m
clang -arch x86_64 -O2 -fobjc-arc -framework Metal -framework Foundation -o metal-rwx-variants-x64 metal-rwx-variants.m
clang -arch x86_64 -O2 -fobjc-arc -framework Metal -framework Foundation -o metal-rwx-reuse-x64 metal-rwx-reuse.m
```

| Program | What it shows |
| --- | --- |
| `rwx-probe.c` | Touching writable+executable memory from the CPU costs the same as writable memory. Code run from a page without `PROT_EXEC` raises a fault that a handler can answer by adding `PROT_EXEC`, after which the code runs (the basis of lazy exec) |
| `metal-rwx-probe.m` | A no-copy Metal buffer over writable+executable memory: the first CPU read after GPU work takes about 1.2 s, whatever the size (1 to 32 MB); over writable memory it takes 0.03 ms |
| `metal-rwx-variants.m` | What avoids it in a plain process: memory without `PROT_EXEC`, dropping `PROT_EXEC` after the buffer is made, or a CPU touch of every page before the GPU uses it |
| `metal-rwx-reuse.m` | Buffers made again over reused memory, and memory reserved `PROT_NONE` and later made accessible, as Wine does |
| `metal-arm64-probe.m` | The same question natively on arm64: plain writable+executable memory is refused (W^X), and GPU writes to read+execute memory do not stall the CPU (0.004 ms). Build with `-arch arm64` |
| `w1-hook.m` | A research hook (not for shipping): wraps `newBufferWithBytesNoCopy` in a Wine process through `DYLD_INSERT_LIBRARIES`, logs the protection of every placed buffer and can drop `PROT_EXEC` or touch the pages first (`MIROE_W1_HOOK=log|noexec|touch`) |

Build the hook universal so the arm64 helper tools of a launch script can load it too (it does nothing there):

```bash
clang -arch x86_64 -arch arm64 -arch arm64e -O2 -dynamiclib -fobjc-arc -framework Metal -framework Foundation -o w1-hook.dylib w1-hook.m
```

Results and the Wine patch are in [`../../docs/research-log.md`](../../docs/research-log.md) (W1).
