// Checks the Windows pointer APIs Unity 6.3 calls at start (no window). On Wine 7.7 these are stubs
// and the process aborts; an engine that implements them prints their results.
using System;
using System.Runtime.InteropServices;

static class PointerTest
{
    [DllImport("user32")] static extern bool IsMouseInPointerEnabled();
    [DllImport("user32")] static extern bool EnableMouseInPointer(bool enable);
    [DllImport("user32")] static extern bool GetPointerType(uint pointerId, out int type);

    static int Main()
    {
        try
        {
            bool before = IsMouseInPointerEnabled();
            bool enabled = EnableMouseInPointer(true);
            bool after = IsMouseInPointerEnabled();
            int type;
            bool typeOk = GetPointerType(1, out type);
            Console.WriteLine("IsMouseInPointerEnabled before={0} EnableMouseInPointer={1} after={2} GetPointerType(1)={3} type={4}",
                              before, enabled, after, typeOk, type);
            Console.WriteLine(enabled && after ? "PASS mouse-in-pointer implemented" : "PARTIAL mouse-in-pointer not switched on");
            return 0;
        }
        catch (Exception e)
        {
            Console.WriteLine("FAIL " + e.GetType().Name + ": " + e.Message);
            return 1;
        }
    }
}
