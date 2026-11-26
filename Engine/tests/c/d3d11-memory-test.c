/*
 * Miro D3D11 memory test (C, no .NET): does memory come back after a burst of large WRITE_DISCARD maps?
 * No window, no swap chain. Watch the process memory from the Mac side (Engine/miroe/tools/memwatch.sh).
 * The pattern is the one of https://github.com/3Shain/dxmt/issues/260: dynamic resources larger than DXMT's
 * 32 MB staging block discarded many times in a burst, then a quiet stretch.
 *
 *   memtest.exe buffers  [burst frames] [calm frames] [idle s]   dynamic buffers, then small uploads only
 *   memtest.exe textures [burst frames] [calm frames] [idle s]   the same with 64 MB dynamic textures
 *   memtest.exe small    [frames]                                speed: 2000 small discards per frame
 *
 * "calm" keeps submitting small uploads; "idle" submits nothing at all.
 *
 * Build (llvm-mingw):  x86_64-w64-mingw32-clang -O2 -o memtest-x64.exe d3d11-memory-test.c -ld3d11
 *                      aarch64-w64-mingw32-clang -O2 -o memtest-arm64.exe d3d11-memory-test.c -ld3d11
 */
#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static LARGE_INTEGER freq, start;
static ID3D11Device *device;
static ID3D11DeviceContext *context;

static double now(void)
{
    LARGE_INTEGER t;
    QueryPerformanceCounter(&t);
    return (double)(t.QuadPart - start.QuadPart) / freq.QuadPart;
}

static void check(HRESULT hr, const char *what)
{
    if (FAILED(hr))
    {
        printf("FAIL %s: 0x%08lx\n", what, hr);
        exit(1);
    }
}

static ID3D11Buffer *make_buffer(UINT size, D3D11_USAGE usage, UINT bind, UINT cpu)
{
    D3D11_BUFFER_DESC desc = { size, usage, bind, cpu, 0, 0 };
    ID3D11Buffer *buffer = NULL;
    check(ID3D11Device_CreateBuffer(device, &desc, NULL, &buffer), "CreateBuffer");
    return buffer;
}

static ID3D11Texture2D *make_texture(UINT size, D3D11_USAGE usage, UINT bind, UINT cpu)
{
    D3D11_TEXTURE2D_DESC desc = { size, size, 1, 1, DXGI_FORMAT_R8G8B8A8_UNORM, { 1, 0 }, usage, bind, cpu, 0 };
    ID3D11Texture2D *texture = NULL;
    check(ID3D11Device_CreateTexture2D(device, &desc, NULL, &texture), "CreateTexture2D");
    return texture;
}

/* Discard-map a dynamic resource, touch it, and have the GPU read it */
static void upload(ID3D11Resource *dynamic, ID3D11Resource *target, int frame)
{
    D3D11_MAPPED_SUBRESOURCE mapped;
    check(ID3D11DeviceContext_Map(context, dynamic, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped), "Map discard");
    *(int *)mapped.pData = frame;
    ID3D11DeviceContext_Unmap(context, dynamic, 0);
    ID3D11DeviceContext_CopyResource(context, target, dynamic);
}

static ID3D11Buffer *readback, *small_target;

static void wait_for_gpu(void)
{
    D3D11_MAPPED_SUBRESOURCE mapped;
    ID3D11DeviceContext_CopyResource(context, (ID3D11Resource *)readback, (ID3D11Resource *)small_target);
    if (SUCCEEDED(ID3D11DeviceContext_Map(context, (ID3D11Resource *)readback, 0, D3D11_MAP_READ, 0, &mapped)))
        ID3D11DeviceContext_Unmap(context, (ID3D11Resource *)readback, 0);
}

/* After the quiet stretch spares may be reused (and may have been purgeable): data written through a
 * discard must still arrive. Writes a pattern into the first 1 MB, copies it on the GPU and reads it back. */
static int verify_reuse(ID3D11Resource *dynamic, ID3D11Resource *target)
{
    D3D11_BOX box = { 0, 0, 0, 1u << 20, 1, 1 };
    D3D11_MAPPED_SUBRESOURCE mapped;
    int round, i;

    for (round = 0; round < 8; round++)
    {
        check(ID3D11DeviceContext_Map(context, dynamic, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped), "Map discard");
        for (i = 0; i < (1 << 18); i++) ((unsigned *)mapped.pData)[i] = i * 2654435761u + round;
        ID3D11DeviceContext_Unmap(context, dynamic, 0);
        ID3D11DeviceContext_CopyResource(context, target, dynamic);
        ID3D11DeviceContext_CopySubresourceRegion(context, (ID3D11Resource *)readback, 0, 0, 0, 0, target, 0, &box);
        check(ID3D11DeviceContext_Map(context, (ID3D11Resource *)readback, 0, D3D11_MAP_READ, 0, &mapped), "Map read");
        for (i = 0; i < (1 << 18); i++)
            if (((unsigned *)mapped.pData)[i] != i * 2654435761u + round)
            {
                printf("FAIL verify: round %d word %d\n", round, i);
                ID3D11DeviceContext_Unmap(context, (ID3D11Resource *)readback, 0);
                return 0;
            }
        ID3D11DeviceContext_Unmap(context, (ID3D11Resource *)readback, 0);
    }
    printf("verify ok: 8 discards after the quiet stretch read back exactly\n");
    return 1;
}

static int burst_test(int textures, int burst_frames, int calm_frames, int idle_seconds)
{
    /* Larger than DXMT's 32 MB staging block, like the uploads in the issue */
    static const UINT buffer_sizes[] = { 40u << 20, 48u << 20, 64u << 20 };
    ID3D11Resource *big[3], *big_target[3];
    ID3D11Buffer *small;
    int i, frame;

    for (i = 0; i < 3; i++)
    {
        if (textures)
        {
            /* 4096x4096 RGBA8 = 64 MB each */
            big[i] = (ID3D11Resource *)make_texture(4096, D3D11_USAGE_DYNAMIC, D3D11_BIND_SHADER_RESOURCE, D3D11_CPU_ACCESS_WRITE);
            big_target[i] = (ID3D11Resource *)make_texture(4096, D3D11_USAGE_DEFAULT, D3D11_BIND_SHADER_RESOURCE, 0);
        }
        else
        {
            big[i] = (ID3D11Resource *)make_buffer(buffer_sizes[i], D3D11_USAGE_DYNAMIC, D3D11_BIND_VERTEX_BUFFER, D3D11_CPU_ACCESS_WRITE);
            big_target[i] = (ID3D11Resource *)make_buffer(buffer_sizes[i], D3D11_USAGE_DEFAULT, D3D11_BIND_VERTEX_BUFFER, 0);
        }
    }
    small = make_buffer(1u << 20, D3D11_USAGE_DYNAMIC, D3D11_BIND_VERTEX_BUFFER, D3D11_CPU_ACCESS_WRITE);

    printf("phase burst start t=%.1fs frames=%d (%s)\n", now(), burst_frames, textures ? "textures" : "buffers");
    for (frame = 0; frame < burst_frames; frame++)
    {
        for (i = 0; i < 3; i++) upload(big[i], big_target[i], frame);
        upload((ID3D11Resource *)small, (ID3D11Resource *)small_target, frame);
        ID3D11DeviceContext_Flush(context);
        if (frame % 4 == 3) wait_for_gpu();
    }
    wait_for_gpu();
    printf("phase calm start t=%.3fs frames=%d\n", now(), calm_frames);
    for (frame = 0; frame < calm_frames; frame++)
    {
        upload((ID3D11Resource *)small, (ID3D11Resource *)small_target, frame);
        ID3D11DeviceContext_Flush(context);
        wait_for_gpu();
        Sleep(5);
    }
    printf("phase idle start t=%.1fs seconds=%d\n", now(), idle_seconds);
    Sleep(idle_seconds * 1000);
    if (!textures && !verify_reuse(big[0], big_target[0])) return 1;
    printf("DONE t=%.1fs\n", now());
    return 0;
}

/* Speed of many small discards: constant-buffer style updates, the hot path for most games */
static int small_test(int frames)
{
    enum { COUNT = 64, PER_FRAME = 2000 };
    ID3D11Buffer *buffers[COUNT], *target;
    double t0;
    int i, frame;

    for (i = 0; i < COUNT; i++)
        buffers[i] = make_buffer(256, D3D11_USAGE_DYNAMIC, D3D11_BIND_CONSTANT_BUFFER, D3D11_CPU_ACCESS_WRITE);
    target = make_buffer(256, D3D11_USAGE_DEFAULT, D3D11_BIND_CONSTANT_BUFFER, 0);
    for (frame = 0; frame < 30; frame++) /* warm up */
    {
        for (i = 0; i < PER_FRAME; i++) upload((ID3D11Resource *)buffers[i % COUNT], (ID3D11Resource *)target, i);
        ID3D11DeviceContext_Flush(context);
    }
    wait_for_gpu();
    t0 = now();
    for (frame = 0; frame < frames; frame++)
    {
        for (i = 0; i < PER_FRAME; i++) upload((ID3D11Resource *)buffers[i % COUNT], (ID3D11Resource *)target, i);
        ID3D11DeviceContext_Flush(context);
        if (frame % 2 == 1) wait_for_gpu();
    }
    wait_for_gpu();
    printf("small discards: %.3f ms/frame (%d discards per frame, %d frames)\n",
           (now() - t0) * 1000.0 / frames, PER_FRAME, frames);
    printf("DONE t=%.1fs\n", now());
    return 0;
}

int main(int argc, char **argv)
{
    const char *mode = argc > 1 ? argv[1] : "buffers";
    D3D_FEATURE_LEVEL level;

    setvbuf(stdout, NULL, _IONBF, 0);
    if (FAILED(D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0, D3D11_SDK_VERSION,
                                 &device, &level, &context)))
    {
        printf("FAIL D3D11CreateDevice\n");
        return 1;
    }
    printf("device: %s, feature level 0x%x\n", GetModuleHandleA("winemetal.dll") ? "DXMT" : "other", level);
    small_target = make_buffer(1u << 20, D3D11_USAGE_DEFAULT, D3D11_BIND_VERTEX_BUFFER, 0);
    readback = make_buffer(1u << 20, D3D11_USAGE_STAGING, 0, D3D11_CPU_ACCESS_READ);
    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&start);

    if (!strcmp(mode, "small"))
        return small_test(argc > 2 ? atoi(argv[2]) : 300);
    return burst_test(!strcmp(mode, "textures"),
                      argc > 2 ? atoi(argv[2]) : 600, argc > 3 ? atoi(argv[3]) : 3000, argc > 4 ? atoi(argv[4]) : 5);
}
