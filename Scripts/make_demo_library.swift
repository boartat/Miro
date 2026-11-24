//
//  make_demo_library.swift
//  Miro
//
//  Builds a demo library of made-up games for screenshots, so no real library ever ends up in a picture.
//
//      swift Scripts/make_demo_library.swift /Users/Shared/MiroDemo
//      Miro.app/Contents/MacOS/Miro -MiroLibraryFolder /Users/Shared/MiroDemo/Library
//
//  Each game is a folder with a tiny, non-runnable Windows executable (only headers and an import table, so
//  Miro's compatibility check has something to read) plus the marker files Miro uses to detect the engine.
//  Covers and icons are drawn here; nothing is downloaded.
//

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Demo games

struct DemoGame {
    let id: String
    let name: String
    let folder: String
    /// Executable path inside the game folder
    let exe: String
    let is64: Bool
    let imports: [(String, [String])]
    /// Extra files: relative path → contents
    let files: [String: String]
    let engine: String
    let playHours: Double
    let launches: Int
    let lastPlayedDaysAgo: Double?
    let addedDaysAgo: Double
    var profile = "balanced"
    var wineLearned: String?
    let palette: Palette
}

enum Palette { case starlight, neon, moon, sunset, dungeon, farm }

let kernel = ("KERNEL32.dll", ["GetModuleHandleW", "ExitProcess", "GetCommandLineW"])
let user = ("USER32.dll", ["CreateWindowExW", "PeekMessageW", "ShowWindow"])

let games: [DemoGame] = [
    DemoGame(
        id: "6A1C2F0E-5B7D-4E61-9C3A-1D2E3F4A5B01", name: "별빛 정원", folder: "StarlightGarden",
        exe: "StarlightGarden.exe", is64: true,
        imports: [("UnityPlayer.dll", ["UnityMain"]), ("VCRUNTIME140.dll", ["memset"]), kernel],
        files: ["UnityPlayer.dll": "demo", "StarlightGarden_Data/app.info": "Miro Demo\n별빛 정원\n"],
        engine: "unity", playHours: 12.4, launches: 9, lastPlayedDaysAgo: 0.05, addedDaysAgo: 12,
        wineLearned: "modern", palette: .starlight
    ),
    DemoGame(
        id: "6A1C2F0E-5B7D-4E61-9C3A-1D2E3F4A5B02", name: "Neon Drift", folder: "NeonDrift",
        exe: "NeonDrift/Binaries/Win64/NeonDrift-Win64-Shipping.exe", is64: true,
        imports: [("d3d12.dll", ["D3D12CreateDevice"]), ("dxgi.dll", ["CreateDXGIFactory2"]),
                  ("XINPUT1_3.dll", ["XInputGetState"]), ("MSVCP140.dll", ["?_Xlength_error@std@@YAXPEBD@Z"]),
                  ("VCRUNTIME140.dll", ["memcpy"]), kernel, user],
        files: ["Engine/Binaries/ThirdParty/readme.txt": "demo"],
        engine: "unreal", playHours: 31, launches: 22, lastPlayedDaysAgo: 1, addedDaysAgo: 30,
        profile: "performance", palette: .neon
    ),
    DemoGame(
        id: "6A1C2F0E-5B7D-4E61-9C3A-1D2E3F4A5B03", name: "달토끼 모험기", folder: "MoonRabbit",
        exe: "Game.exe", is64: true,
        imports: [("nw.dll", ["ChromeMain"]), kernel],
        files: ["nw.dll": "demo", "www/js/rpg_core.js": "// demo",
                "www/data/System.json": #"{"gameTitle":"달토끼 모험기"}"#],
        engine: "rpgMakerMV", playHours: 5.2, launches: 6, lastPlayedDaysAgo: 3, addedDaysAgo: 8, palette: .moon
    ),
    DemoGame(
        id: "6A1C2F0E-5B7D-4E61-9C3A-1D2E3F4A5B04", name: "여름의 끝에서", folder: "SummerEnd",
        exe: "SummerEnd.exe", is64: true,
        imports: [("python39.dll", ["Py_Main"]), kernel],
        files: ["renpy/__init__.py": "# demo", "lib/py3-windows-x86_64/python39.dll": "demo"],
        engine: "renpy", playHours: 3.1, launches: 4, lastPlayedDaysAgo: 6, addedDaysAgo: 9,
        profile: "efficiency", palette: .sunset
    ),
    DemoGame(
        id: "6A1C2F0E-5B7D-4E61-9C3A-1D2E3F4A5B05", name: "Pixel Dungeon Tales", folder: "PixelDungeon",
        exe: "PixelDungeon.exe", is64: false,
        imports: [("d3d11.dll", ["D3D11CreateDevice"]), ("d3dx9_43.dll", ["D3DXCreateTextureFromFileW"]),
                  ("XINPUT1_4.dll", ["XInputGetState"]), ("DSOUND.dll", ["DirectSoundCreate8"]), kernel, user],
        files: ["data.win": "demo"],
        engine: "gameMaker", playHours: 0.8, launches: 2, lastPlayedDaysAgo: 14, addedDaysAgo: 15, palette: .dungeon
    ),
    DemoGame(
        id: "6A1C2F0E-5B7D-4E61-9C3A-1D2E3F4A5B06", name: "작은 농장 이야기", folder: "TinyFarm",
        exe: "TinyFarm.exe", is64: false,
        imports: [("mscoree.dll", ["_CorExeMain"])],
        files: ["Microsoft.Xna.Framework.dll": "demo", "Microsoft.Xna.Framework.Game.dll": "demo"],
        engine: "xna", playHours: 0, launches: 0, lastPlayedDaysAgo: nil, addedDaysAgo: 0.02, palette: .farm
    )
]

let folderID = "6A1C2F0E-5B7D-4E61-9C3A-1D2E3F4A5BF1"
let folderGames = [games[2].id, games[3].id, games[4].id]

// MARK: - Minimal PE writer (headers + import table, no code worth running)

struct ByteWriter {
    var data: Data
    init(size: Int) { data = Data(count: size) }
    mutating func u8(_ offset: Int, _ value: UInt8) { data[offset] = value }
    mutating func u16(_ offset: Int, _ value: UInt16) { put(offset, value.littleEndian) }
    mutating func u32(_ offset: Int, _ value: UInt32) { put(offset, value.littleEndian) }
    mutating func u64(_ offset: Int, _ value: UInt64) { put(offset, value.littleEndian) }
    mutating func bytes(_ offset: Int, _ value: [UInt8]) { data.replaceSubrange(offset..<offset + value.count, with: value) }
    private mutating func put<T: FixedWidthInteger>(_ offset: Int, _ value: T) {
        withUnsafeBytes(of: value) { data.replaceSubrange(offset..<offset + MemoryLayout<T>.size, with: $0) }
    }
}

func align(_ value: Int, _ to: Int) -> Int { (value + to - 1) / to * to }

func makePE(is64: Bool, imports: [(String, [String])]) -> Data {
    let thunk = is64 ? 8 : 4
    let idataRVA = 0x2000
    // Lay out .idata: descriptors, lookup tables, address tables, hint/name entries, DLL names
    var pos = (imports.count + 1) * 20
    var ilt: [Int] = [], iat: [Int] = [], hints: [[Int]] = [], names: [Int] = []
    for (_, functions) in imports { ilt.append(pos); pos += (functions.count + 1) * thunk }
    let iatStart = pos
    for (_, functions) in imports { iat.append(pos); pos += (functions.count + 1) * thunk }
    let iatSize = pos - iatStart
    for (_, functions) in imports {
        hints.append(functions.map { function in
            defer { pos = align(pos + 2 + function.utf8.count + 1, 2) }
            return pos
        })
    }
    for (dll, _) in imports { names.append(pos); pos += dll.utf8.count + 1 }
    let idataSize = pos
    let idataRaw = align(idataSize, 0x200)

    var idata = ByteWriter(size: idataRaw)
    for (index, (dll, functions)) in imports.enumerated() {
        let descriptor = index * 20
        idata.u32(descriptor, UInt32(idataRVA + ilt[index]))
        idata.u32(descriptor + 12, UInt32(idataRVA + names[index]))
        idata.u32(descriptor + 16, UInt32(idataRVA + iat[index]))
        for (slot, function) in functions.enumerated() {
            let entry = UInt64(idataRVA + hints[index][slot])
            for table in [ilt[index], iat[index]] {
                if is64 { idata.u64(table + slot * 8, entry) } else { idata.u32(table + slot * 4, UInt32(entry)) }
            }
            idata.bytes(hints[index][slot] + 2, Array(function.utf8))
        }
        idata.bytes(names[index], Array(dll.utf8))
    }

    let headerSize = 0x400, textRaw = 0x200
    var pe = ByteWriter(size: headerSize + textRaw + idataRaw)
    pe.bytes(0, Array("MZ".utf8))
    pe.u32(0x3C, 0x40)
    pe.bytes(0x40, Array("PE".utf8) + [0, 0])
    let coff = 0x44
    pe.u16(coff, is64 ? 0x8664 : 0x14C)
    pe.u16(coff + 2, 2)
    pe.u16(coff + 16, is64 ? 240 : 224)
    pe.u16(coff + 18, is64 ? 0x0022 : 0x0102)
    let opt = coff + 20
    pe.u16(opt, is64 ? 0x20B : 0x10B)
    pe.u8(opt + 2, 14)
    pe.u32(opt + 4, UInt32(textRaw))
    pe.u32(opt + 8, UInt32(idataRaw))
    pe.u32(opt + 16, 0x1000)
    pe.u32(opt + 20, 0x1000)
    if is64 { pe.u64(opt + 24, 0x1_4000_0000) } else { pe.u32(opt + 24, 0x2000); pe.u32(opt + 28, 0x40_0000) }
    pe.u32(opt + 32, 0x1000)
    pe.u32(opt + 36, 0x200)
    pe.u16(opt + 40, 6)
    pe.u16(opt + 48, 6)
    pe.u32(opt + 56, UInt32(idataRVA + align(idataSize, 0x1000)))
    pe.u32(opt + 60, UInt32(headerSize))
    pe.u16(opt + 68, 2)  // Windows GUI
    pe.u16(opt + 70, is64 ? 0x8160 : 0x8140)
    let dirs: Int
    if is64 {
        pe.u64(opt + 72, 0x10_0000); pe.u64(opt + 80, 0x1000); pe.u64(opt + 88, 0x10_0000); pe.u64(opt + 96, 0x1000)
        pe.u32(opt + 108, 16); dirs = opt + 112
    } else {
        pe.u32(opt + 72, 0x10_0000); pe.u32(opt + 76, 0x1000); pe.u32(opt + 80, 0x10_0000); pe.u32(opt + 84, 0x1000)
        pe.u32(opt + 92, 16); dirs = opt + 96
    }
    pe.u32(dirs + 8, UInt32(idataRVA)); pe.u32(dirs + 12, UInt32((imports.count + 1) * 20))
    pe.u32(dirs + 96, UInt32(idataRVA + iatStart)); pe.u32(dirs + 100, UInt32(iatSize))

    let sections = dirs + 16 * 8
    func section(_ index: Int, _ name: String, rva: Int, virtualSize: Int, raw: Int, rawOffset: Int, flags: UInt32) {
        let header = sections + index * 40
        pe.bytes(header, Array(name.utf8))
        pe.u32(header + 8, UInt32(virtualSize))
        pe.u32(header + 12, UInt32(rva))
        pe.u32(header + 16, UInt32(raw))
        pe.u32(header + 20, UInt32(rawOffset))
        pe.u32(header + 36, flags)
    }
    section(0, ".text", rva: 0x1000, virtualSize: 1, raw: textRaw, rawOffset: headerSize, flags: 0x6000_0020)
    section(1, ".idata", rva: idataRVA, virtualSize: idataSize, raw: idataRaw, rawOffset: headerSize + textRaw,
            flags: 0xC000_0040)
    pe.u8(headerSize, 0xC3)  // ret
    pe.data.replaceSubrange(headerSize + textRaw..<headerSize + textRaw + idataRaw, with: idata.data)
    return pe.data
}

// MARK: - Artwork

struct Seeded {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func verticalGradient(_ ctx: CGContext, _ colors: [UInt32], in rect: CGRect) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: colors.map { color($0) } as CFArray, locations: nil)!
    ctx.saveGState()
    ctx.clip(to: rect)
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])
    ctx.restoreGState()
}

func glow(_ ctx: CGContext, at point: CGPoint, radius: CGFloat, _ hex: UInt32, _ alpha: CGFloat) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [color(hex, alpha), color(hex, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(gradient, startCenter: point, startRadius: 0, endCenter: point, endRadius: radius, options: [])
}

func circle(_ ctx: CGContext, _ center: CGPoint, _ radius: CGFloat, _ fill: CGColor) {
    ctx.setFillColor(fill)
    ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
}

/// Rolling silhouette along the bottom (y is from the bottom)
func hills(_ ctx: CGContext, width: CGFloat, base: CGFloat, amplitude: CGFloat, waves: Double, phase: Double, _ fill: CGColor) {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 0, y: 0))
    for x in stride(from: 0, through: width, by: 8) {
        let t = Double(x / width)
        let y = base + amplitude * CGFloat(sin(t * waves * .pi * 2 + phase) * 0.6 + sin(t * waves * 5.3 + phase * 2) * 0.4)
        path.addLine(to: CGPoint(x: x, y: y))
    }
    path.addLine(to: CGPoint(x: width, y: 0))
    path.closeSubpath()
    ctx.addPath(path)
    ctx.setFillColor(fill)
    ctx.fillPath()
}

func stars(_ ctx: CGContext, count: Int, in rect: CGRect, seed: UInt64, _ hex: UInt32) {
    var rng = Seeded(state: seed)
    for _ in 0..<count {
        let point = CGPoint(x: rect.minX + rect.width * rng.next(), y: rect.minY + rect.height * rng.next())
        let size = 1 + 3 * pow(rng.next(), 3)
        circle(ctx, point, size, color(hex, 0.35 + 0.65 * rng.next()))
    }
}

func draw(_ palette: Palette, _ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
    let full = CGRect(x: 0, y: 0, width: w, height: h)
    switch palette {
    case .starlight:
        verticalGradient(ctx, [0x0B1033, 0x2A1B5C, 0x5B3A8C], in: full)
        stars(ctx, count: 420, in: CGRect(x: 0, y: h * 0.3, width: w, height: h * 0.7), seed: 7, 0xFFFFFF)
        glow(ctx, at: CGPoint(x: w * 0.72, y: h * 0.72), radius: 260, 0xFFE9A8, 0.55)
        circle(ctx, CGPoint(x: w * 0.72, y: h * 0.72), 92, color(0xFFF4D6))
        circle(ctx, CGPoint(x: w * 0.74, y: h * 0.74), 84, color(0x2F2063))
        hills(ctx, width: w, base: h * 0.30, amplitude: 50, waves: 1.3, phase: 0.4, color(0x2C1E57))
        hills(ctx, width: w, base: h * 0.20, amplitude: 40, waves: 2.1, phase: 1.7, color(0x1A1240))
        var rng = Seeded(state: 11)
        for _ in 0..<70 {
            let point = CGPoint(x: w * rng.next(), y: h * (0.08 + 0.2 * rng.next()))
            glow(ctx, at: point, radius: 26, [0xFF9BD2, 0x9BE7FF, 0xFFE38A][Int(rng.next() * 3)], 0.9)
        }
    case .neon:
        verticalGradient(ctx, [0x07020F, 0x2B0A3D, 0x8A1C6E], in: full)
        let horizon = h * 0.42
        glow(ctx, at: CGPoint(x: w / 2, y: horizon + 150), radius: 420, 0xFF4FA3, 0.45)
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: horizon, width: w, height: h))
        let sunCenter = CGPoint(x: w / 2, y: horizon + 150)
        let sun = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                             colors: [color(0xFFD25E), color(0xFF3D8B)] as CFArray, locations: nil)!
        ctx.addEllipse(in: CGRect(x: sunCenter.x - 230, y: sunCenter.y - 230, width: 460, height: 460))
        ctx.clip()
        ctx.drawLinearGradient(sun, start: CGPoint(x: 0, y: sunCenter.y + 230), end: CGPoint(x: 0, y: sunCenter.y - 230), options: [])
        ctx.restoreGState()
        for index in 0..<7 {
            let y = horizon + 20 + CGFloat(index) * 26
            ctx.setFillColor(color(0x2B0A3D))
            ctx.fill(CGRect(x: w / 2 - 240, y: y, width: 480, height: CGFloat(4 + index)))
        }
        ctx.setFillColor(color(0x0A0314))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: horizon))
        ctx.setStrokeColor(color(0x35E0FF, 0.8))
        ctx.setLineWidth(2)
        for index in -18...18 {
            ctx.move(to: CGPoint(x: w / 2 + CGFloat(index) * 40, y: horizon))
            ctx.addLine(to: CGPoint(x: w / 2 + CGFloat(index) * 260, y: 0))
        }
        var y = horizon
        var step: CGFloat = 8
        while y > 0 {
            ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: w, y: y))
            y -= step; step *= 1.28
        }
        ctx.strokePath()
        glow(ctx, at: CGPoint(x: w / 2, y: horizon), radius: 700, 0x35E0FF, 0.18)
    case .moon:
        verticalGradient(ctx, [0x0E2246, 0x1F4E80, 0x4E8CC2], in: full)
        stars(ctx, count: 260, in: CGRect(x: 0, y: h * 0.45, width: w, height: h * 0.55), seed: 21, 0xEAF4FF)
        glow(ctx, at: CGPoint(x: w * 0.3, y: h * 0.66), radius: 330, 0xFFF6D8, 0.5)
        circle(ctx, CGPoint(x: w * 0.3, y: h * 0.66), 170, color(0xFFF3CF))
        for (dx, dy, r) in [(-50.0, 30.0, 26.0), (40, -40, 34), (60, 60, 18), (-20, -70, 14)] {
            circle(ctx, CGPoint(x: w * 0.3 + dx, y: h * 0.66 + dy), r, color(0xF1E2B4))
        }
        for (x, y, scale) in [(0.62, 0.62, 1.0), (0.8, 0.5, 0.7), (0.15, 0.4, 0.8)] {
            for (dx, r) in [(0.0, 60.0), (70, 80), (150, 55)] {
                circle(ctx, CGPoint(x: w * x + dx * scale, y: h * y), r * scale, color(0xD8E8F7, 0.55))
            }
        }
        hills(ctx, width: w, base: h * 0.22, amplitude: 70, waves: 1.7, phase: 2.2, color(0x173659))
        hills(ctx, width: w, base: h * 0.12, amplitude: 45, waves: 2.6, phase: 0.3, color(0x0D2140))
    case .sunset:
        verticalGradient(ctx, [0x2B1846, 0xC2456A, 0xFF9A5A, 0xFFD38A], in: CGRect(x: 0, y: h * 0.38, width: w, height: h * 0.62))
        glow(ctx, at: CGPoint(x: w * 0.5, y: h * 0.42), radius: 480, 0xFFE3A3, 0.6)
        circle(ctx, CGPoint(x: w * 0.5, y: h * 0.46), 140, color(0xFFF1C9))
        verticalGradient(ctx, [0x3A2357, 0x8A3D6E, 0x1B1236], in: CGRect(x: 0, y: 0, width: w, height: h * 0.38))
        var rng = Seeded(state: 5)
        for index in 0..<26 {
            let y = h * 0.38 - CGFloat(index) * 15 - 6
            let width = (380 - CGFloat(index) * 9) * (0.7 + 0.6 * rng.next())
            ctx.setFillColor(color(0xFFD9A0, 0.75 - CGFloat(index) * 0.025))
            ctx.fill(CGRect(x: w / 2 - width / 2, y: y, width: width, height: 4))
        }
        for (x, y) in [(0.18, 0.78), (0.24, 0.8), (0.75, 0.74)] {
            ctx.setStrokeColor(color(0x2B1846, 0.8)); ctx.setLineWidth(5)
            ctx.move(to: CGPoint(x: w * x - 24, y: h * y)); ctx.addLine(to: CGPoint(x: w * x, y: h * y - 12))
            ctx.addLine(to: CGPoint(x: w * x + 24, y: h * y)); ctx.strokePath()
        }
    case .dungeon:
        verticalGradient(ctx, [0x120E14, 0x231B26, 0x161118], in: full)
        let tile: CGFloat = 60
        var rng = Seeded(state: 3)
        for row in 0..<Int(h / tile) + 1 {
            for col in 0..<Int(w / tile) + 1 {
                let shade = 0.16 + 0.12 * rng.next()
                ctx.setFillColor(CGColor(srgbRed: shade, green: shade * 0.85, blue: shade * 0.95, alpha: 1))
                let offset = row % 2 == 0 ? 0 : tile / 2
                ctx.fill(CGRect(x: CGFloat(col) * tile + offset, y: CGFloat(row) * tile, width: tile - 4, height: tile - 4))
            }
        }
        for x in [0.22, 0.78] {
            glow(ctx, at: CGPoint(x: w * x, y: h * 0.6), radius: 380, 0xFF8A2B, 0.55)
            ctx.setFillColor(color(0x3B2A1E)); ctx.fill(CGRect(x: w * x - 12, y: h * 0.45, width: 24, height: 110))
            for (dy, size, hex) in [(0.0, 40.0, 0xFF6A1A), (30, 28, 0xFFB52E), (54, 16, 0xFFF0A0)] as [(CGFloat, CGFloat, UInt32)] {
                ctx.setFillColor(color(hex)); ctx.fill(CGRect(x: w * x - size / 2, y: h * 0.45 + 110 + dy, width: size, height: size))
            }
        }
        ctx.setFillColor(color(0x07050A))
        ctx.fill(CGRect(x: w / 2 - 170, y: 0, width: 340, height: h * 0.55))
        ctx.fillEllipse(in: CGRect(x: w / 2 - 170, y: h * 0.55 - 170, width: 340, height: 340))
        glow(ctx, at: CGPoint(x: w / 2, y: h * 0.3), radius: 120, 0x7DF2FF, 0.35)
    case .farm:
        verticalGradient(ctx, [0x7CC8F2, 0xBFE6FA, 0xFFF4D6], in: full)
        glow(ctx, at: CGPoint(x: w * 0.8, y: h * 0.78), radius: 300, 0xFFF0A0, 0.8)
        circle(ctx, CGPoint(x: w * 0.8, y: h * 0.78), 90, color(0xFFE066))
        for (x, y) in [(0.2, 0.8), (0.5, 0.86)] {
            for (dx, r) in [(0.0, 50.0), (60, 70), (130, 48)] {
                circle(ctx, CGPoint(x: w * x + dx, y: h * y), r, color(0xFFFFFF, 0.9))
            }
        }
        hills(ctx, width: w, base: h * 0.42, amplitude: 60, waves: 1.1, phase: 1.0, color(0x8FD46B))
        hills(ctx, width: w, base: h * 0.30, amplitude: 50, waves: 1.6, phase: 2.6, color(0x5DB44E))
        let barn = CGRect(x: w * 0.3, y: h * 0.3, width: 260, height: 200)
        ctx.setFillColor(color(0xD9483B)); ctx.fill(barn)
        ctx.move(to: CGPoint(x: barn.minX - 30, y: barn.maxY)); ctx.addLine(to: CGPoint(x: barn.midX, y: barn.maxY + 120))
        ctx.addLine(to: CGPoint(x: barn.maxX + 30, y: barn.maxY)); ctx.closePath()
        ctx.setFillColor(color(0x8E2A24)); ctx.fillPath()
        ctx.setFillColor(color(0xFFF4E0)); ctx.fill(CGRect(x: barn.midX - 45, y: barn.minY, width: 90, height: 120))
        hills(ctx, width: w, base: h * 0.16, amplitude: 30, waves: 2.2, phase: 0.2, color(0x3F8F3A))
        var rng = Seeded(state: 9)
        for _ in 0..<90 {
            circle(ctx, CGPoint(x: w * rng.next(), y: h * 0.12 * rng.next()), 6, color([0xFFFFFF, 0xFFD54F, 0xFF8FB1][Int(rng.next() * 3)]))
        }
    }
}

func render(width: Int, height: Int, _ body: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    body(ctx)
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(url.path)") }
}

// MARK: - Main

guard CommandLine.arguments.count == 2 else {
    print("usage: swift make_demo_library.swift <output folder>")
    exit(1)
}
let root = URL(filePath: CommandLine.arguments[1], directoryHint: .isDirectory)
let fileManager = FileManager.default
let library = root.appending(path: "Library")
let gamesFolder = root.appending(path: "Games")
for folder in [library, gamesFolder] where fileManager.fileExists(atPath: folder.path) {
    try fileManager.removeItem(at: folder)
}
for folder in [library.appending(path: "Covers"), library.appending(path: "Icons"), gamesFolder] {
    try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
}

let iso = ISO8601DateFormatter()
func daysAgo(_ days: Double) -> String { iso.string(from: Date.now.addingTimeInterval(-days * 86_400)) }

var entries: [[String: Any]] = []
for game in games {
    let folder = gamesFolder.appending(path: game.folder)
    let exe = folder.appending(path: game.exe)
    try fileManager.createDirectory(at: exe.deletingLastPathComponent(), withIntermediateDirectories: true)
    try makePE(is64: game.is64, imports: game.imports).write(to: exe)
    for (path, contents) in game.files {
        let url = folder.appending(path: path)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }

    let cover = render(width: 1920, height: 1080) { draw(game.palette, $0, 1920, 1080) }
    writePNG(cover, to: library.appending(path: "Covers/\(game.id).png"))
    let icon = render(width: 256, height: 256) { ctx in
        ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 256, height: 256), cornerWidth: 56, cornerHeight: 56, transform: nil))
        ctx.clip()
        ctx.draw(cover.cropping(to: CGRect(x: 960 - 400, y: 540 - 400, width: 800, height: 800))!,
                 in: CGRect(x: 0, y: 0, width: 256, height: 256))
    }
    writePNG(icon, to: library.appending(path: "Icons/\(game.id).png"))

    var entry: [String: Any] = [
        "id": game.id, "name": game.name, "executablePath": exe.path(percentEncoded: false),
        "addedAt": daysAgo(game.addedDaysAgo), "playSeconds": game.playHours * 3600, "launchCount": game.launches,
        "engine": game.engine, "architecture": game.is64 ? "64-bit" : "32-bit",
        "coverFile": "Covers/\(game.id).png", "iconFile": "Icons/\(game.id).png",
        "artworkLookupDone": true, "profile": game.profile, "winePreference": "auto"
    ]
    if let days = game.lastPlayedDaysAgo {
        entry["lastPlayedAt"] = daysAgo(days)
        entry["lastRunSucceeded"] = true
        entry["lastExitCode"] = 0
    }
    if let learned = game.wineLearned { entry["wineLearned"] = learned }
    entries.append(entry)
}

func writeJSON(_ object: Any, _ name: String) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: library.appending(path: name))
}
try writeJSON(entries, "games.json")
try writeJSON([["id": folderID, "name": "인디 게임 모음", "gameIDs": folderGames, "isExpanded": true]], "folders.json")
print("Demo library ready: \(library.path(percentEncoded: false))")
