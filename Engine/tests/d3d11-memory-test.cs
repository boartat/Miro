// Miro D3D11 memory test: does memory come back after a burst of large WRITE_DISCARD maps?
// No window, no swap chain. Reproduces the pattern of https://github.com/3Shain/dxmt/issues/260:
// a game that discards dynamic buffers larger than 32 MB many times in a short burst (a "teamfight"),
// then goes back to small uploads. Run it and watch the process memory from the Mac side
// (footprint / vmmap); the program prints a line when each phase starts.
//
//   memtest.exe [burst frames] [calm frames]
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

static class MemoryTest
{
    [StructLayout(LayoutKind.Sequential)] struct D3D11_BUFFER_DESC { public uint ByteWidth, Usage, BindFlags, CPUAccessFlags, MiscFlags, StructureByteStride; }
    [StructLayout(LayoutKind.Sequential)] struct D3D11_MAPPED_SUBRESOURCE { public IntPtr Data; public uint RowPitch, DepthPitch; }

    [DllImport("d3d11")]
    static extern int D3D11CreateDevice(IntPtr adapter, int driverType, IntPtr software, uint flags, IntPtr levels,
        uint levelCount, uint sdk, out IntPtr device, out int level, out IntPtr context);
    [DllImport("kernel32", CharSet = CharSet.Unicode)] static extern IntPtr GetModuleHandleW(string name);

    delegate int CreateBufferFn(IntPtr self, ref D3D11_BUFFER_DESC desc, IntPtr init, out IntPtr buffer);
    delegate int MapFn(IntPtr self, IntPtr resource, uint sub, uint type, uint flags, out D3D11_MAPPED_SUBRESOURCE mapped);
    delegate void UnmapFn(IntPtr self, IntPtr resource, uint sub);
    delegate void CopyResourceFn(IntPtr self, IntPtr dst, IntPtr src);
    delegate void FlushFn(IntPtr self);

    static T Method<T>(IntPtr obj, int index) where T : class
    {
        return Marshal.GetDelegateForFunctionPointer<T>(Marshal.ReadIntPtr(Marshal.ReadIntPtr(obj), index * IntPtr.Size));
    }

    static void Check(int hr, string what)
    {
        if (hr < 0) throw new Exception(what + " failed: 0x" + hr.ToString("X8"));
    }

    const uint USAGE_DEFAULT = 0, USAGE_DYNAMIC = 2, USAGE_STAGING = 3;
    const uint BIND_VERTEX_BUFFER = 1, CPU_WRITE = 0x10000, CPU_READ = 0x20000;
    const uint MAP_READ = 1, MAP_WRITE_DISCARD = 4;

    static int Main(string[] args)
    {
        int burstFrames = args.Length > 0 ? int.Parse(args[0]) : 600;
        int calmFrames = args.Length > 1 ? int.Parse(args[1]) : 1200;
        try
        {
            IntPtr device, context;
            int level;
            Check(D3D11CreateDevice(IntPtr.Zero, 1, IntPtr.Zero, 0, IntPtr.Zero, 0, 7, out device, out level, out context), "D3D11CreateDevice");
            Console.WriteLine("device: {0}, feature level 0x{1:X}", GetModuleHandleW("winemetal") != IntPtr.Zero ? "DXMT" : "other", level);

            var createBuffer = Method<CreateBufferFn>(device, 3);
            var map = Method<MapFn>(context, 14);
            var unmap = Method<UnmapFn>(context, 15);
            var copy = Method<CopyResourceFn>(context, 47);
            var flush = Method<FlushFn>(context, 111);

            Func<uint, uint, uint, uint, IntPtr> buffer = (size, usage, bind, cpu) =>
            {
                var desc = new D3D11_BUFFER_DESC { ByteWidth = size, Usage = usage, BindFlags = bind, CPUAccessFlags = cpu };
                IntPtr b;
                Check(createBuffer(device, ref desc, IntPtr.Zero, out b), "CreateBuffer " + size);
                return b;
            };

            // Larger than DXMT's 32 MB staging block, like the uploads in the issue
            uint[] bigSizes = { 40u << 20, 48u << 20, 64u << 20 };
            var big = new IntPtr[bigSizes.Length];
            var bigTargets = new IntPtr[bigSizes.Length];
            for (int i = 0; i < bigSizes.Length; i++)
            {
                big[i] = buffer(bigSizes[i], USAGE_DYNAMIC, BIND_VERTEX_BUFFER, CPU_WRITE);
                bigTargets[i] = buffer(bigSizes[i], USAGE_DEFAULT, BIND_VERTEX_BUFFER, 0);
            }
            IntPtr small = buffer(1u << 20, USAGE_DYNAMIC, BIND_VERTEX_BUFFER, CPU_WRITE);
            IntPtr smallTarget = buffer(1u << 20, USAGE_DEFAULT, BIND_VERTEX_BUFFER, 0);
            IntPtr readback = buffer(1u << 20, USAGE_STAGING, 0, CPU_READ);

            Action<IntPtr, IntPtr, int> upload = (dynamicBuffer, target, frame) =>
            {
                D3D11_MAPPED_SUBRESOURCE mapped;
                Check(map(context, dynamicBuffer, 0, MAP_WRITE_DISCARD, 0, out mapped), "Map discard");
                Marshal.WriteInt32(mapped.Data, frame);
                unmap(context, dynamicBuffer, 0);
                copy(context, target, dynamicBuffer);
            };
            Action waitForGpu = () =>
            {
                D3D11_MAPPED_SUBRESOURCE mapped;
                copy(context, readback, smallTarget);
                Check(map(context, readback, 0, MAP_READ, 0, out mapped), "Map read");
                unmap(context, readback, 0);
            };

            var clock = Stopwatch.StartNew();
            Console.WriteLine("phase burst start t={0:F1}s frames={1}", clock.Elapsed.TotalSeconds, burstFrames);
            for (int frame = 0; frame < burstFrames; frame++)
            {
                for (int i = 0; i < big.Length; i++) upload(big[i], bigTargets[i], frame);
                upload(small, smallTarget, frame);
                flush(context);
                if (frame % 4 == 3) waitForGpu();
            }
            waitForGpu();
            Console.WriteLine("phase calm start t={0:F1}s frames={1}", clock.Elapsed.TotalSeconds, calmFrames);
            for (int frame = 0; frame < calmFrames; frame++)
            {
                upload(small, smallTarget, frame);
                flush(context);
                waitForGpu();
                Thread.Sleep(5);
            }
            Console.WriteLine("phase idle start t={0:F1}s", clock.Elapsed.TotalSeconds);
            Thread.Sleep(5000);
            Console.WriteLine("DONE t={0:F1}s", clock.Elapsed.TotalSeconds);
            return 0;
        }
        catch (Exception e)
        {
            Console.WriteLine("FAIL " + e.Message);
            return 1;
        }
    }
}
