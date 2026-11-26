/*
 * Miro game-like D3D11 test (C, no .NET, no window): one "match" of a game with the upload pattern of
 * https://github.com/3Shain/dxmt/issues/260, without using any real game.
 *
 * Every frame draws into an off-screen 1920x1080 render target with a per-draw constant buffer discard and a
 * particle vertex buffer used as a ring (NO_OVERWRITE, DISCARD when it wraps). During "fights" the frame also
 * discards three large dynamic buffers (36/40/64 MB, above DXMT's 32 MB staging block) and, every 10 frames,
 * uploads 36 MB into a texture with UpdateSubresource (the staging path). At most 3 frames are in flight and
 * frames are capped at 120 fps, like a game with a frame limiter.
 *
 *   gametest.exe [scale]    scale multiplies every phase length (default 1: about 85 s)
 *
 * Prints "phase <name> start" lines for Engine/miroe/tools/memwatch.sh and frame time statistics per phase.
 *
 * Build (llvm-mingw): aarch64-w64-mingw32-clang -O2 -o gametest-arm64.exe d3d11-game-test.c -ld3d11 -ld3dcompiler_47
 */
#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static ID3D11Device *device;
static ID3D11DeviceContext *context;
static LARGE_INTEGER freq, start;

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

static const char shader_source[] =
    "cbuffer Draw : register(b0) { float4 offset_scale; float4 color; };\n"
    "Texture2D<float4> streamed : register(t0);\n"
    "float4 vs(float2 pos : POSITION) : SV_Position { return float4(pos * offset_scale.zw + offset_scale.xy, 0, 1); }\n"
    "float4 ps(float4 p : SV_Position) : SV_Target {\n"
    "  return color * (0.5 + 0.5 * streamed.Load(int3(uint2(p.xy) & 4095, 0)));\n"
    "}\n";

static ID3DBlob *compile(const char *entry, const char *target)
{
    ID3DBlob *code = NULL, *errors = NULL;
    HRESULT hr = D3DCompile(shader_source, sizeof(shader_source) - 1, "game", NULL, NULL, entry, target, 0, 0, &code, &errors);
    if (FAILED(hr))
    {
        printf("FAIL D3DCompile %s: %s\n", entry, errors ? (const char *)ID3D10Blob_GetBufferPointer(errors) : "?");
        exit(1);
    }
    return code;
}

static ID3D11Buffer *make_buffer(UINT size, D3D11_USAGE usage, UINT bind, UINT cpu)
{
    D3D11_BUFFER_DESC desc = { size, usage, bind, cpu, 0, 0 };
    ID3D11Buffer *buffer = NULL;
    check(ID3D11Device_CreateBuffer(device, &desc, NULL, &buffer), "CreateBuffer");
    return buffer;
}

/* Frame times of one phase */
#define MAX_FRAMES 20000
typedef struct
{
    const char *name;
    double seconds;
    int draws, fight, menu;
    int count;
    float ms[MAX_FRAMES];
} phase;

static int compare(const void *a, const void *b)
{
    float x = *(const float *)a, y = *(const float *)b;
    return (x > y) - (x < y);
}

static void report(phase *p)
{
    double sum = 0;
    int i;
    if (!p->count) return;
    for (i = 0; i < p->count; i++) sum += p->ms[i];
    qsort(p->ms, p->count, sizeof(float), compare);
    printf("stats %-8s frames %5d  avg %6.2f ms  p50 %6.2f  p95 %6.2f  p99 %6.2f  max %7.2f\n", p->name, p->count,
           sum / p->count, p->ms[p->count / 2], p->ms[p->count * 95 / 100], p->ms[p->count * 99 / 100], p->ms[p->count - 1]);
}

int main(int argc, char **argv)
{
    double scale = argc > 1 ? atof(argv[1]) : 1.0;
    static phase phases[] = {
        { "warmup", 5, 1500, 0, 0 },  { "normal1", 20, 1500, 0, 0 }, { "fight1", 10, 3000, 1, 0 },
        { "normal2", 20, 1500, 0, 0 }, { "fight2", 10, 3000, 1, 0 },  { "menu", 15, 50, 0, 1 },
    };
    enum { CB_COUNT = 64, PARTICLE_BYTES = 8u << 20, LATENCY = 3 };
    static const UINT big_sizes[] = { 36u << 20, 40u << 20, 64u << 20 };
    ID3D11Buffer *cbs[CB_COUNT], *particles, *big[3], *big_target[3];
    ID3D11Texture2D *target, *streamed;
    ID3D11RenderTargetView *rtv;
    ID3D11ShaderResourceView *srv;
    ID3D11VertexShader *vs;
    ID3D11PixelShader *ps;
    ID3D11InputLayout *layout;
    ID3D11Query *frame_done[LATENCY];
    D3D_FEATURE_LEVEL level;
    D3D11_VIEWPORT viewport = { 0, 0, 1920, 1080, 0, 1 };
    UINT particle_offset = 0, stride = 8, zero = 0;
    void *upload_data;
    ID3DBlob *vs_code, *ps_code;
    long long frame = 0;
    int p, i;

    setvbuf(stdout, NULL, _IONBF, 0);
    check(D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0, D3D11_SDK_VERSION, &device, &level, &context),
          "D3D11CreateDevice");
    printf("device: %s, feature level 0x%x\n", GetModuleHandleA("winemetal.dll") ? "DXMT" : "other", level);

    vs_code = compile("vs", "vs_5_0");
    ps_code = compile("ps", "ps_5_0");
    check(ID3D11Device_CreateVertexShader(device, ID3D10Blob_GetBufferPointer(vs_code), ID3D10Blob_GetBufferSize(vs_code), NULL, &vs), "VS");
    check(ID3D11Device_CreatePixelShader(device, ID3D10Blob_GetBufferPointer(ps_code), ID3D10Blob_GetBufferSize(ps_code), NULL, &ps), "PS");
    {
        D3D11_INPUT_ELEMENT_DESC element = { "POSITION", 0, DXGI_FORMAT_R32G32_FLOAT, 0, 0, D3D11_INPUT_PER_VERTEX_DATA, 0 };
        check(ID3D11Device_CreateInputLayout(device, &element, 1, ID3D10Blob_GetBufferPointer(vs_code), ID3D10Blob_GetBufferSize(vs_code), &layout), "layout");
    }
    {
        D3D11_TEXTURE2D_DESC desc = { 1920, 1080, 1, 1, DXGI_FORMAT_R8G8B8A8_UNORM, { 1, 0 }, D3D11_USAGE_DEFAULT, D3D11_BIND_RENDER_TARGET, 0, 0 };
        check(ID3D11Device_CreateTexture2D(device, &desc, NULL, &target), "target");
        check(ID3D11Device_CreateRenderTargetView(device, (ID3D11Resource *)target, NULL, &rtv), "RTV");
        desc.Width = desc.Height = 4096;
        desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
        check(ID3D11Device_CreateTexture2D(device, &desc, NULL, &streamed), "streamed texture");
        check(ID3D11Device_CreateShaderResourceView(device, (ID3D11Resource *)streamed, NULL, &srv), "SRV");
    }
    for (i = 0; i < CB_COUNT; i++)
        cbs[i] = make_buffer(256, D3D11_USAGE_DYNAMIC, D3D11_BIND_CONSTANT_BUFFER, D3D11_CPU_ACCESS_WRITE);
    particles = make_buffer(PARTICLE_BYTES, D3D11_USAGE_DYNAMIC, D3D11_BIND_VERTEX_BUFFER, D3D11_CPU_ACCESS_WRITE);
    for (i = 0; i < 3; i++)
    {
        big[i] = make_buffer(big_sizes[i], D3D11_USAGE_DYNAMIC, D3D11_BIND_VERTEX_BUFFER, D3D11_CPU_ACCESS_WRITE);
        big_target[i] = make_buffer(big_sizes[i], D3D11_USAGE_DEFAULT, D3D11_BIND_VERTEX_BUFFER, 0);
    }
    for (i = 0; i < LATENCY; i++)
    {
        D3D11_QUERY_DESC desc = { D3D11_QUERY_EVENT, 0 };
        check(ID3D11Device_CreateQuery(device, &desc, &frame_done[i]), "query");
    }
    upload_data = calloc(1, 3072u * 3072u * 4u); /* 36 MB, like the uploads in the issue */

    ID3D11DeviceContext_OMSetRenderTargets(context, 1, &rtv, NULL);
    ID3D11DeviceContext_RSSetViewports(context, 1, &viewport);
    ID3D11DeviceContext_IASetPrimitiveTopology(context, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    ID3D11DeviceContext_IASetInputLayout(context, layout);
    ID3D11DeviceContext_VSSetShader(context, vs, NULL, 0);
    ID3D11DeviceContext_PSSetShader(context, ps, NULL, 0);
    ID3D11DeviceContext_PSSetShaderResources(context, 0, 1, &srv);

    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&start);
    for (p = 0; p < (int)(sizeof(phases) / sizeof(phases[0])); p++)
    {
        phase *ph = &phases[p];
        double end = now() + ph->seconds * scale;
        printf("phase %s start t=%.1fs\n", ph->name, now());
        while (now() < end)
        {
            double t0 = now(), spent;
            float clear[4] = { 0.1f, 0.2f, 0.3f, 1 };
            int slot = (int)(frame % LATENCY);

            /* frame latency: wait for the frame that used this query slot */
            if (frame >= LATENCY)
                while (ID3D11DeviceContext_GetData(context, (ID3D11Asynchronous *)frame_done[slot], NULL, 0, 0) == S_FALSE)
                    Sleep(0);

            ID3D11DeviceContext_ClearRenderTargetView(context, rtv, clear);
            if (ph->fight)
            {
                D3D11_MAPPED_SUBRESOURCE mapped;
                for (i = 0; i < 3; i++)
                {
                    check(ID3D11DeviceContext_Map(context, (ID3D11Resource *)big[i], 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped), "Map big");
                    memset(mapped.pData, (int)frame, 4096);
                    ID3D11DeviceContext_Unmap(context, (ID3D11Resource *)big[i], 0);
                    ID3D11DeviceContext_CopyResource(context, (ID3D11Resource *)big_target[i], (ID3D11Resource *)big[i]);
                }
                if (frame % 10 == 0)
                {
                    D3D11_BOX box = { 0, 0, 0, 3072, 3072, 1 };
                    ID3D11DeviceContext_UpdateSubresource(context, (ID3D11Resource *)streamed, 0, &box, upload_data, 3072 * 4, 0);
                }
            }
            for (i = 0; i < ph->draws; i++)
            {
                D3D11_MAPPED_SUBRESOURCE mapped;
                float *quad;
                ID3D11Buffer *cb = cbs[i % CB_COUNT];
                D3D11_MAP map_type = D3D11_MAP_WRITE_NO_OVERWRITE;

                /* particle ring: append, discard when it wraps */
                if (particle_offset + 6 * stride > PARTICLE_BYTES)
                {
                    particle_offset = 0;
                    map_type = D3D11_MAP_WRITE_DISCARD;
                }
                check(ID3D11DeviceContext_Map(context, (ID3D11Resource *)particles, 0, map_type, 0, &mapped), "Map particles");
                quad = (float *)((char *)mapped.pData + particle_offset);
                quad[0] = 0; quad[1] = 0; quad[2] = 1; quad[3] = 0; quad[4] = 0; quad[5] = 1;
                quad[6] = 1; quad[7] = 0; quad[8] = 1; quad[9] = 1; quad[10] = 0; quad[11] = 1;
                ID3D11DeviceContext_Unmap(context, (ID3D11Resource *)particles, 0);

                check(ID3D11DeviceContext_Map(context, (ID3D11Resource *)cb, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped), "Map CB");
                ((float *)mapped.pData)[0] = (float)(i % 40) / 20 - 1;
                ((float *)mapped.pData)[1] = (float)(i / 40 % 30) / 15 - 1;
                ((float *)mapped.pData)[2] = ((float *)mapped.pData)[3] = ph->menu ? 0.2f : 0.03f;
                ((float *)mapped.pData)[4] = 1; ((float *)mapped.pData)[5] = 0.5f; ((float *)mapped.pData)[6] = 0.25f; ((float *)mapped.pData)[7] = 1;
                ID3D11DeviceContext_Unmap(context, (ID3D11Resource *)cb, 0);

                ID3D11DeviceContext_VSSetConstantBuffers(context, 0, 1, &cb);
                ID3D11DeviceContext_PSSetConstantBuffers(context, 0, 1, &cb);
                ID3D11DeviceContext_IASetVertexBuffers(context, 0, 1, &particles, &stride, &zero);
                ID3D11DeviceContext_Draw(context, 6, particle_offset / stride);
                particle_offset += 6 * stride;
            }
            ID3D11DeviceContext_End(context, (ID3D11Asynchronous *)frame_done[slot]);
            ID3D11DeviceContext_Flush(context);

            spent = (now() - t0) * 1000.0;
            if (ph->count < MAX_FRAMES) ph->ms[ph->count++] = (float)spent;
            if (spent < 1000.0 / 120) Sleep((DWORD)(1000.0 / 120 - spent)); /* frame limiter */
            frame++;
        }
    }
    printf("phase end t=%.1fs frames=%lld\n", now(), frame);
    for (p = 0; p < (int)(sizeof(phases) / sizeof(phases[0])); p++) report(&phases[p]);
    printf("DONE\n");
    return 0;
}
