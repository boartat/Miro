/*
 * miroe: Direct3D 12 with shaders, without a window. HLSL is compiled to DXBC (shader model 5.0) at run time.
 *   1. draw: a full-screen triangle whose pixel shader takes a colour from root constants and halves it right of x=128
 *   2. sample: a 4x4 checker texture, uploaded through a copy, read by a pixel shader through a shader-visible
 *      descriptor table and a static point sampler
 *   3. compute: 1024 threads write i*i + k into a UAV buffer (k a root constant)
 * Every pixel and element is checked, then the draw is timed over 200 frames.
 *
 *   aarch64-w64-mingw32-clang -O2 -Wall -o d3d12-shader-arm64.exe d3d12-shader-test.c -ld3d12 -ldxgi -ldxguid -ld3dcompiler_47
 *
 * Prints "D3D12 SHADERS OK" when all three are exact.
 */
#define COBJMACROS
#define WIDL_C_INLINE_WRAPPERS
#include <windows.h>
#include <d3d12.h>
#include <d3dcompiler.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define W 256
#define H 256
#define N 1024
#define CHECK(x) do { HRESULT hr_ = (x); if (FAILED(hr_)) { printf("FAILED line %d %s: 0x%08lx\n", __LINE__, #x, hr_); exit(1); } } while (0)

static const char vs_src[] =
    "float4 main(uint id : SV_VertexID, out float2 uv : TEXCOORD) : SV_Position {\n"
    "  uv = float2((id << 1) & 2, id & 2);\n"
    "  return float4(uv * float2(2, -2) + float2(-1, 1), 0, 1); }\n";
static const char ps_colour_src[] =
    "cbuffer c : register(b0) { float4 colour; };\n"
    "float4 main(float4 pos : SV_Position) : SV_Target { return pos.x < 128 ? colour : float4(colour.rgb * 0.5, colour.a); }\n";
static const char ps_sample_src[] =
    "Texture2D t : register(t0); SamplerState s : register(s0);\n"
    "float4 main(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target { return t.Sample(s, uv); }\n";
static const char cs_src[] =
    "cbuffer c : register(b0) { uint k; };\n"
    "RWStructuredBuffer<uint> o : register(u0);\n"
    "[numthreads(64, 1, 1)] void main(uint3 id : SV_DispatchThreadID) { o[id.x] = id.x * id.x + k; }\n";

static ID3D12Device *device; static ID3D12CommandQueue *queue; static ID3D12CommandAllocator *alloc;
static ID3D12GraphicsCommandList *list; static ID3D12Fence *fence; static HANDLE event; static UINT64 fence_value;

static ID3DBlob *compile(const char *src, const char *target)
{
    ID3DBlob *code = NULL, *errors = NULL;
    HRESULT hr = D3DCompile(src, strlen(src), NULL, NULL, NULL, "main", target, 0, 0, &code, &errors);
    if (FAILED(hr)) { printf("compile %s failed: %s\n", target, errors ? (char *)ID3D10Blob_GetBufferPointer(errors) : "?"); exit(1); }
    return code;
}

static ID3D12RootSignature *root_signature(const D3D12_ROOT_SIGNATURE_DESC *desc)
{
    ID3DBlob *blob, *errors = NULL; ID3D12RootSignature *rs;
    HRESULT hr = D3D12SerializeRootSignature(desc, D3D_ROOT_SIGNATURE_VERSION_1, &blob, &errors);
    if (FAILED(hr)) { printf("root signature: %s\n", errors ? (char *)ID3D10Blob_GetBufferPointer(errors) : "?"); exit(1); }
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

static double now_ms(void) { LARGE_INTEGER f, t; QueryPerformanceFrequency(&f); QueryPerformanceCounter(&t); return t.QuadPart * 1000.0 / f.QuadPart; }

static int close_to(int a, int b) { return abs(a - b) <= 1; }

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    CHECK(D3D12CreateDevice(NULL, D3D_FEATURE_LEVEL_11_0, &IID_ID3D12Device, (void **)&device));
    D3D12_COMMAND_QUEUE_DESC qd = {.Type = D3D12_COMMAND_LIST_TYPE_DIRECT};
    CHECK(ID3D12Device_CreateCommandQueue(device, &qd, &IID_ID3D12CommandQueue, (void **)&queue));
    CHECK(ID3D12Device_CreateCommandAllocator(device, D3D12_COMMAND_LIST_TYPE_DIRECT, &IID_ID3D12CommandAllocator, (void **)&alloc));
    CHECK(ID3D12Device_CreateCommandList(device, 0, D3D12_COMMAND_LIST_TYPE_DIRECT, alloc, NULL, &IID_ID3D12GraphicsCommandList, (void **)&list));
    CHECK(ID3D12GraphicsCommandList_Close(list));
    CHECK(ID3D12Device_CreateFence(device, 0, D3D12_FENCE_FLAG_NONE, &IID_ID3D12Fence, (void **)&fence));
    event = CreateEventW(NULL, FALSE, FALSE, NULL);
    int failures = 0;

    /* render target, its RTV and a readback buffer */
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
    D3D12_VIEWPORT vp = {0, 0, W, H, 0, 1}; D3D12_RECT sc = {0, 0, W, H};

    /* 1. draw with root constants */
    ID3DBlob *vs = compile(vs_src, "vs_5_0"), *ps1 = compile(ps_colour_src, "ps_5_0"), *ps2 = compile(ps_sample_src, "ps_5_0"), *cs = compile(cs_src, "cs_5_0");
    D3D12_ROOT_PARAMETER p1 = {.ParameterType = D3D12_ROOT_PARAMETER_TYPE_32BIT_CONSTANTS, .Constants = {0, 0, 4}, .ShaderVisibility = D3D12_SHADER_VISIBILITY_PIXEL};
    D3D12_ROOT_SIGNATURE_DESC rs1d = {1, &p1, 0, NULL, D3D12_ROOT_SIGNATURE_FLAG_NONE};
    ID3D12RootSignature *rs1 = root_signature(&rs1d);
    D3D12_GRAPHICS_PIPELINE_STATE_DESC gd = {0};
    gd.VS.pShaderBytecode = ID3D10Blob_GetBufferPointer(vs); gd.VS.BytecodeLength = ID3D10Blob_GetBufferSize(vs);
    gd.BlendState.RenderTarget[0].RenderTargetWriteMask = D3D12_COLOR_WRITE_ENABLE_ALL;
    gd.SampleMask = ~0u; gd.RasterizerState.FillMode = D3D12_FILL_MODE_SOLID; gd.RasterizerState.CullMode = D3D12_CULL_MODE_NONE;
    gd.RasterizerState.DepthClipEnable = TRUE; gd.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE;
    gd.NumRenderTargets = 1; gd.RTVFormats[0] = DXGI_FORMAT_R8G8B8A8_UNORM; gd.SampleDesc.Count = 1;
    gd.pRootSignature = rs1; gd.PS.pShaderBytecode = ID3D10Blob_GetBufferPointer(ps1); gd.PS.BytecodeLength = ID3D10Blob_GetBufferSize(ps1);
    ID3D12PipelineState *pso1; double t0 = now_ms();
    CHECK(ID3D12Device_CreateGraphicsPipelineState(device, &gd, &IID_ID3D12PipelineState, (void **)&pso1));
    printf("graphics pipeline created in %.1f ms\n", now_ms() - t0);
    float colour[4] = {0.8f, 0.4f, 0.2f, 1.0f};
    D3D12_TEXTURE_COPY_LOCATION dst = {.pResource = readback, .Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT, .PlacedFootprint = fp};
    D3D12_TEXTURE_COPY_LOCATION src = {.pResource = target, .Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX, .SubresourceIndex = 0};
    double sum = 0, worst = 0;
    for (int frame = 0; frame <= 200; frame++)
    {
        double f0 = now_ms();
        begin();
        float clear[4] = {0, 0, 0, 0};
        ID3D12GraphicsCommandList_ClearRenderTargetView(list, rtv, clear, 0, NULL);
        ID3D12GraphicsCommandList_SetGraphicsRootSignature(list, rs1);
        ID3D12GraphicsCommandList_SetPipelineState(list, pso1);
        ID3D12GraphicsCommandList_SetGraphicsRoot32BitConstants(list, 0, 4, colour, 0);
        ID3D12GraphicsCommandList_OMSetRenderTargets(list, 1, &rtv, FALSE, NULL);
        ID3D12GraphicsCommandList_RSSetViewports(list, 1, &vp); ID3D12GraphicsCommandList_RSSetScissorRects(list, 1, &sc);
        ID3D12GraphicsCommandList_IASetPrimitiveTopology(list, D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
        ID3D12GraphicsCommandList_DrawInstanced(list, 3, 1, 0, 0);
        if (frame == 0)
        {
            barrier(target, D3D12_RESOURCE_STATE_RENDER_TARGET, D3D12_RESOURCE_STATE_COPY_SOURCE);
            ID3D12GraphicsCommandList_CopyTextureRegion(list, &dst, 0, 0, 0, &src, NULL);
            barrier(target, D3D12_RESOURCE_STATE_COPY_SOURCE, D3D12_RESOURCE_STATE_RENDER_TARGET);
        }
        submit_and_wait();
        if (frame == 0)
        {
            unsigned char *p; CHECK(ID3D12Resource_Map(readback, 0, NULL, (void **)&p));
            int bad = 0;
            for (int y = 0; y < H; y++)
                for (int x = 0; x < W; x++)
                {
                    unsigned char *px = p + fp.Offset + y * fp.Footprint.RowPitch + x * 4;
                    int s = x < 128 ? 2 : 1; /* left: colour, right: half */
                    if (!close_to(px[0], 204 * s / 2) || !close_to(px[1], 102 * s / 2) || !close_to(px[2], 51 * s / 2) || px[3] != 255) bad++;
                }
            printf("draw: %d of %d pixels wrong (left %u,%u,%u right %u,%u,%u)\n", bad, W * H, p[fp.Offset], p[fp.Offset + 1], p[fp.Offset + 2],
                   p[fp.Offset + 200 * 4], p[fp.Offset + 200 * 4 + 1], p[fp.Offset + 200 * 4 + 2]);
            ID3D12Resource_Unmap(readback, 0, NULL);
            failures += bad != 0;
        }
        else { double ms = now_ms() - f0; sum += ms; if (ms > worst) worst = ms; }
    }
    printf("draw + fence wait: %.3f ms/frame, worst %.3f ms (200 frames)\n", sum / 200, worst);

    /* 2. sample a texture through a descriptor table */
    D3D12_RESOURCE_DESC cd = {.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D, .Width = 4, .Height = 4, .DepthOrArraySize = 1, .MipLevels = 1,
                              .Format = DXGI_FORMAT_R8G8B8A8_UNORM, .SampleDesc = {1, 0}};
    ID3D12Resource *checker = resource(D3D12_HEAP_TYPE_DEFAULT, &cd, D3D12_RESOURCE_STATE_COPY_DEST);
    D3D12_PLACED_SUBRESOURCE_FOOTPRINT cfp; UINT64 up_size;
    ID3D12Device_GetCopyableFootprints(device, &cd, 0, 1, 0, &cfp, NULL, NULL, &up_size);
    D3D12_RESOURCE_DESC ud = buffer_desc(up_size, D3D12_RESOURCE_FLAG_NONE);
    ID3D12Resource *upload = resource(D3D12_HEAP_TYPE_UPLOAD, &ud, D3D12_RESOURCE_STATE_GENERIC_READ);
    unsigned char *u; CHECK(ID3D12Resource_Map(upload, 0, NULL, (void **)&u));
    for (int y = 0; y < 4; y++)
        for (int x = 0; x < 4; x++)
        {
            unsigned char *px = u + cfp.Offset + y * cfp.Footprint.RowPitch + x * 4;
            int on = (x + y) & 1;
            px[0] = on ? 255 : 0; px[1] = on ? 0 : 255; px[2] = 0; px[3] = 255;
        }
    ID3D12Resource_Unmap(upload, 0, NULL);
    D3D12_DESCRIPTOR_HEAP_DESC shd = {.Type = D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV, .NumDescriptors = 1, .Flags = D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE};
    ID3D12DescriptorHeap *srv_heap; CHECK(ID3D12Device_CreateDescriptorHeap(device, &shd, &IID_ID3D12DescriptorHeap, (void **)&srv_heap));
    ID3D12Device_CreateShaderResourceView(device, checker, NULL, ID3D12DescriptorHeap_GetCPUDescriptorHandleForHeapStart(srv_heap));
    D3D12_DESCRIPTOR_RANGE range = {D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1, 0, 0, 0};
    D3D12_ROOT_PARAMETER p2 = {.ParameterType = D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE, .DescriptorTable = {1, &range}, .ShaderVisibility = D3D12_SHADER_VISIBILITY_PIXEL};
    D3D12_STATIC_SAMPLER_DESC ss = {.Filter = D3D12_FILTER_MIN_MAG_MIP_POINT, .AddressU = D3D12_TEXTURE_ADDRESS_MODE_CLAMP, .AddressV = D3D12_TEXTURE_ADDRESS_MODE_CLAMP,
                                    .AddressW = D3D12_TEXTURE_ADDRESS_MODE_CLAMP, .MaxLOD = D3D12_FLOAT32_MAX, .ShaderVisibility = D3D12_SHADER_VISIBILITY_PIXEL};
    D3D12_ROOT_SIGNATURE_DESC rs2d = {1, &p2, 1, &ss, D3D12_ROOT_SIGNATURE_FLAG_NONE};
    ID3D12RootSignature *rs2 = root_signature(&rs2d);
    gd.pRootSignature = rs2; gd.PS.pShaderBytecode = ID3D10Blob_GetBufferPointer(ps2); gd.PS.BytecodeLength = ID3D10Blob_GetBufferSize(ps2);
    ID3D12PipelineState *pso2; CHECK(ID3D12Device_CreateGraphicsPipelineState(device, &gd, &IID_ID3D12PipelineState, (void **)&pso2));
    begin();
    D3D12_TEXTURE_COPY_LOCATION usrc = {.pResource = upload, .Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT, .PlacedFootprint = cfp};
    D3D12_TEXTURE_COPY_LOCATION udst = {.pResource = checker, .Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX, .SubresourceIndex = 0};
    ID3D12GraphicsCommandList_CopyTextureRegion(list, &udst, 0, 0, 0, &usrc, NULL);
    barrier(checker, D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE);
    ID3D12GraphicsCommandList_SetDescriptorHeaps(list, 1, &srv_heap);
    ID3D12GraphicsCommandList_SetGraphicsRootSignature(list, rs2);
    ID3D12GraphicsCommandList_SetPipelineState(list, pso2);
    ID3D12GraphicsCommandList_SetGraphicsRootDescriptorTable(list, 0, ID3D12DescriptorHeap_GetGPUDescriptorHandleForHeapStart(srv_heap));
    ID3D12GraphicsCommandList_OMSetRenderTargets(list, 1, &rtv, FALSE, NULL);
    ID3D12GraphicsCommandList_RSSetViewports(list, 1, &vp); ID3D12GraphicsCommandList_RSSetScissorRects(list, 1, &sc);
    ID3D12GraphicsCommandList_IASetPrimitiveTopology(list, D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    ID3D12GraphicsCommandList_DrawInstanced(list, 3, 1, 0, 0);
    barrier(target, D3D12_RESOURCE_STATE_RENDER_TARGET, D3D12_RESOURCE_STATE_COPY_SOURCE);
    ID3D12GraphicsCommandList_CopyTextureRegion(list, &dst, 0, 0, 0, &src, NULL);
    barrier(target, D3D12_RESOURCE_STATE_COPY_SOURCE, D3D12_RESOURCE_STATE_RENDER_TARGET);
    submit_and_wait();
    {
        unsigned char *p; CHECK(ID3D12Resource_Map(readback, 0, NULL, (void **)&p));
        int bad = 0;
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++)
            {
                unsigned char *px = p + fp.Offset + y * fp.Footprint.RowPitch + x * 4;
                int on = ((x / 64) + (y / 64)) & 1; /* 4x4 texels over 256x256 pixels */
                if (px[0] != (on ? 255 : 0) || px[1] != (on ? 0 : 255) || px[2] != 0 || px[3] != 255) bad++;
            }
        printf("sample: %d of %d pixels wrong\n", bad, W * H);
        ID3D12Resource_Unmap(readback, 0, NULL);
        failures += bad != 0;
    }

    /* 3. compute into a UAV buffer */
    D3D12_ROOT_PARAMETER p3[2] = {
        {.ParameterType = D3D12_ROOT_PARAMETER_TYPE_32BIT_CONSTANTS, .Constants = {0, 0, 1}, .ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL},
        {.ParameterType = D3D12_ROOT_PARAMETER_TYPE_UAV, .Descriptor = {0, 0}, .ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL}};
    D3D12_ROOT_SIGNATURE_DESC rs3d = {2, p3, 0, NULL, D3D12_ROOT_SIGNATURE_FLAG_NONE};
    ID3D12RootSignature *rs3 = root_signature(&rs3d);
    D3D12_COMPUTE_PIPELINE_STATE_DESC cpd = {.pRootSignature = rs3, .CS = {ID3D10Blob_GetBufferPointer(cs), ID3D10Blob_GetBufferSize(cs)}};
    ID3D12PipelineState *pso3; CHECK(ID3D12Device_CreateComputePipelineState(device, &cpd, &IID_ID3D12PipelineState, (void **)&pso3));
    D3D12_RESOURCE_DESC od = buffer_desc(N * 4, D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS);
    ID3D12Resource *out = resource(D3D12_HEAP_TYPE_DEFAULT, &od, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
    D3D12_RESOURCE_DESC ord = buffer_desc(N * 4, D3D12_RESOURCE_FLAG_NONE);
    ID3D12Resource *out_rb = resource(D3D12_HEAP_TYPE_READBACK, &ord, D3D12_RESOURCE_STATE_COPY_DEST);
    UINT k = 7;
    begin();
    ID3D12GraphicsCommandList_SetComputeRootSignature(list, rs3);
    ID3D12GraphicsCommandList_SetPipelineState(list, pso3);
    ID3D12GraphicsCommandList_SetComputeRoot32BitConstants(list, 0, 1, &k, 0);
    ID3D12GraphicsCommandList_SetComputeRootUnorderedAccessView(list, 1, ID3D12Resource_GetGPUVirtualAddress(out));
    ID3D12GraphicsCommandList_Dispatch(list, N / 64, 1, 1);
    barrier(out, D3D12_RESOURCE_STATE_UNORDERED_ACCESS, D3D12_RESOURCE_STATE_COPY_SOURCE);
    ID3D12GraphicsCommandList_CopyResource(list, out_rb, out);
    submit_and_wait();
    {
        UINT *v; CHECK(ID3D12Resource_Map(out_rb, 0, NULL, (void **)&v));
        int bad = 0;
        for (UINT i = 0; i < N; i++) if (v[i] != i * i + k) bad++;
        printf("compute: %d of %d values wrong (v[10] = %u, want %u)\n", bad, N, v[10], 10 * 10 + k);
        ID3D12Resource_Unmap(out_rb, 0, NULL);
        failures += bad != 0;
    }

    printf("%s\n", failures ? "D3D12 SHADERS FAILED" : "D3D12 SHADERS OK");
    return failures ? 1 : 0;
}
