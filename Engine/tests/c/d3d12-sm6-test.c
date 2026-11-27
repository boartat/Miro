/*
 * miroe: Direct3D 12 with shader model 6 (DXIL) shaders, without a window.
 * The shaders are compiled beforehand with Microsoft's DXC (sm6/build.sh) and read from a folder:
 *   1. SM 6.0 draw: vs60 + ps60, a full-screen triangle with root-constant colour, halved right of x = 128
 *   2. SM 6.0 wave operations (cs60_wave): lane count, lane index, prefix sum, wave sum
 *   3. SM 6.2 16-bit types (cs62_half): float16_t and uint16_t arithmetic
 *   4. SM 6.6 dynamic resources (cs66_heap): a UAV taken from ResourceDescriptorHeap[] by index
 * Also prints what the device reports for shader models, waves and 16-bit operations.
 *
 *   aarch64-w64-mingw32-clang -O2 -Wall -o d3d12-sm6-arm64.exe d3d12-sm6-test.c -ld3d12 -ldxgi -ldxguid
 *   d3d12-sm6-arm64.exe <folder with the .dxil files>
 *
 * Prints "D3D12 SM6 OK" when every check is exact.
 */
#define COBJMACROS
#define WIDL_C_INLINE_WRAPPERS
#include <windows.h>
#include <d3d12.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define W 256
#define H 256
#define CHECK(x) do { HRESULT hr_ = (x); if (FAILED(hr_)) { printf("FAILED line %d %s: 0x%08lx\n", __LINE__, #x, hr_); exit(1); } } while (0)

static ID3D12Device *device; static ID3D12CommandQueue *queue; static ID3D12CommandAllocator *alloc;
static ID3D12GraphicsCommandList *list; static ID3D12Fence *fence; static HANDLE event; static UINT64 fence_value;
static char folder[MAX_PATH];

typedef struct { void *code; SIZE_T size; } shader;

static shader load(const char *name)
{
    char path[MAX_PATH]; snprintf(path, sizeof(path), "%s\\%s.dxil", folder, name);
    FILE *f = fopen(path, "rb");
    if (!f) { printf("cannot open %s\n", path); exit(1); }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    shader s = {malloc(n), (SIZE_T)n};
    if (fread(s.code, 1, n, f) != (size_t)n) { printf("cannot read %s\n", path); exit(1); }
    fclose(f);
    return s;
}

static ID3D12RootSignature *root_signature(const D3D12_ROOT_PARAMETER1 *params, UINT count, D3D12_ROOT_SIGNATURE_FLAGS flags)
{
    D3D12_VERSIONED_ROOT_SIGNATURE_DESC d = {.Version = D3D_ROOT_SIGNATURE_VERSION_1_1,
                                             .Desc_1_1 = {count, params, 0, NULL, flags}};
    ID3DBlob *blob, *errors = NULL; ID3D12RootSignature *rs;
    HRESULT hr = D3D12SerializeVersionedRootSignature(&d, &blob, &errors);
    if (FAILED(hr)) { printf("root signature: 0x%08lx %s\n", hr, errors ? (char *)ID3D10Blob_GetBufferPointer(errors) : ""); exit(1); }
    CHECK(ID3D12Device_CreateRootSignature(device, 0, ID3D10Blob_GetBufferPointer(blob), ID3D10Blob_GetBufferSize(blob), &IID_ID3D12RootSignature, (void **)&rs));
    return rs;
}

static ID3D12Resource *resource(D3D12_HEAP_TYPE heap, const D3D12_RESOURCE_DESC *desc, D3D12_RESOURCE_STATES state)
{
    D3D12_HEAP_PROPERTIES hp = {.Type = heap}; ID3D12Resource *r;
    CHECK(ID3D12Device_CreateCommittedResource(device, &hp, D3D12_HEAP_FLAG_NONE, desc, state, NULL, &IID_ID3D12Resource, (void **)&r));
    return r;
}

static D3D12_RESOURCE_DESC buffer_desc(UINT64 size, D3D12_RESOURCE_FLAGS flags)
{
    D3D12_RESOURCE_DESC d = {.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER, .Width = size, .Height = 1, .DepthOrArraySize = 1,
                             .MipLevels = 1, .SampleDesc = {1, 0}, .Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR, .Flags = flags};
    return d;
}

static void barrier(ID3D12Resource *r, D3D12_RESOURCE_STATES before, D3D12_RESOURCE_STATES after)
{
    D3D12_RESOURCE_BARRIER b = {.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION,
                                .Transition = {.pResource = r, .Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES, .StateBefore = before, .StateAfter = after}};
    ID3D12GraphicsCommandList_ResourceBarrier(list, 1, &b);
}

static void begin(void) { CHECK(ID3D12CommandAllocator_Reset(alloc)); CHECK(ID3D12GraphicsCommandList_Reset(list, alloc, NULL)); }

static void submit_and_wait(void)
{
    CHECK(ID3D12GraphicsCommandList_Close(list));
    ID3D12CommandQueue_ExecuteCommandLists(queue, 1, (ID3D12CommandList **)&list);
    CHECK(ID3D12CommandQueue_Signal(queue, fence, ++fence_value));
    if (ID3D12Fence_GetCompletedValue(fence) < fence_value)
    {
        CHECK(ID3D12Fence_SetEventOnCompletion(fence, fence_value, event));
        if (WaitForSingleObject(event, 10000) != WAIT_OBJECT_0) { printf("GPU timeout\n"); exit(1); }
    }
}

static int close_to(int a, int b) { return abs(a - b) <= 1; }

/* runs a compute shader over `threads` threads into a UAV buffer of `words` uints and returns a CPU copy */
static UINT *run_compute(ID3D12PipelineState *pso, ID3D12RootSignature *rs, UINT threads, UINT words, BOOL heap_index)
{
    D3D12_RESOURCE_DESC od = buffer_desc(words * 4, D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS);
    ID3D12Resource *out = resource(D3D12_HEAP_TYPE_DEFAULT, &od, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
    D3D12_RESOURCE_DESC rd = buffer_desc(words * 4, D3D12_RESOURCE_FLAG_NONE);
    ID3D12Resource *rb = resource(D3D12_HEAP_TYPE_READBACK, &rd, D3D12_RESOURCE_STATE_COPY_DEST);
    ID3D12DescriptorHeap *heap = NULL;
    begin();
    ID3D12GraphicsCommandList_SetComputeRootSignature(list, rs);
    ID3D12GraphicsCommandList_SetPipelineState(list, pso);
    if (heap_index)
    {
        /* the UAV at index 2 of a shader-visible heap of 4, the index passed as a root constant */
        D3D12_DESCRIPTOR_HEAP_DESC hd = {.Type = D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV, .NumDescriptors = 4, .Flags = D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE};
        CHECK(ID3D12Device_CreateDescriptorHeap(device, &hd, &IID_ID3D12DescriptorHeap, (void **)&heap));
        UINT inc = ID3D12Device_GetDescriptorHandleIncrementSize(device, D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV);
        D3D12_CPU_DESCRIPTOR_HANDLE h = ID3D12DescriptorHeap_GetCPUDescriptorHandleForHeapStart(heap);
        h.ptr += 2 * inc;
        D3D12_UNORDERED_ACCESS_VIEW_DESC ud = {.Format = DXGI_FORMAT_UNKNOWN, .ViewDimension = D3D12_UAV_DIMENSION_BUFFER,
                                               .Buffer = {.NumElements = words, .StructureByteStride = 4}};
        ID3D12Device_CreateUnorderedAccessView(device, out, NULL, &ud, h);
        ID3D12GraphicsCommandList_SetDescriptorHeaps(list, 1, &heap);
        UINT index = 2;
        ID3D12GraphicsCommandList_SetComputeRoot32BitConstants(list, 0, 1, &index, 0);
    }
    else
        ID3D12GraphicsCommandList_SetComputeRootUnorderedAccessView(list, 0, ID3D12Resource_GetGPUVirtualAddress(out));
    ID3D12GraphicsCommandList_Dispatch(list, threads / 64, 1, 1);
    barrier(out, D3D12_RESOURCE_STATE_UNORDERED_ACCESS, D3D12_RESOURCE_STATE_COPY_SOURCE);
    ID3D12GraphicsCommandList_CopyResource(list, rb, out);
    submit_and_wait();
    UINT *v, *copy = malloc(words * 4);
    CHECK(ID3D12Resource_Map(rb, 0, NULL, (void **)&v));
    memcpy(copy, v, words * 4);
    ID3D12Resource_Unmap(rb, 0, NULL);
    return copy;
}

static ID3D12PipelineState *compute_pso(ID3D12RootSignature *rs, shader cs)
{
    D3D12_COMPUTE_PIPELINE_STATE_DESC d = {.pRootSignature = rs, .CS = {cs.code, cs.size}};
    ID3D12PipelineState *pso; HRESULT hr = ID3D12Device_CreateComputePipelineState(device, &d, &IID_ID3D12PipelineState, (void **)&pso);
    if (FAILED(hr)) { printf("compute pipeline: 0x%08lx\n", hr); return NULL; }
    return pso;
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc < 2) { printf("usage: %s <folder with the .dxil files>\n", argv[0]); return 2; }
    snprintf(folder, sizeof(folder), "%s", argv[1]);
    CHECK(D3D12CreateDevice(NULL, D3D_FEATURE_LEVEL_11_0, &IID_ID3D12Device, (void **)&device));

    D3D12_FEATURE_DATA_SHADER_MODEL sm = {D3D_SHADER_MODEL_6_7};
    if (FAILED(ID3D12Device_CheckFeatureSupport(device, D3D12_FEATURE_SHADER_MODEL, &sm, sizeof(sm)))) sm.HighestShaderModel = 0;
    D3D12_FEATURE_DATA_D3D12_OPTIONS1 o1 = {0}; ID3D12Device_CheckFeatureSupport(device, D3D12_FEATURE_D3D12_OPTIONS1, &o1, sizeof(o1));
    D3D12_FEATURE_DATA_D3D12_OPTIONS4 o4 = {0}; ID3D12Device_CheckFeatureSupport(device, D3D12_FEATURE_D3D12_OPTIONS4, &o4, sizeof(o4));
    D3D12_FEATURE_DATA_D3D12_OPTIONS o0 = {0}; ID3D12Device_CheckFeatureSupport(device, D3D12_FEATURE_D3D12_OPTIONS, &o0, sizeof(o0));
    printf("device: shader model %x.%x, wave ops %d (lanes %u-%u), native 16-bit %d, resource binding tier %d\n",
           sm.HighestShaderModel >> 4, sm.HighestShaderModel & 15, o1.WaveOps, o1.WaveLaneCountMin, o1.WaveLaneCountMax,
           o4.Native16BitShaderOpsSupported, o0.ResourceBindingTier);

    D3D12_COMMAND_QUEUE_DESC qd = {.Type = D3D12_COMMAND_LIST_TYPE_DIRECT};
    CHECK(ID3D12Device_CreateCommandQueue(device, &qd, &IID_ID3D12CommandQueue, (void **)&queue));
    CHECK(ID3D12Device_CreateCommandAllocator(device, D3D12_COMMAND_LIST_TYPE_DIRECT, &IID_ID3D12CommandAllocator, (void **)&alloc));
    CHECK(ID3D12Device_CreateCommandList(device, 0, D3D12_COMMAND_LIST_TYPE_DIRECT, alloc, NULL, &IID_ID3D12GraphicsCommandList, (void **)&list));
    CHECK(ID3D12GraphicsCommandList_Close(list));
    CHECK(ID3D12Device_CreateFence(device, 0, D3D12_FENCE_FLAG_NONE, &IID_ID3D12Fence, (void **)&fence));
    event = CreateEventW(NULL, FALSE, FALSE, NULL);
    int failures = 0;

    /* 1. SM 6.0 draw */
    {
        D3D12_RESOURCE_DESC td = {.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D, .Width = W, .Height = H, .DepthOrArraySize = 1, .MipLevels = 1,
                                  .Format = DXGI_FORMAT_R8G8B8A8_UNORM, .SampleDesc = {1, 0}, .Flags = D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET};
        ID3D12Resource *target = resource(D3D12_HEAP_TYPE_DEFAULT, &td, D3D12_RESOURCE_STATE_RENDER_TARGET);
        D3D12_DESCRIPTOR_HEAP_DESC rhd = {.Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV, .NumDescriptors = 1};
        ID3D12DescriptorHeap *rtv_heap; CHECK(ID3D12Device_CreateDescriptorHeap(device, &rhd, &IID_ID3D12DescriptorHeap, (void **)&rtv_heap));
        D3D12_CPU_DESCRIPTOR_HANDLE rtv = ID3D12DescriptorHeap_GetCPUDescriptorHandleForHeapStart(rtv_heap);
        ID3D12Device_CreateRenderTargetView(device, target, NULL, rtv);
        D3D12_PLACED_SUBRESOURCE_FOOTPRINT fp; UINT64 rb_size;
        ID3D12Device_GetCopyableFootprints(device, &td, 0, 1, 0, &fp, NULL, NULL, &rb_size);
        D3D12_RESOURCE_DESC rbd = buffer_desc(rb_size, D3D12_RESOURCE_FLAG_NONE);
        ID3D12Resource *readback = resource(D3D12_HEAP_TYPE_READBACK, &rbd, D3D12_RESOURCE_STATE_COPY_DEST);
        D3D12_ROOT_PARAMETER1 p = {.ParameterType = D3D12_ROOT_PARAMETER_TYPE_32BIT_CONSTANTS, .Constants = {0, 0, 4}, .ShaderVisibility = D3D12_SHADER_VISIBILITY_PIXEL};
        ID3D12RootSignature *rs = root_signature(&p, 1, D3D12_ROOT_SIGNATURE_FLAG_NONE);
        shader vs = load("vs60"), ps = load("ps60");
        D3D12_GRAPHICS_PIPELINE_STATE_DESC gd = {0};
        gd.pRootSignature = rs; gd.VS.pShaderBytecode = vs.code; gd.VS.BytecodeLength = vs.size; gd.PS.pShaderBytecode = ps.code; gd.PS.BytecodeLength = ps.size;
        gd.BlendState.RenderTarget[0].RenderTargetWriteMask = D3D12_COLOR_WRITE_ENABLE_ALL;
        gd.SampleMask = ~0u; gd.RasterizerState.FillMode = D3D12_FILL_MODE_SOLID; gd.RasterizerState.CullMode = D3D12_CULL_MODE_NONE;
        gd.RasterizerState.DepthClipEnable = TRUE; gd.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE;
        gd.NumRenderTargets = 1; gd.RTVFormats[0] = DXGI_FORMAT_R8G8B8A8_UNORM; gd.SampleDesc.Count = 1;
        ID3D12PipelineState *pso; HRESULT hr = ID3D12Device_CreateGraphicsPipelineState(device, &gd, &IID_ID3D12PipelineState, (void **)&pso);
        if (FAILED(hr)) { printf("SM 6.0 draw: pipeline 0x%08lx\n", hr); failures++; }
        else
        {
            float colour[4] = {0.8f, 0.4f, 0.2f, 1.0f}, clear[4] = {0, 0, 0, 0};
            D3D12_VIEWPORT vp = {0, 0, W, H, 0, 1}; D3D12_RECT sc = {0, 0, W, H};
            begin();
            ID3D12GraphicsCommandList_ClearRenderTargetView(list, rtv, clear, 0, NULL);
            ID3D12GraphicsCommandList_SetGraphicsRootSignature(list, rs);
            ID3D12GraphicsCommandList_SetPipelineState(list, pso);
            ID3D12GraphicsCommandList_SetGraphicsRoot32BitConstants(list, 0, 4, colour, 0);
            ID3D12GraphicsCommandList_OMSetRenderTargets(list, 1, &rtv, FALSE, NULL);
            ID3D12GraphicsCommandList_RSSetViewports(list, 1, &vp); ID3D12GraphicsCommandList_RSSetScissorRects(list, 1, &sc);
            ID3D12GraphicsCommandList_IASetPrimitiveTopology(list, D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
            ID3D12GraphicsCommandList_DrawInstanced(list, 3, 1, 0, 0);
            barrier(target, D3D12_RESOURCE_STATE_RENDER_TARGET, D3D12_RESOURCE_STATE_COPY_SOURCE);
            D3D12_TEXTURE_COPY_LOCATION dst = {.pResource = readback, .Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT, .PlacedFootprint = fp};
            D3D12_TEXTURE_COPY_LOCATION src = {.pResource = target, .Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX, .SubresourceIndex = 0};
            ID3D12GraphicsCommandList_CopyTextureRegion(list, &dst, 0, 0, 0, &src, NULL);
            submit_and_wait();
            unsigned char *px0; CHECK(ID3D12Resource_Map(readback, 0, NULL, (void **)&px0));
            int bad = 0;
            for (int y = 0; y < H; y++)
                for (int x = 0; x < W; x++)
                {
                    unsigned char *px = px0 + fp.Offset + y * fp.Footprint.RowPitch + x * 4;
                    int s = x < 128 ? 2 : 1;
                    if (!close_to(px[0], 204 * s / 2) || !close_to(px[1], 102 * s / 2) || !close_to(px[2], 51 * s / 2) || px[3] != 255) bad++;
                }
            printf("SM 6.0 draw: %d of %d pixels wrong\n", bad, W * H);
            ID3D12Resource_Unmap(readback, 0, NULL);
            failures += bad != 0;
        }
    }

    D3D12_ROOT_PARAMETER1 uav = {.ParameterType = D3D12_ROOT_PARAMETER_TYPE_UAV, .Descriptor = {0, 0, D3D12_ROOT_DESCRIPTOR_FLAG_NONE}, .ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL};
    ID3D12RootSignature *rs_uav = root_signature(&uav, 1, D3D12_ROOT_SIGNATURE_FLAG_NONE);

    /* 2. SM 6.0 wave operations, 256 threads */
    {
        ID3D12PipelineState *pso = compute_pso(rs_uav, load("cs60_wave"));
        if (!pso) failures++;
        else
        {
            const UINT n = 256; UINT *v = run_compute(pso, rs_uav, n, n * 4, FALSE);
            UINT lanes = v[0]; int bad = 0;
            for (UINT i = 0; i < n; i++)
            {
                UINT base = i / lanes * lanes, lane = i % lanes, sum = 0;
                for (UINT j = base; j < base + lanes; j++) sum += j;
                if (v[i * 4] != lanes || v[i * 4 + 1] != lane || v[i * 4 + 2] != lane || v[i * 4 + 3] != sum) bad++;
            }
            printf("SM 6.0 waves: %u lanes, %d of %u threads wrong (thread 37: index %u prefix %u sum %u)\n", lanes, bad, n, v[37 * 4 + 1], v[37 * 4 + 2], v[37 * 4 + 3]);
            failures += bad != 0 || lanes < 4;
        }
    }

    /* 3. SM 6.2 16-bit types, 256 threads */
    {
        ID3D12PipelineState *pso = compute_pso(rs_uav, load("cs62_half"));
        if (!pso) failures++;
        else
        {
            const UINT n = 256; UINT *v = run_compute(pso, rs_uav, n, n, FALSE);
            int bad = 0;
            for (UINT i = 0; i < n; i++) if (v[i] != ((2 * i) | (((i * 300) & 0xffff) << 16))) bad++;
            printf("SM 6.2 16-bit: %d of %u values wrong (v[255] = 0x%08x, want 0x%08x)\n", bad, n, v[255], (2 * 255) | (((255 * 300) & 0xffff) << 16));
            failures += bad != 0;
        }
    }

    /* 4. SM 6.6 dynamic resources, 1024 threads */
    {
        D3D12_ROOT_PARAMETER1 k = {.ParameterType = D3D12_ROOT_PARAMETER_TYPE_32BIT_CONSTANTS, .Constants = {0, 0, 1}, .ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL};
        ID3D12RootSignature *rs = root_signature(&k, 1, D3D12_ROOT_SIGNATURE_FLAG_CBV_SRV_UAV_HEAP_DIRECTLY_INDEXED);
        ID3D12PipelineState *pso = compute_pso(rs, load("cs66_heap"));
        if (!pso) failures++;
        else
        {
            const UINT n = 1024; UINT *v = run_compute(pso, rs, n, n, TRUE);
            int bad = 0;
            for (UINT i = 0; i < n; i++) if (v[i] != i * 3 + 12345) bad++;
            printf("SM 6.6 descriptor heap indexing: %d of %u values wrong (v[100] = %u)\n", bad, n, v[100]);
            failures += bad != 0;
        }
    }

    printf("%s\n", failures ? "D3D12 SM6 FAILED" : "D3D12 SM6 OK");
    return failures ? 1 : 0;
}
