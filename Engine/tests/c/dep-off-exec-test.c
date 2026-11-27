/*
 * miroe W1: code a 32-bit program runs from writable memory while data execution prevention is off.
 * Windows runs all of these when the executable lacks IMAGE_DLLCHARACTERISTICS_NX_COMPAT; a Wine that makes pages
 * executable lazily (on the first execute fault) must too. Build it, then clear the NX_COMPAT bit of the .exe.
 *
 *   i686-w64-mingw32-clang -O1 -o dep-off-exec-test.exe dep-off-exec-test.c
 *
 * Prints one line per case and "DEP-OFF EXEC OK" when every case returned the value its code computes.
 * With an argument (1-9) it runs only that case, so a runner can time each one out on its own.
 */
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#define CASE(n) if (!only || only == (n))

typedef int (*fn)(void);
static const unsigned char code_template[] = {0xb8, 0, 0, 0, 0, 0xc3}; /* mov eax, imm32; ret */

static int run(const char *name, unsigned char *mem, int value)
{
    memcpy(mem, code_template, sizeof(code_template));
    memcpy(mem + 1, &value, 4);
    FlushInstructionCache(GetCurrentProcess(), mem, sizeof(code_template));
    int got = ((fn)mem)();
    printf("%-44s %s (%d)\n", name, got == value ? "ok" : "WRONG", got);
    return got == value;
}

int main(int argc, char **argv)
{
    int only = argc > 1 ? atoi(argv[1]) : 0;
    DWORD flags = 0; BOOL permanent = FALSE;
    setvbuf(stdout, NULL, _IONBF, 0);
    int ok = 1;
    if (GetProcessDEPPolicy(GetCurrentProcess(), &flags, &permanent))
        printf("DEP policy flags %lu permanent %d\n", flags, permanent);

    unsigned char *va = VirtualAlloc(NULL, 65536, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    CASE(1) ok &= run("VirtualAlloc(PAGE_READWRITE)", va, 11);
    CASE(2) { if (only) run("(first run on the page)", va, 11); ok &= run("same page, rewritten after it ran", va, 12); }
    CASE(3) ok &= run("second page of the allocation", va + 4096 + 100, 13);
    unsigned char *straddle = va + 2 * 4096 - 3;                  /* instruction across a page boundary */
    CASE(4) ok &= run("instruction across a page boundary", straddle, 14);

    unsigned char *heap = HeapAlloc(GetProcessHeap(), 0, 256);
    CASE(5) ok &= run("HeapAlloc", heap, 21);

    unsigned char *big = malloc(1 << 20);
    CASE(6) ok &= run("malloc 1 MB", big + 12345, 31);

    static unsigned char data_section[64];
    CASE(7) ok &= run(".data section", data_section, 41);

    unsigned char stack[64];
    CASE(8) ok &= run("stack", stack, 51);

    CASE(9) {
    if (only) { memcpy(va, code_template, sizeof(code_template)); int v = 12; memcpy(va + 1, &v, 4); }
    DWORD old;
    VirtualProtect(va, 4096, PAGE_READONLY, &old);
    int got = ((fn)va)();                                      /* code written above is still there */
    printf("%-44s %s (%d)\n", "after VirtualProtect(PAGE_READONLY)", got == 12 ? "ok" : "WRONG", got);
    ok &= got == 12;
    }

    printf("%s\n", ok ? "DEP-OFF EXEC OK" : "DEP-OFF EXEC FAILED");
    return ok ? 0 : 1;
}
