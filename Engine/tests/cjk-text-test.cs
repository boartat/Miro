// Miro CJK text test: does Korean, Japanese and Chinese text draw with real glyphs, or as tofu boxes?
// No window: every string is drawn into an off-screen bitmap.
//
// For each Windows font name, two different characters of a script are drawn side by side through GDI+
// (Graphics.DrawString, what WinForms and many launchers use) and through GDI (TextRenderer). A script
// passes when both drawings have ink and differ: a missing glyph draws the same .notdef box twice.
// See https://bugs.winehq.org/show_bug.cgi?id=60881
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Windows.Forms;

static class CjkTextTest
{
    static readonly string[] Fonts =
    {
        "Microsoft Sans Serif", "MS Shell Dlg", "MS Shell Dlg 2", "Tahoma", "Segoe UI", "Arial",
        "Malgun Gothic", "Gulim", "Dotum", "Batang", "MS Gothic", "MS UI Gothic", "Meiryo", "Yu Gothic", "MS Mincho",
        "SimSun", "Microsoft YaHei", "PMingLiU", "Microsoft JhengHei",
    };
    static readonly string[][] Scripts =
    {
        new[] { "Korean", "한", "글" },   // 한 글
        new[] { "Kana", "あ", "カ" },     // あ カ
        new[] { "Kanji", "日", "本" },    // 日 本
        new[] { "Chinese", "仙", "剑" },  // 仙 剑
    };

    static int[] Draw(string font, string text, bool gdiPlus)
    {
        using (var bitmap = new Bitmap(40, 40, PixelFormat.Format32bppArgb))
        {
            using (var g = Graphics.FromImage(bitmap))
            using (var f = new Font(font, 20, GraphicsUnit.Pixel))
            {
                g.Clear(Color.White);
                if (gdiPlus)
                {
                    g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
                    g.DrawString(text, f, Brushes.Black, 2, 2);
                }
                else
                {
                    TextRenderer.DrawText(g, text, f, new Point(2, 2), Color.Black, Color.White);
                }
            }
            var pixels = new int[40 * 40];
            for (int y = 0; y < 40; y++)
                for (int x = 0; x < 40; x++)
                    pixels[y * 40 + x] = bitmap.GetPixel(x, y).R < 128 ? 1 : 0;
            return pixels;
        }
    }

    static string Check(string font, string[] script, bool gdiPlus)
    {
        int[] a = Draw(font, script[1], gdiPlus), b = Draw(font, script[2], gdiPlus);
        int inkA = 0, inkB = 0, diff = 0;
        for (int i = 0; i < a.Length; i++) { inkA += a[i]; inkB += b[i]; if (a[i] != b[i]) diff++; }
        if (inkA == 0 || inkB == 0) return "blank";
        return diff > 5 ? "ok" : "TOFU";
    }

    static int Main()
    {
        int failures = 0;
        foreach (bool gdiPlus in new[] { true, false })
        {
            Console.WriteLine(gdiPlus ? "GDI+ (Graphics.DrawString)" : "GDI (TextRenderer)");
            Console.Write("  {0,-22}", "font");
            foreach (var s in Scripts) Console.Write("{0,-9}", s[0]);
            Console.WriteLine();
            foreach (var font in Fonts)
            {
                Console.Write("  {0,-22}", font);
                foreach (var s in Scripts)
                {
                    string result;
                    try { result = Check(font, s, gdiPlus); } catch (Exception e) { result = "error:" + e.GetType().Name; }
                    if (result != "ok") failures++;
                    Console.Write("{0,-9}", result);
                }
                Console.WriteLine();
            }
        }
        Console.WriteLine(failures == 0 ? "PASS" : "FAIL " + failures + " cases");
        return failures == 0 ? 0 : 1;
    }
}
