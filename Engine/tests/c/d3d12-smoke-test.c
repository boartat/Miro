/*
 * miroe: smallest Direct3D 12 check, without a window or shaders.
 * Creates a device and a direct queue, clears a 256x256 render target to a colour, copies it to a readback buffer,
 * waits on a fence and checks every pixel. Then times 200 frames of clear + copy + fence wait.
 *
 *   aarch64-w64-mingw32-clang -O2 -Wall -o d3d12-smoke-arm64.exe d3d12-smoke-test.c -ld3d12 -ldxgi -ldxguid
 *
 * Prints "D3D12 SMOKE OK" when every pixel has the colour.
 */
#define COBJMACROS
#define WIDL_C_INLINE_WRAPPERS
#include <windows.h>
#include <d3d12.h>
#include <dxgi1_4.h>
#include <stdio.h>
#include <stdlib.h>

#define W 256
#define H 256
#define CHECK(x) do { HRESULT hr_ = (x); if (FAILED(hr_)) { printf("FAILED %s: 0x%08lx\n", #x, hr_); return 1; } } while (0)

static double now_ms(void)
{
    LARGE_INTEGER f, t; QueryPerformanceFrequency(&f); QueryPerformanceCounter(&t);
    return t.QuadPart * 1000.0 / f.QuadPart;
}

int main(void)
{
    ID3D12Device *device; ID3D12CommandQueue *queue; ID3D12CommandAllocator *alloc; ID3D12GraphicsCommandList *list;
    ID3D12DescriptorHeap *rtv_heap; ID3D12Resource *target, *readback; ID3D12Fence *fence;
    setvbuf(stdout, NULL, _IONBF, 0);

    CHECK(D3D12CreateDevice(NULL, D3D_FEATURE_LEVEL_11_0, &IID_ID3D12Device, (void **)&device));
    D3D12_FEATURE_DATA_FEATURE_LEVELS levels = {0};
    D3D_FEATURE_LEVEL asked[] = {D3D_FEATURE_LEVEL_12_2, D3D_FEATURE_LEVEL_12_1, D3D_FEATURE_LEVEL_12_0, D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0};
    levels.NumFeatureLevels = 5; levels.pFeatureLevelsRequested = asked;
    if (SUCCEEDED(ID3D12Device_CheckFeatureSupport(device, D3D12_FEATURE_FEATURE_LEVELS, &levels, sizeof(levels))))
        printf("device: max feature level 0x%x\n", levels.MaxSupportedFeatureLevel);

    D3D12_COMMAND_QUEUE_DESC qd = {.Type = D3D12_COMMAND_LIST_TYPE_DIRECT};
    CHECK(ID3D12Device_CreateCommandQueue(device, &qd, &IID_ID3D12CommandQueue, (void **)&queue));
    CHECK(ID3D12Device_CreateCommandAllocator(device, D3D12_COMMAND_LIST_TYPE_DIRECT, &IID_ID3D12CommandAllocator, (void **)&alloc));
    CHECK(ID3D12Device_CreateCommandList(device, 0, D3D12_COMMAND_LIST_TYPE_DIRECT, alloc, NULL, &IID_ID3D12GraphicsCommandList, (void **)&list));
    CHECK(ID3D12GraphicsCommandList_Close(list));

    D3D12_DESCRIPTOR_HEAP_DESC hd = {.Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV, .NumDescriptors = 1};
    CHECK(ID3D12Device_CreateDescriptorHeap(device, &hd, &IID_ID3D12DescriptorHeap, (void **)&rtv_heap));
    D3D12_CPU_DESCRIPTOR_HANDLE rtv;
    rtv = ID3D12DescriptorHeap_GetCPUDescriptorHandleForHeapStart(rtv_heap);

    D3D12_HEAP_PROPERTIES def = {.Type = D3D12_HEAP_TYPE_DEFAULT}, rb = {.Type = D3D12_HEAP_TYPE_READBACK};
    D3D12_RESOURCE_DESC td = {.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D, .Width = W, .Height = H, .DepthOrArraySize = 1,
                              .MipLevels = 1, .Format = DXGI_FORMAT_R8G8B8A8_UNORM, .SampleDesc = {1, 0},
                              .Flags = D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET};
    CHECK(ID3D12Device_CreateCommittedResource(device, &def, D3D12_HEAP_FLAG_NONE, &td, D3D12_RESOURCE_STATE_RENDER_TARGET, NULL,
                                               &IID_ID3D12Resource, (void **)&target));
    ID3D12Device_CreateRenderTargetView(device, target, NULL, rtv);

    D3D12_PLACED_SUBRESOURCE_FOOTPRINT fp; UINT64 total = 0;
    ID3D12Device_GetCopyableFootprints(device, &td, 0, 1, 0, &fp, NULL, NULL, &total);
    D3D12_RESOURCE_DESC bd = {.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER, .Width = total, .Height = 1, .DepthOrArraySize = 1,
                              .MipLevels = 1, .SampleDesc = {1, 0}, .Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR};
    CHECK(ID3D12Device_CreateCommittedResource(device, &rb, D3D12_HEAP_FLAG_NONE, &bd, D3D12_RESOURCE_STATE_COPY_DEST, NULL,
                                               &IID_ID3D12Resource, (void **)&readback));
    CHECK(ID3D12Device_CreateFence(device, 0, D3D12_FENCE_FLAG_NONE, &IID_ID3D12Fence, (void **)&fence));
    HANDLE event = CreateEventW(NULL, FALSE, FALSE, NULL);
    UINT64 value = 0;
    double worst = 0, sum = 0;

    for (int frame = 0; frame <= 200; frame++)
    {
        float colour[4] = {0.25f, 0.5f, 0.75f, 1.0f};
        double t0 = now_ms();
        CHECK(ID3D12CommandAllocator_Reset(alloc));
        CHECK(ID3D12GraphicsCommandList_Reset(list, alloc, NULL));
        ID3D12GraphicsCommandList_ClearRenderTargetView(list, rtv, colour, 0, NULL);
        D3D12_RESOURCE_BARRIER b = {.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION,
                                    .Transition = {.pResource = target, .Subresource = 0,
                                                   .StateBefore = D3D12_RESOURCE_STATE_RENDER_TARGET, .StateAfter = D3D12_RESOURCE_STATE_COPY_SOURCE}};
        ID3D12GraphicsCommandList_ResourceBarrier(list, 1, &b);
        D3D12_TEXTURE_COPY_LOCATION dst = {.pResource = readback, .Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT, .PlacedFootprint = fp};
        D3D12_TEXTURE_COPY_LOCATION src = {.pResource = target, .Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX, .SubresourceIndex = 0};
        ID3D12GraphicsCommandList_CopyTextureRegion(list, &dst, 0, 0, 0, &src, NULL);
        b.Transition.StateBefore = D3D12_RESOURCE_STATE_COPY_SOURCE; b.Transition.StateAfter = D3D12_RESOURCE_STATE_RENDER_TARGET;
        ID3D12GraphicsCommandList_ResourceBarrier(list, 1, &b);
        CHECK(ID3D12GraphicsCommandList_Close(list));
        ID3D12CommandQueue_ExecuteCommandLists(queue, 1, (ID3D12CommandList **)&list);
        CHECK(ID3D12CommandQueue_Signal(queue, fence, ++value));
        if (ID3D12Fence_GetCompletedValue(fence) < value)
        {
            CHECK(ID3D12Fence_SetEventOnCompletion(fence, value, event));
            WaitForSingleObject(event, 5000);
        }
        double ms = now_ms() - t0;
        if (frame == 0)
        {
            unsigned char *p; D3D12_RANGE range = {0, (SIZE_T)total};
            CHECK(ID3D12Resource_Map(readback, 0, &range, (void **)&p));
            int bad = 0;
            for (int y = 0; y < H; y++)
                for (int x = 0; x < W; x++)
                {
                    unsigned char *px = p + fp.Offset + y * fp.Footprint.RowPitch + x * 4;
                    if (abs(px[0] - 64) > 1 || abs(px[1] - 128) > 1 || abs(px[2] - 191) > 1 || px[3] != 255) bad++;
                }
            printf("readback: %d of %d pixels wrong, first (%u, %u, %u, %u)\n", bad, W * H, p[fp.Offset], p[fp.Offset + 1], p[fp.Offset + 2], p[fp.Offset + 3]);
            ID3D12Resource_Unmap(readback, 0, NULL);
            if (bad) { printf("D3D12 SMOKE FAILED\n"); return 1; }
            printf("first frame %.2f ms\n", ms);
        }
        else { sum += ms; if (ms > worst) worst = ms; }
    }
    printf("clear + copy + fence wait: %.3f ms/frame, worst %.3f ms (200 frames)\n", sum / 200, worst);
    printf("D3D12 SMOKE OK\n");
    return 0;
}
