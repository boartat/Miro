//
//  CJKFonts.swift
//  Miro
//
//  Fonts for Windows programs without Microsoft fonts. The default is Noto Sans CJK KR (SIL Open Font License 1.1:
//  Latin, Hangul, kana and CJK ideographs), shipped with the miroe engine (miro/fonts) and copied into each prefix's
//  C:\windows\Fonts, so programs that open font files themselves (Unity, other engines) find it too.
//  The Windows names programs ask for are mapped to it:
//    - FontSubstitutes: Wine's dialog font (MS Shell Dlg / MS Shell Dlg 2)
//    - Replacements: Korean, Japanese and Chinese Windows font names, Segoe UI
//    - FontLink\SystemLink: the fallback list of the UI fonts Wine has itself (Tahoma …), so Korean drawn in Tahoma
//      comes from Noto; the Mac's own fonts follow as a further fallback (used where macOS keeps them, never copied)
//  Older engines without miro/fonts keep the earlier mapping to Mac fonts.
//

import Foundation
import WhiskyKit

enum CJKFonts {
    /// The family name inside NotoSansCJKkr-*.otf
    static let noto = "Noto Sans CJK KR"
    static let notoFiles = ["NotoSansCJKkr-Regular.otf": "Noto Sans CJK KR (TrueType)",
                            "NotoSansCJKkr-Bold.otf": "Noto Sans CJK KR Bold (TrueType)"]

    /// Earlier targets, for an engine without the Noto files (only targets Wine's GDI+ can open)
    static let macKorean = "Arial Unicode MS"
    static let macJapanese = "Hiragino Sans W3"
    static let macSimplified = "Hiragino Sans GB W3"

    static let korean = ["Malgun Gothic", "맑은 고딕", "Gulim", "GulimChe", "굴림", "굴림체", "Dotum", "DotumChe", "돋움", "돋움체",
                         "Batang", "BatangChe", "바탕", "바탕체", "Gungsuh", "GungsuhChe", "궁서", "궁서체"]
    static let japanese = ["MS Gothic", "MS PGothic", "MS UI Gothic", "Meiryo", "Meiryo UI", "Yu Gothic", "Yu Gothic UI",
                           "ＭＳ ゴシック", "ＭＳ Ｐゴシック", "メイリオ", "游ゴシック",
                           "MS Mincho", "MS PMincho", "Yu Mincho", "ＭＳ 明朝", "ＭＳ Ｐ明朝", "游明朝"]
    static let simplified = ["Microsoft YaHei", "Microsoft YaHei UI", "SimHei", "微软雅黑", "黑体", "SimSun", "NSimSun", "宋体", "新宋体"]
    static let traditional = ["PMingLiU", "MingLiU", "Microsoft JhengHei", "Microsoft JhengHei UI", "新細明體", "細明體", "微軟正黑體"]
    /// Modern Windows UI fonts Wine does not have
    static let uiNames = ["Segoe UI", "Segoe UI Semibold", "Segoe UI Bold"]

    /// Fallback fonts for the fonts Windows programs draw their UI with (HKLM\…\FontLink\SystemLink). Wine's own
    /// entries name Windows files (GULIM.TTC, MALGUN.TTF …) that are not there. Wine matches each entry by file name
    /// and family name.
    static let macLinks = [
        "AppleSDGothicNeo.ttc,Apple SD Gothic Neo",
        "ヒラギノ角ゴシック W3.ttc,Hiragino Sans W3",
        "Hiragino Sans GB.ttc,Hiragino Sans GB",
        "Arial Unicode.ttf,Arial Unicode MS",
    ]
    static let linkedFonts = [
        "Tahoma", "Tahoma Bold", "Microsoft Sans Serif", "MS Sans Serif", "Lucida Sans Unicode", "Segoe UI",
        "Segoe UI Bold", "Arial", "Arial Bold", "Verdana", "Times New Roman", "Courier New", "Trebuchet MS",
    ]

    static func notoSource(_ engine: WineEngine) -> URL? {
        let folder = engine.root.appending(path: "miro/fonts")
        return notoFiles.keys.allSatisfy({ folder.appending(path: $0).fileExists }) ? folder : nil
    }

    /// Set once per prefix (a marker in the prefix remembers it; v2 added the font links, v3 Noto Sans CJK)
    static func applyIfNeeded(engine: WineEngine, bottle: Bottle) async {
        let noto = notoSource(engine)
        let marker = engine.bottleURL.appending(path: noto != nil ? ".miro-cjk-fonts-3" : ".miro-cjk-fonts-2")
        guard engine.bottleURL.appending(path: "system.reg").fileExists, !marker.fileExists else { return }

        var lines = ["Windows Registry Editor Version 5.00", ""]
        var links = macLinks
        if let noto {
            // the font files themselves, in C:\windows\Fonts (an APFS clone: no extra space)
            let fonts = engine.bottleURL.appending(path: "drive_c/windows/Fonts")
            try? FileManager.default.createDirectory(at: fonts, withIntermediateDirectories: true)
            for file in notoFiles.keys where !fonts.appending(path: file).fileExists {
                try? FileManager.default.copyItem(at: noto.appending(path: file), to: fonts.appending(path: file))
            }
            lines += [#"[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Fonts]"#]
            lines += notoFiles.map { "\"\($0.value)\"=\"\($0.key)\"" }
            lines += ["", #"[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes]"#,
                      "\"MS Shell Dlg\"=\"\(Self.noto)\"", "\"MS Shell Dlg 2\"=\"\(Self.noto)\"", ""]
            lines += [#"[HKEY_CURRENT_USER\Software\Wine\Fonts\Replacements]"#]
            lines += (korean + japanese + simplified + traditional + uiNames).map { "\"\($0)\"=\"\(Self.noto)\"" }
            links.insert("NotoSansCJKkr-Regular.otf,\(Self.noto)", at: 0)
        } else {
            lines += [#"[HKEY_CURRENT_USER\Software\Wine\Fonts\Replacements]"#]
            lines += korean.map { "\"\($0)\"=\"\(macKorean)\"" } + traditional.map { "\"\($0)\"=\"\(macKorean)\"" }
            lines += japanese.map { "\"\($0)\"=\"\(macJapanese)\"" } + simplified.map { "\"\($0)\"=\"\(macSimplified)\"" }
        }
        // REG_MULTI_SZ: UTF-16LE strings, each ending in a NUL, and one more NUL
        let multi = (links.joined(separator: "\0") + "\0\0").data(using: .utf16LittleEndian) ?? Data()
        let hex = multi.map { String(format: "%02x", $0) }.joined(separator: ",")
        lines += ["", #"[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink]"#]
        lines += linkedFonts.map { "\"\($0)\"=hex(7):\(hex)" }
        let text = lines.joined(separator: "\r\n") + "\r\n"
        let file = FileManager.default.temporaryDirectory.appending(path: "miro-cjk-\(UUID().uuidString).reg")
        var data = Data([0xFF, 0xFE])  // regedit reads UTF-16LE with a BOM
        data.append(text.data(using: .utf16LittleEndian) ?? Data())
        guard (try? data.write(to: file)) != nil else { return }
        defer { try? FileManager.default.removeItem(at: file) }
        if let (status, _) = try? await engine.run(["regedit", "/S", file.path(percentEncoded: false)], bottle: bottle), status == 0 {
            FileManager.default.createFile(atPath: marker.path(percentEncoded: false), contents: Data())
        }
    }
}
