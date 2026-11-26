/*
 * Miro D3D11 memory test (C, no .NET): does memory come back after a burst of large WRITE_DISCARD maps?
 * No window, no swap chain. Same pattern as d3d11-memory-test.cs and https://github.com/3Shain/dxmt/issues/260:
 * dynamic buffers larger than DXMT's 32 MB staging block are discarded many times in a burst, then only a
 * small buffer is used. Watch the process memory from the Mac side (Engine/miroe/tools/memwatch.sh).
 *
 *   memtest.exe [burst frames] [calm frames]
 *
 * Build (llvm-mingw):  x86_64-w64-mingw32-clang -O2 -o memtest.exe d3d11-memory-test.c -ld3d11
 *                      aarch64-w64-mingw32-clang -O2 -o memtest-arm64.exe d3d11-memory-test.c -ld3d11
 */
#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <stdio.h>
#include <stdlib.h>

static double now(LARGE_INTEGER start, LARGE_INTEGER freq)
{
    LARGE_INTEGER t;
    QueryPerformanceCounter(&t);
    return (double)(t.QuadPart - start.QuadPart) / freq.QuadPart;
}

static ID3D11Buffer *make_buffer(ID3D11Device *device, UINT size, D3D11_USAGE usage, UINT bind, UINT cpu)
{
    D3D11_BUFFER_DESC desc = { size, usage, bind, cpu, 0, 0 };
    ID3D11Buffer *buffer = NULL;
    HRESULT hr = ID3D11Device_CreateBuffer(device, &desc, NULL, &buffer);
    if (FAILED(hr))
    {
        printf("FAIL CreateBuffer %u: 0x%08lx\n", size, hr);
        exit(1);
    }
    return buffer;
}

static void upload(ID3D11DeviceContext *context, ID3D11Buffer *dynamic, ID3D11Buffer *target, int frame)
{
    D3D11_MAPPED_SUBRESOURCE mapped;
    HRESULT hr = ID3D11DeviceContext_Map(context, (ID3D11Resource *)dynamic, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped);
    if (FAILED(hr))
    {
        printf("FAIL Map discard: 0x%08lx\n", hr);
        exit(1);
    }
    *(int *)mapped.pData = frame;
    ID3D11DeviceContext_Unmap(context, (ID3D11Resource *)dynamic, 0);
    ID3D11DeviceContext_CopyResource(context, (ID3D11Resource *)target, (ID3D11Resource *)dynamic);
}

static void wait_for_gpu(ID3D11DeviceContext *context, ID3D11Buffer *readback, ID3D11Buffer *source)
{
    D3D11_MAPPED_SUBRESOURCE mapped;
    ID3D11DeviceContext_CopyResource(context, (ID3D11Resource *)readback, (ID3D11Resource *)source);
    if (SUCCEEDED(ID3D11DeviceContext_Map(context, (ID3D11Resource *)readback, 0, D3D11_MAP_READ, 0, &mapped)))
        ID3D11DeviceContext_Unmap(context, (ID3D11Resource *)readback, 0);
}

int main(int argc, char **argv)
{
    int burst_frames = argc > 1 ? atoi(argv[1]) : 600;
    int calm_frames = argc > 2 ? atoi(argv[2]) : 3000;
    /* Larger than DXMT's 32 MB staging block, like the uploads in the issue */
    static const UINT big_sizes[] = { 40u << 20, 48u << 20, 64u << 20 };
    ID3D11Buffer *big[3], *big_target[3], *small, *small_target, *readback;
    ID3D11Device *device;
    ID3D11DeviceContext *context;
    D3D_FEATURE_LEVEL level;
    LARGE_INTEGER freq, start;
    int i, frame;

    setvbuf(stdout, NULL, _IONBF, 0);
    if (FAILED(D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0, D3D11_SDK_VERSION,
                                 &device, &level, &context)))
    {
        printf("FAIL D3D11CreateDevice\n");
        return 1;
    }
    printf("device: %s, feature level 0x%x\n", GetModuleHandleA("winemetal.dll") ? "DXMT" : "other", level);

    for (i = 0; i < 3; i++)
    {
        big[i] = make_buffer(device, big_sizes[i], D3D11_USAGE_DYNAMIC, D3D11_BIND_VERTEX_BUFFER, D3D11_CPU_ACCESS_WRITE);
        big_target[i] = make_buffer(device, big_sizes[i], D3D11_USAGE_DEFAULT, D3D11_BIND_VERTEX_BUFFER, 0);
    }
    small = make_buffer(device, 1u << 20, D3D11_USAGE_DYNAMIC, D3D11_BIND_VERTEX_BUFFER, D3D11_CPU_ACCESS_WRITE);
    small_target = make_buffer(device, 1u << 20, D3D11_USAGE_DEFAULT, D3D11_BIND_VERTEX_BUFFER, 0);
    readback = make_buffer(device, 1u << 20, D3D11_USAGE_STAGING, 0, D3D11_CPU_ACCESS_READ);

    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&start);
    printf("phase burst start t=%.1fs frames=%d\n", now(start, freq), burst_frames);
    for (frame = 0; frame < burst_frames; frame++)
    {
        for (i = 0; i < 3; i++) upload(context, big[i], big_target[i], frame);
        upload(context, small, small_target, frame);
        ID3D11DeviceContext_Flush(context);
        if (frame % 4 == 3) wait_for_gpu(context, readback, small_target);
    }
    wait_for_gpu(context, readback, small_target);
    printf("phase calm start t=%.1fs frames=%d burst_ms_per_frame=%.3f\n", now(start, freq), calm_frames,
           burst_frames ? now(start, freq) * 1000.0 / burst_frames : 0.0);
    for (frame = 0; frame < calm_frames; frame++)
    {
        upload(context, small, small_target, frame);
        ID3D11DeviceContext_Flush(context);
        wait_for_gpu(context, readback, small_target);
        Sleep(5);
    }
    printf("phase idle start t=%.1fs\n", now(start, freq));
    Sleep(5000);
    printf("DONE t=%.1fs\n", now(start, freq));
    return 0;
}
