// Miro Direct3D 11 smoke test.
// Draws one frame with a vertex and a pixel shader into a small window placed far off-screen, reads the
// pixels back and prints PASS or FAIL. Nothing is shown on the display.
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

static class DxTest
{
    [StructLayout(LayoutKind.Sequential)] struct DXGI_RATIONAL { public uint Num, Den; }
    [StructLayout(LayoutKind.Sequential)] struct DXGI_MODE_DESC { public uint Width, Height; public DXGI_RATIONAL Refresh; public uint Format, ScanlineOrdering, Scaling; }
    [StructLayout(LayoutKind.Sequential)] struct DXGI_SAMPLE_DESC { public uint Count, Quality; }
    [StructLayout(LayoutKind.Sequential)] struct DXGI_SWAP_CHAIN_DESC
    {
        public DXGI_MODE_DESC BufferDesc; public DXGI_SAMPLE_DESC SampleDesc; public uint BufferUsage, BufferCount;
        public IntPtr OutputWindow; public int Windowed; public uint SwapEffect, Flags;
    }
    [StructLayout(LayoutKind.Sequential)] struct D3D11_TEXTURE2D_DESC
    {
        public uint Width, Height, MipLevels, ArraySize, Format; public DXGI_SAMPLE_DESC SampleDesc;
        public uint Usage, BindFlags, CPUAccessFlags, MiscFlags;
    }
    [StructLayout(LayoutKind.Sequential)] struct D3D11_MAPPED_SUBRESOURCE { public IntPtr Data; public uint RowPitch, DepthPitch; }
    [StructLayout(LayoutKind.Sequential)] struct D3D11_VIEWPORT { public float X, Y, Width, Height, MinDepth, MaxDepth; }
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int Left, Top, Right, Bottom; }

    [DllImport("user32", CharSet = CharSet.Unicode)]
    static extern IntPtr CreateWindowExW(uint ex, string cls, string name, uint style, int x, int y, int w, int h,
                                         IntPtr parent, IntPtr menu, IntPtr instance, IntPtr param);
    [DllImport("user32")] static extern bool DestroyWindow(IntPtr hwnd);
    [DllImport("user32")] static extern bool ShowWindow(IntPtr hwnd, int cmd);
    [DllImport("user32")] static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int w, int h, uint flags);
    [DllImport("user32")] static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
    [DllImport("kernel32", CharSet = CharSet.Unicode)] static extern IntPtr GetModuleHandleW(string name);
    [DllImport("d3d11")]
    static extern int D3D11CreateDeviceAndSwapChain(IntPtr adapter, int driverType, IntPtr software, uint flags,
        IntPtr levels, uint levelCount, uint sdk, ref DXGI_SWAP_CHAIN_DESC desc, out IntPtr swapChain,
        out IntPtr device, out int level, out IntPtr context);
    [DllImport("d3dcompiler_47")]
    static extern int D3DCompile(byte[] source, IntPtr size, string name, IntPtr defines, IntPtr include,
        string entry, string target, uint flags1, uint flags2, out IntPtr code, out IntPtr errors);

    delegate int GetBufferFn(IntPtr self, uint buffer, ref Guid riid, out IntPtr surface);
    delegate int PresentFn(IntPtr self, uint sync, uint flags);
    delegate int CreateTexture2DFn(IntPtr self, ref D3D11_TEXTURE2D_DESC desc, IntPtr init, out IntPtr texture);
    delegate int CreateViewFn(IntPtr self, IntPtr resource, IntPtr desc, out IntPtr view);
    delegate int CreateShaderFn(IntPtr self, IntPtr code, IntPtr size, IntPtr linkage, out IntPtr shader);
    delegate void SetShaderFn(IntPtr self, IntPtr shader, IntPtr instances, uint count);
    delegate void DrawFn(IntPtr self, uint count, uint start);
    delegate int MapFn(IntPtr self, IntPtr resource, uint sub, uint type, uint flags, out D3D11_MAPPED_SUBRESOURCE mapped);
    delegate void UnmapFn(IntPtr self, IntPtr resource, uint sub);
    delegate void SetTopologyFn(IntPtr self, uint topology);
    delegate void SetRenderTargetsFn(IntPtr self, uint count, ref IntPtr views, IntPtr depth);
    delegate void SetViewportsFn(IntPtr self, uint count, ref D3D11_VIEWPORT viewport);
    delegate void CopyResourceFn(IntPtr self, IntPtr dst, IntPtr src);
    delegate void ClearFn(IntPtr self, IntPtr view, float[] color);
    delegate IntPtr BlobPointerFn(IntPtr self);
    delegate IntPtr BlobSizeFn(IntPtr self);
    delegate uint ReleaseFn(IntPtr self);
    delegate int ResizeBuffersFn(IntPtr self, uint count, uint width, uint height, uint format, uint flags);

    static T Method<T>(IntPtr obj, int index) where T : class
    {
        IntPtr vtable = Marshal.ReadIntPtr(obj);
        return Marshal.GetDelegateForFunctionPointer<T>(Marshal.ReadIntPtr(vtable, index * IntPtr.Size));
    }

    static void Check(int hr, string what)
    {
        if (hr < 0) throw new Exception(what + " failed: 0x" + hr.ToString("X8"));
    }

    static IntPtr Compile(string source, string entry, string target)
    {
        IntPtr code, errors;
        byte[] bytes = Encoding.ASCII.GetBytes(source);
        int hr = D3DCompile(bytes, (IntPtr)bytes.Length, "test", IntPtr.Zero, IntPtr.Zero, entry, target, 0, 0, out code, out errors);
        if (hr < 0 && errors != IntPtr.Zero)
            throw new Exception("D3DCompile " + entry + ": " + Marshal.PtrToStringAnsi(Method<BlobPointerFn>(errors, 3)(errors)));
        Check(hr, "D3DCompile " + entry);
        return code;
    }

    const string Shaders = @"
float4 vs(uint id : SV_VertexID) : SV_Position
{
    float2 p = float2((id << 1) & 2, id & 2);
    return float4(p * float2(2, -2) + float2(-1, 1), 0, 1);
}
float4 ps(float4 pos : SV_Position) : SV_Target
{
    return float4(0.2, 0.6, 0.9, 1.0);
}";

    static int Main(string[] args)
    {
        const uint W = 64, H = 64;
        const uint WS_POPUP = 0x80000000, WS_EX_TOOLWINDOW = 0x80, WS_EX_NOACTIVATE = 0x08000000;
        IntPtr hwnd = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, "STATIC", "Miro D3D11 test",
                                      WS_POPUP, -20000, -20000, (int)W, (int)H,
                                      IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
        try
        {
            RECT rect;
            GetWindowRect(hwnd, out rect);
            if (rect.Right > -1000 || rect.Bottom > -1000)
            {
                Console.WriteLine("FAIL window is not off-screen ({0},{1}), stopping", rect.Left, rect.Top);
                return 2;
            }
            ShowWindow(hwnd, 4 /* SW_SHOWNOACTIVATE */);

            var desc = new DXGI_SWAP_CHAIN_DESC
            {
                BufferDesc = new DXGI_MODE_DESC { Width = W, Height = H, Format = 87 /* B8G8R8A8_UNORM */ },
                SampleDesc = new DXGI_SAMPLE_DESC { Count = 1 },
                BufferUsage = 0x20 /* RENDER_TARGET_OUTPUT */, BufferCount = 2,
                OutputWindow = hwnd, Windowed = 1, SwapEffect = 4 /* FLIP_DISCARD */
            };
            IntPtr swapChain, device, context;
            int level;
            Check(D3D11CreateDeviceAndSwapChain(IntPtr.Zero, 1 /* HARDWARE */, IntPtr.Zero, 0, IntPtr.Zero, 0, 7, ref desc,
                                                out swapChain, out device, out level, out context), "D3D11CreateDeviceAndSwapChain");
            string backend = GetModuleHandleW("winemetal") != IntPtr.Zero ? "DXMT" : "other";
            Console.WriteLine("device ok: backend {0}, feature level 0x{1:X}", backend, level);

            Guid texture2D = new Guid("6f15aaf2-d208-4e89-9ab4-489535d34f9c");
            IntPtr backBuffer, rtv;
            Check(Method<GetBufferFn>(swapChain, 9)(swapChain, 0, ref texture2D, out backBuffer), "GetBuffer");
            Check(Method<CreateViewFn>(device, 9)(device, backBuffer, IntPtr.Zero, out rtv), "CreateRenderTargetView");

            IntPtr vsCode = Compile(Shaders, "vs", "vs_5_0"), psCode = Compile(Shaders, "ps", "ps_5_0");
            IntPtr vs, ps;
            Check(Method<CreateShaderFn>(device, 12)(device, Method<BlobPointerFn>(vsCode, 3)(vsCode), Method<BlobSizeFn>(vsCode, 4)(vsCode), IntPtr.Zero, out vs), "CreateVertexShader");
            Check(Method<CreateShaderFn>(device, 15)(device, Method<BlobPointerFn>(psCode, 3)(psCode), Method<BlobSizeFn>(psCode, 4)(psCode), IntPtr.Zero, out ps), "CreatePixelShader");

            var viewport = new D3D11_VIEWPORT { Width = W, Height = H, MaxDepth = 1 };
            Action frame = () =>
            {
                Method<SetRenderTargetsFn>(context, 33)(context, 1, ref rtv, IntPtr.Zero);
                Method<SetViewportsFn>(context, 44)(context, 1, ref viewport);
                Method<ClearFn>(context, 50)(context, rtv, new float[] { 1, 0, 0, 1 });
                Method<SetTopologyFn>(context, 24)(context, 4 /* TRIANGLELIST */);
                Method<SetShaderFn>(context, 11)(context, vs, IntPtr.Zero, 0);
                Method<SetShaderFn>(context, 9)(context, ps, IntPtr.Zero, 0);
                Method<DrawFn>(context, 13)(context, 3, 0);
            };
            frame();

            Func<uint, uint, int> wrongPixels = (width, height) =>
            {
            var stagingDesc = new D3D11_TEXTURE2D_DESC
            {
                Width = width, Height = height, MipLevels = 1, ArraySize = 1, Format = 87, SampleDesc = new DXGI_SAMPLE_DESC { Count = 1 },
                Usage = 3 /* STAGING */, CPUAccessFlags = 0x20000 /* READ */
            };
            IntPtr staging;
            Check(Method<CreateTexture2DFn>(device, 5)(device, ref stagingDesc, IntPtr.Zero, out staging), "CreateTexture2D");
            Method<CopyResourceFn>(context, 47)(context, staging, backBuffer);
            D3D11_MAPPED_SUBRESOURCE mapped;
            Check(Method<MapFn>(context, 14)(context, staging, 0, 1 /* READ */, 0, out mapped), "Map");
            int wrong = 0;
            byte b = 0, g = 0, r = 0;
            for (uint y = 0; y < height; y += 7)
                for (uint x = 0; x < width; x += 7)
                {
                    IntPtr p = mapped.Data + (int)(y * mapped.RowPitch + x * 4);
                    b = Marshal.ReadByte(p); g = Marshal.ReadByte(p, 1); r = Marshal.ReadByte(p, 2);
                    if (Math.Abs(r - 51) > 3 || Math.Abs(g - 153) > 3 || Math.Abs(b - 230) > 3) wrong++;
                }
            Method<UnmapFn>(context, 15)(context, staging, 0);
            Method<ReleaseFn>(staging, 2)(staging);
            Console.WriteLine("pixels {0}x{1}: last rgb({2},{3},{4}), wrong samples {5}", width, height, r, g, b, wrong);
            return wrong;
            };
            int bad = wrongPixels(W, H);
            for (int i = 0; i < 10; i++)
            {
                frame();
                Check(Method<PresentFn>(swapChain, 8)(swapChain, 0, 0), "Present before resize");
            }

            // Resize the window and the swap chain, then draw and check again (the view must follow the window)
            const uint W2 = 96, H2 = 80;
            SetWindowPos(hwnd, IntPtr.Zero, -20000, -20000, (int)W2, (int)H2, 0x14 /* NOZORDER | NOACTIVATE */);
            Method<SetRenderTargetsFn>(context, 33)(context, 0, ref rtv, IntPtr.Zero);
            Method<ReleaseFn>(rtv, 2)(rtv);
            Method<ReleaseFn>(backBuffer, 2)(backBuffer);
            Check(Method<ResizeBuffersFn>(swapChain, 13)(swapChain, 0, W2, H2, 0, 0), "ResizeBuffers");
            Check(Method<GetBufferFn>(swapChain, 9)(swapChain, 0, ref texture2D, out backBuffer), "GetBuffer after resize");
            Check(Method<CreateViewFn>(device, 9)(device, backBuffer, IntPtr.Zero, out rtv), "CreateRenderTargetView after resize");
            viewport.Width = W2; viewport.Height = H2;
            frame();
            bad += wrongPixels(W2, H2);

            var watch = Stopwatch.StartNew();
            int frames = 0;
            while (watch.ElapsedMilliseconds < 2000)
            {
                frame();
                Check(Method<PresentFn>(swapChain, 8)(swapChain, 0, 0), "Present");
                frames++;
            }
            Console.WriteLine("presented {0} frames in {1} ms", frames, watch.ElapsedMilliseconds);

            Console.WriteLine(bad == 0 ? "PASS" : "FAIL wrong pixels");
            return bad == 0 ? 0 : 1;
        }
        catch (Exception e)
        {
            Console.WriteLine("FAIL " + e.Message);
            return 1;
        }
        finally
        {
            DestroyWindow(hwnd);
        }
    }
}
