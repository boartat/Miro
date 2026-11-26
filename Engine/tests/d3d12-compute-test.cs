// Miro Direct3D 12 smoke test. No window: creates a device, runs a compute shader that writes
// 256 values into a buffer, copies it to a readback buffer and checks every value.
//   dx12test.exe <folder with cs.dxbc>   (compile cs.dxbc with: dx12test.exe compile <folder>)
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

static class Dx12Test
{
    [StructLayout(LayoutKind.Explicit, Size = 32)] struct ROOT_PARAMETER
    {
        [FieldOffset(0)] public int Type; [FieldOffset(8)] public uint ShaderRegister; [FieldOffset(12)] public uint RegisterSpace;
        [FieldOffset(24)] public int Visibility;
    }
    [StructLayout(LayoutKind.Sequential)] struct ROOT_SIGNATURE_DESC
    {
        public uint NumParameters; public IntPtr Parameters; public uint NumStaticSamplers; public IntPtr StaticSamplers; public int Flags;
    }
    [StructLayout(LayoutKind.Explicit, Size = 56)] struct COMPUTE_PSO_DESC
    {
        [FieldOffset(0)] public IntPtr RootSignature; [FieldOffset(8)] public IntPtr CS; [FieldOffset(16)] public IntPtr CSSize;
        [FieldOffset(24)] public uint NodeMask; [FieldOffset(32)] public IntPtr Cached; [FieldOffset(40)] public IntPtr CachedSize;
        [FieldOffset(48)] public int Flags;
    }
    [StructLayout(LayoutKind.Sequential)] struct HEAP_PROPERTIES { public int Type, CPUPageProperty, MemoryPoolPreference; public uint CreationNodeMask, VisibleNodeMask; }
    [StructLayout(LayoutKind.Explicit, Size = 56)] struct RESOURCE_DESC
    {
        [FieldOffset(0)] public int Dimension; [FieldOffset(8)] public ulong Alignment; [FieldOffset(16)] public ulong Width;
        [FieldOffset(24)] public uint Height; [FieldOffset(28)] public ushort DepthOrArraySize; [FieldOffset(30)] public ushort MipLevels;
        [FieldOffset(32)] public int Format; [FieldOffset(36)] public uint SampleCount; [FieldOffset(40)] public uint SampleQuality;
        [FieldOffset(44)] public int Layout; [FieldOffset(48)] public int Flags;
    }
    [StructLayout(LayoutKind.Explicit, Size = 32)] struct RESOURCE_BARRIER
    {
        [FieldOffset(0)] public int Type; [FieldOffset(4)] public int Flags; [FieldOffset(8)] public IntPtr Resource;
        [FieldOffset(16)] public uint Subresource; [FieldOffset(20)] public int StateBefore; [FieldOffset(24)] public int StateAfter;
    }
    [StructLayout(LayoutKind.Sequential)] struct COMMAND_QUEUE_DESC { public int Type, Priority, Flags; public uint NodeMask; }

    [DllImport("d3d12")] static extern int D3D12CreateDevice(IntPtr adapter, int minLevel, ref Guid riid, out IntPtr device);
    [DllImport("d3d12")] static extern int D3D12SerializeRootSignature(ref ROOT_SIGNATURE_DESC desc, int version, out IntPtr blob, out IntPtr error);
    [DllImport("d3dcompiler_47")]
    static extern int D3DCompile(byte[] source, IntPtr size, string name, IntPtr defines, IntPtr include,
        string entry, string target, uint flags1, uint flags2, out IntPtr code, out IntPtr errors);

    delegate int CreateQueueFn(IntPtr self, ref COMMAND_QUEUE_DESC desc, ref Guid riid, out IntPtr queue);
    delegate int CreateAllocatorFn(IntPtr self, int type, ref Guid riid, out IntPtr allocator);
    delegate int CreateComputePSOFn(IntPtr self, ref COMPUTE_PSO_DESC desc, ref Guid riid, out IntPtr pso);
    delegate int CreateListFn(IntPtr self, uint nodeMask, int type, IntPtr allocator, IntPtr pso, ref Guid riid, out IntPtr list);
    delegate int CreateRootSignatureFn(IntPtr self, uint nodeMask, IntPtr blob, IntPtr size, ref Guid riid, out IntPtr rs);
    delegate int CreateCommittedFn(IntPtr self, ref HEAP_PROPERTIES heap, int heapFlags, ref RESOURCE_DESC desc, int state, IntPtr clear, ref Guid riid, out IntPtr resource);
    delegate int CreateFenceFn(IntPtr self, ulong initial, int flags, ref Guid riid, out IntPtr fence);
    delegate int CloseFn(IntPtr self);
    delegate void SetPtrFn(IntPtr self, IntPtr value);
    delegate void SetRootUavFn(IntPtr self, uint index, ulong address);
    delegate void DispatchFn(IntPtr self, uint x, uint y, uint z);
    delegate void BarrierFn(IntPtr self, uint count, ref RESOURCE_BARRIER barrier);
    delegate void CopyBufferFn(IntPtr self, IntPtr dst, ulong dstOffset, IntPtr src, ulong srcOffset, ulong bytes);
    delegate void ExecuteFn(IntPtr self, uint count, ref IntPtr lists);
    delegate int SignalFn(IntPtr self, IntPtr fence, ulong value);
    delegate ulong CompletedFn(IntPtr self);
    delegate int MapFn(IntPtr self, uint sub, IntPtr range, out IntPtr data);
    delegate ulong GpuAddressFn(IntPtr self);
    delegate IntPtr BlobPointerFn(IntPtr self);
    delegate IntPtr BlobSizeFn(IntPtr self);

    static T M<T>(IntPtr obj, int index) where T : class
    {
        return Marshal.GetDelegateForFunctionPointer<T>(Marshal.ReadIntPtr(Marshal.ReadIntPtr(obj), index * IntPtr.Size));
    }

    static void Check(int hr, string what)
    {
        if (hr < 0) throw new Exception(what + " failed: 0x" + hr.ToString("X8"));
    }

    const string Shader = @"
RWStructuredBuffer<uint> output : register(u0);
[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID) { output[id.x] = id.x * 3 + 7; }";

    static int Main(string[] args)
    {
        try
        {
            if (args.Length == 2 && args[0] == "compile")
            {
                byte[] src = Encoding.ASCII.GetBytes(Shader);
                IntPtr code, errors;
                int hr = D3DCompile(src, (IntPtr)src.Length, "cs", IntPtr.Zero, IntPtr.Zero, "main", "cs_5_0", 0, 0, out code, out errors);
                if (hr < 0 && errors != IntPtr.Zero) throw new Exception(Marshal.PtrToStringAnsi(M<BlobPointerFn>(errors, 3)(errors)));
                Check(hr, "D3DCompile");
                byte[] bytes = new byte[(int)M<BlobSizeFn>(code, 4)(code)];
                Marshal.Copy(M<BlobPointerFn>(code, 3)(code), bytes, 0, bytes.Length);
                File.WriteAllBytes(Path.Combine(args[1], "cs.dxbc"), bytes);
                Console.WriteLine("compiled");
                return 0;
            }
            byte[] cs = File.ReadAllBytes(Path.Combine(args[0], "cs.dxbc"));

            Guid iidDevice = new Guid("189819f1-1db6-4b57-be54-1821339b85f7");
            Guid iidQueue = new Guid("0ec870a6-5d7e-4c22-8cfc-5baae07616ed");
            Guid iidAllocator = new Guid("6102dee4-af59-4b09-b999-b44d73f09b24");
            Guid iidList = new Guid("5b160d0f-ac1b-4185-8ba8-b3ae42a5a455");
            Guid iidFence = new Guid("0a753dcf-c4d8-4b91-adf6-be5a60d95a76");
            Guid iidResource = new Guid("696442be-a72e-4059-bc79-5b5c98040fad");
            Guid iidRootSignature = new Guid("c54a6b66-72df-4ee8-8be5-a946a1429214");
            Guid iidPSO = new Guid("765a30f3-f624-4c6f-a828-ace948622445");

            IntPtr device;
            Check(D3D12CreateDevice(IntPtr.Zero, 0xb000, ref iidDevice, out device), "D3D12CreateDevice");
            Console.WriteLine("device ok");

            var queueDesc = new COMMAND_QUEUE_DESC { Type = 0 };
            IntPtr queue, allocator, list, fence;
            Check(M<CreateQueueFn>(device, 8)(device, ref queueDesc, ref iidQueue, out queue), "CreateCommandQueue");
            Check(M<CreateAllocatorFn>(device, 9)(device, 0, ref iidAllocator, out allocator), "CreateCommandAllocator");

            // Root signature: one root UAV at u0
            IntPtr param = Marshal.AllocHGlobal(32);
            for (int i = 0; i < 32; i += 4) Marshal.WriteInt32(param, i, 0);
            Marshal.StructureToPtr(new ROOT_PARAMETER { Type = 4 /* UAV */, ShaderRegister = 0, Visibility = 0 }, param, false);
            var rsDesc = new ROOT_SIGNATURE_DESC { NumParameters = 1, Parameters = param };
            IntPtr rsBlob, rsError, rootSignature;
            int shr = D3D12SerializeRootSignature(ref rsDesc, 1, out rsBlob, out rsError);
            if (shr < 0 && rsError != IntPtr.Zero) throw new Exception(Marshal.PtrToStringAnsi(M<BlobPointerFn>(rsError, 3)(rsError)));
            Check(shr, "D3D12SerializeRootSignature");
            Check(M<CreateRootSignatureFn>(device, 16)(device, 0, M<BlobPointerFn>(rsBlob, 3)(rsBlob), M<BlobSizeFn>(rsBlob, 4)(rsBlob), ref iidRootSignature, out rootSignature), "CreateRootSignature");

            GCHandle csHandle = GCHandle.Alloc(cs, GCHandleType.Pinned);
            var psoDesc = new COMPUTE_PSO_DESC { RootSignature = rootSignature, CS = csHandle.AddrOfPinnedObject(), CSSize = (IntPtr)cs.Length };
            IntPtr pso;
            Check(M<CreateComputePSOFn>(device, 11)(device, ref psoDesc, ref iidPSO, out pso), "CreateComputePipelineState");
            csHandle.Free();

            const int Count = 256;
            const ulong Bytes = Count * 4;
            var defaultHeap = new HEAP_PROPERTIES { Type = 1 };
            var readbackHeap = new HEAP_PROPERTIES { Type = 3 };
            var bufferDesc = new RESOURCE_DESC { Dimension = 1, Width = Bytes, Height = 1, DepthOrArraySize = 1, MipLevels = 1, SampleCount = 1, Layout = 1, Flags = 4 /* UAV */ };
            IntPtr buffer, readback;
            Check(M<CreateCommittedFn>(device, 27)(device, ref defaultHeap, 0, ref bufferDesc, 8 /* UNORDERED_ACCESS */, IntPtr.Zero, ref iidResource, out buffer), "CreateCommittedResource default");
            bufferDesc.Flags = 0;
            Check(M<CreateCommittedFn>(device, 27)(device, ref readbackHeap, 0, ref bufferDesc, 0x400 /* COPY_DEST */, IntPtr.Zero, ref iidResource, out readback), "CreateCommittedResource readback");

            Check(M<CreateListFn>(device, 12)(device, 0, 0, allocator, pso, ref iidList, out list), "CreateCommandList");
            M<SetPtrFn>(list, 29)(list, rootSignature);
            M<SetRootUavFn>(list, 41)(list, 0, M<GpuAddressFn>(buffer, 11)(buffer));
            M<DispatchFn>(list, 14)(list, Count / 64, 1, 1);
            var barrier = new RESOURCE_BARRIER { Type = 0, Resource = buffer, Subresource = 0xffffffff, StateBefore = 8, StateAfter = 0x800 /* COPY_SOURCE */ };
            M<BarrierFn>(list, 26)(list, 1, ref barrier);
            M<CopyBufferFn>(list, 15)(list, readback, 0, buffer, 0, Bytes);
            Check(M<CloseFn>(list, 9)(list), "Close");

            Check(M<CreateFenceFn>(device, 36)(device, 0, 0, ref iidFence, out fence), "CreateFence");
            M<ExecuteFn>(queue, 10)(queue, 1, ref list);
            Check(M<SignalFn>(queue, 14)(queue, fence, 1), "Signal");
            var completed = M<CompletedFn>(fence, 8);
            for (int i = 0; i < 500 && completed(fence) < 1; i++) Thread.Sleep(10);
            if (completed(fence) < 1) throw new Exception("GPU did not finish within 5 s");

            IntPtr data;
            Check(M<MapFn>(readback, 8)(readback, 0, IntPtr.Zero, out data), "Map");
            int wrong = 0;
            for (int i = 0; i < Count; i++) if ((uint)Marshal.ReadInt32(data, i * 4) != (uint)(i * 3 + 7)) wrong++;
            Console.WriteLine("compute: {0} values, wrong {1}, sample [0]={2} [255]={3}", Count, wrong,
                              Marshal.ReadInt32(data, 0), Marshal.ReadInt32(data, 255 * 4));
            Console.WriteLine(wrong == 0 ? "PASS" : "FAIL wrong values");
            return wrong == 0 ? 0 : 1;
        }
        catch (Exception e)
        {
            Console.WriteLine("FAIL " + e.Message);
            return 1;
        }
    }
}
