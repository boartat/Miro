#!/usr/bin/env python3
"""Writes a .reg file that maps Windows Korean, Japanese and Chinese font names to fonts macOS already has.

    cjk-fonts.py <out.reg>
    WINEPREFIX=<C: drive> wine regedit /S <out.reg>

Without this a fresh C: drive draws CJK text as tofu boxes (https://bugs.winehq.org/show_bug.cgi?id=60881):
Wine links its UI fonts (Tahoma, Microsoft Sans Serif ...) to Gulim, MS UI Gothic, SimSun and PMingLiU,
which a Mac doesn't have. winetricks' fakekorean/fakejapanese fix it by downloading Source Han Sans
(about 120 MB); this uses the Mac's own fonts instead, with no download.

Only fonts that Wine's GDI+ can open are used as targets, because .NET / WinForms programs throw when
GDI+ can't find a font. On Wine 11 GDI+ finds Hiragino Sans W3, Hiragino Sans GB W3 and Arial Unicode MS,
but not Apple SD Gothic Neo, Hiragino Mincho, Songti or Heiti (GDI finds them all), so Korean and
Traditional Chinese use Arial Unicode MS for now. Engine/tests/cjk-text-test.cs checks the result.
"""
import sys

KOREAN = "Arial Unicode MS"
JAPANESE = "Hiragino Sans W3"
SIMPLIFIED = "Hiragino Sans GB W3"
TRADITIONAL = "Arial Unicode MS"

NAMES = [
    (KOREAN, ["Malgun Gothic", "맑은 고딕", "Gulim", "GulimChe", "굴림", "굴림체", "Dotum", "DotumChe", "돋움", "돋움체",
             "Batang", "BatangChe", "바탕", "바탕체", "Gungsuh", "GungsuhChe", "궁서", "궁서체"]),
    (JAPANESE, ["MS Gothic", "MS PGothic", "MS UI Gothic", "Meiryo", "Meiryo UI", "Yu Gothic", "Yu Gothic UI",
               "ＭＳ ゴシック", "ＭＳ Ｐゴシック", "メイリオ", "游ゴシック",
               "MS Mincho", "MS PMincho", "Yu Mincho", "ＭＳ 明朝", "ＭＳ Ｐ明朝", "游明朝"]),
    (SIMPLIFIED, ["Microsoft YaHei", "Microsoft YaHei UI", "SimHei", "微软雅黑", "黑体", "SimSun", "NSimSun", "宋体", "新宋体"]),
    (TRADITIONAL, ["PMingLiU", "MingLiU", "Microsoft JhengHei", "Microsoft JhengHei UI", "新細明體", "細明體", "微軟正黑體"]),
]


def main():
    lines = ["Windows Registry Editor Version 5.00", "", r"[HKEY_CURRENT_USER\Software\Wine\Fonts\Replacements]"]
    for target, names in NAMES:
        lines += ['"%s"="%s"' % (name, target) for name in names]
    with open(sys.argv[1], "w", encoding="utf-16") as f:
        f.write("\r\n".join(lines) + "\r\n")


if __name__ == "__main__":
    main()
