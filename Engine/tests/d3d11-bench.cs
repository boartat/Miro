// Miro Direct3D 11 benchmark. No window, no swap chain: renders into an off-screen texture.
//   bench.exe compile <folder>   writes the shader bytecode (run once, on any engine)
//   bench.exe run <folder>       GPU test (heavy pixel shader, 1920x1080) and draw-call test (CPU overhead)
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

static class Bench
{
    [StructLayout(LayoutKind.Sequential)] struct DXGI_SAMPLE_DESC { public uint Count, Quality; }
    [StructLayout(LayoutKind.Sequential)] struct D3D11_TEXTURE2D_DESC
    {
        public uint Width, Height, MipLevels, ArraySize, Format; public DXGI_SAMPLE_DESC SampleDesc;
        public uint Usage, BindFlags, CPUAccessFlags, MiscFlags;
    }
    [StructLayout(LayoutKind.Sequential)] struct D3D11_MAPPED_SUBRESOURCE { public IntPtr Data; public uint RowPitch, DepthPitch; }
    [StructLayout(LayoutKind.Sequential)] struct D3D11_VIEWPORT { public float X, Y, Width, Height, MinDepth, MaxDepth; }

    [DllImport("d3d11")]
    static extern int D3D11CreateDevice(IntPtr adapter, int driverType, IntPtr software, uint flags, IntPtr levels,
        uint levelCount, uint sdk, out IntPtr device, out int level, out IntPtr context);
    [DllImport("d3dcompiler_47")]
    static extern int D3DCompile(byte[] source, IntPtr size, string name, IntPtr defines, IntPtr include,
        string entry, string target, uint flags1, uint flags2, out IntPtr code, out IntPtr errors);
    [DllImport("kernel32", CharSet = CharSet.Unicode)] static extern IntPtr GetModuleHandleW(string name);

    delegate int CreateTexture2DFn(IntPtr self, ref D3D11_TEXTURE2D_DESC desc, IntPtr init, out IntPtr texture);
    delegate int CreateViewFn(IntPtr self, IntPtr resource, IntPtr desc, out IntPtr view);
    delegate int CreateShaderFn(IntPtr self, byte[] code, IntPtr size, IntPtr linkage, out IntPtr shader);
    delegate void SetShaderFn(IntPtr self, IntPtr shader, IntPtr instances, uint count);
    delegate void DrawFn(IntPtr self, uint count, uint start);
    delegate int MapFn(IntPtr self, IntPtr resource, uint sub, uint type, uint flags, out D3D11_MAPPED_SUBRESOURCE mapped);
    delegate void UnmapFn(IntPtr self, IntPtr resource, uint sub);
    delegate void SetTopologyFn(IntPtr self, uint topology);
    delegate void SetRenderTargetsFn(IntPtr self, uint count, ref IntPtr views, IntPtr depth);
    delegate void SetViewportsFn(IntPtr self, uint count, ref D3D11_VIEWPORT viewport);
    delegate void CopyResourceFn(IntPtr self, IntPtr dst, IntPtr src);
    delegate IntPtr BlobPointerFn(IntPtr self);
    delegate IntPtr BlobSizeFn(IntPtr self);

    static T Method<T>(IntPtr obj, int index) where T : class
    {
        return Marshal.GetDelegateForFunctionPointer<T>(Marshal.ReadIntPtr(Marshal.ReadIntPtr(obj), index * IntPtr.Size));
    }

    static void Check(int hr, string what)
    {
        if (hr < 0) throw new Exception(what + " failed: 0x" + hr.ToString("X8"));
    }

    const string Shaders = @"
float4 vs_full(uint id : SV_VertexID) : SV_Position
{
    float2 p = float2((id << 1) & 2, id & 2);
    return float4(p * float2(2, -2) + float2(-1, 1), 0, 1);
}
float4 vs_tiny(uint id : SV_VertexID) : SV_Position
{
    float2 p = float2(id == 1, id == 2) * 0.01;
    return float4(p, 0, 1);
}
float4 ps_heavy(float4 pos : SV_Position) : SV_Target
{
    float2 uv = pos.xy / float2(1920, 1080);
    float3 c = 0;
    [loop] for (int i = 0; i < 96; i++)
    {
        float t = i * 0.37;
        c += float3(sin(uv.x * 9 + t), cos(uv.y * 7 - t), sin((uv.x + uv.y) * 5 + t * 0.5));
    }
    return float4(abs(c) / 96, 1);
}
float4 ps_light(float4 pos : SV_Position) : SV_Target { return float4(0.2, 0.6, 0.9, 1); }
float4 ps_light2(float4 pos : SV_Position) : SV_Target { return float4(0.9, 0.6, 0.2, 1); }";

    static readonly string[][] Entries = {
        new[] { "vs_full", "vs_5_0" }, new[] { "vs_tiny", "vs_5_0" },
        new[] { "ps_heavy", "ps_5_0" }, new[] { "ps_light", "ps_5_0" }, new[] { "ps_light2", "ps_5_0" } };

    static int Main(string[] args)
    {
        try
        {
            string folder = args[1];
            if (args[0] == "compile")
            {
                byte[] source = Encoding.ASCII.GetBytes(Shaders);
                foreach (var e in Entries)
                {
                    IntPtr code, errors;
                    int hr = D3DCompile(source, (IntPtr)source.Length, "bench", IntPtr.Zero, IntPtr.Zero, e[0], e[1], 0, 0, out code, out errors);
                    if (hr < 0 && errors != IntPtr.Zero) throw new Exception(Marshal.PtrToStringAnsi(Method<BlobPointerFn>(errors, 3)(errors)));
                    Check(hr, "D3DCompile " + e[0]);
                    byte[] bytes = new byte[(int)Method<BlobSizeFn>(code, 4)(code)];
                    Marshal.Copy(Method<BlobPointerFn>(code, 3)(code), bytes, 0, bytes.Length);
                    File.WriteAllBytes(Path.Combine(folder, e[0] + ".dxbc"), bytes);
                }
                Console.WriteLine("compiled");
                return 0;
            }

            IntPtr device, context;
            int level;
            Check(D3D11CreateDevice(IntPtr.Zero, 1, IntPtr.Zero, 0, IntPtr.Zero, 0, 7, out device, out level, out context), "D3D11CreateDevice");
            Console.WriteLine("device: {0}, feature level 0x{1:X}", GetModuleHandleW("winemetal") != IntPtr.Zero ? "DXMT" : "other", level);

            Func<string, bool, IntPtr> shader = (name, vertex) =>
            {
                byte[] code = File.ReadAllBytes(Path.Combine(folder, name + ".dxbc"));
                IntPtr s;
                Check(Method<CreateShaderFn>(device, vertex ? 12 : 15)(device, code, (IntPtr)code.Length, IntPtr.Zero, out s), "Create " + name);
                return s;
            };
            IntPtr vsFull = shader("vs_full", true), vsTiny = shader("vs_tiny", true);
            IntPtr psHeavy = shader("ps_heavy", false), psLight = shader("ps_light", false), psLight2 = shader("ps_light2", false);

            const uint W = 1920, H = 1080;
            var desc = new D3D11_TEXTURE2D_DESC { Width = W, Height = H, MipLevels = 1, ArraySize = 1, Format = 87,
                SampleDesc = new DXGI_SAMPLE_DESC { Count = 1 }, BindFlags = 0x20 /* RENDER_TARGET */ };
            IntPtr target, rtv, staging;
            Check(Method<CreateTexture2DFn>(device, 5)(device, ref desc, IntPtr.Zero, out target), "CreateTexture2D");
            Check(Method<CreateViewFn>(device, 9)(device, target, IntPtr.Zero, out rtv), "CreateRenderTargetView");
            desc.BindFlags = 0; desc.Usage = 3; desc.CPUAccessFlags = 0x20000;
            Check(Method<CreateTexture2DFn>(device, 5)(device, ref desc, IntPtr.Zero, out staging), "CreateTexture2D staging");

            var viewport = new D3D11_VIEWPORT { Width = W, Height = H, MaxDepth = 1 };
            Method<SetRenderTargetsFn>(context, 33)(context, 1, ref rtv, IntPtr.Zero);
            Method<SetViewportsFn>(context, 44)(context, 1, ref viewport);
            Method<SetTopologyFn>(context, 24)(context, 4);
            var setVS = Method<SetShaderFn>(context, 11);
            var setPS = Method<SetShaderFn>(context, 9);
            var draw = Method<DrawFn>(context, 13);
            Action sync = () =>
            {
                D3D11_MAPPED_SUBRESOURCE mapped;
                Method<CopyResourceFn>(context, 47)(context, staging, target);
                Check(Method<MapFn>(context, 14)(context, staging, 0, 1, 0, out mapped), "Map");
                Method<UnmapFn>(context, 15)(context, staging, 0);
            };

            Func<string, int, Action, string> measure = (name, frames, frame) =>
            {
                frame(); sync();   // warm up: first use compiles pipelines
                var cpu0 = Process.GetCurrentProcess().TotalProcessorTime;
                var watch = Stopwatch.StartNew();
                for (int i = 0; i < frames; i++) frame();
                sync();
                double wall = watch.Elapsed.TotalMilliseconds / frames;
                double cpu = (Process.GetCurrentProcess().TotalProcessorTime - cpu0).TotalMilliseconds / frames;
                return string.Format("{0}: {1:F2} ms/frame, CPU {2:F2} ms/frame", name, wall, cpu);
            };

            Console.WriteLine(measure("gpu  (96-step shader, 1920x1080)", 120, () =>
            {
                setVS(context, vsFull, IntPtr.Zero, 0);
                setPS(context, psHeavy, IntPtr.Zero, 0);
                draw(context, 3, 0);
            }));
            Console.WriteLine(measure("draw (4000 draws + 4000 shader switches)", 60, () =>
            {
                setVS(context, vsTiny, IntPtr.Zero, 0);
                for (int i = 0; i < 4000; i++)
                {
                    setPS(context, (i & 1) == 0 ? psLight : psLight2, IntPtr.Zero, 0);
                    draw(context, 3, 0);
                }
            }));
            if (args.Length > 2 && args[2] == "soak")
            {
                int seconds = args.Length > 3 ? int.Parse(args[3]) : 120;
                var total = Stopwatch.StartNew();
                var slice = Stopwatch.StartNew();
                long frames = 0, sliceFrames = 0;
                while (total.Elapsed.TotalSeconds < seconds)
                {
                    setVS(context, vsFull, IntPtr.Zero, 0); setPS(context, psHeavy, IntPtr.Zero, 0); draw(context, 3, 0);
                    setVS(context, vsTiny, IntPtr.Zero, 0);
                    for (int i = 0; i < 500; i++) { setPS(context, (i & 1) == 0 ? psLight : psLight2, IntPtr.Zero, 0); draw(context, 3, 0); }
                    if (++frames % 20 == 0) sync();
                    sliceFrames++;
                    if (slice.Elapsed.TotalSeconds >= 30)
                    {
                        var proc = Process.GetCurrentProcess();
                        Console.WriteLine("soak {0,4:F0}s: {1,6:F1} frames/s, private memory {2} MB", total.Elapsed.TotalSeconds,
                                          sliceFrames / slice.Elapsed.TotalSeconds, proc.PrivateMemorySize64 / (1024 * 1024));
                        slice.Restart(); sliceFrames = 0;
                    }
                }
            }
            Console.WriteLine("DONE");
            return 0;
        }
        catch (Exception e)
        {
            Console.WriteLine("FAIL " + e.Message);
            return 1;
        }
    }
}
