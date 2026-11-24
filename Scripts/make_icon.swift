#!/usr/bin/env swift
//
//  make_icon.swift
//  Miro
//
//  Renders Miro's sparkle app icon into Miro/Assets.xcassets/AppIcon.appiconset.
//  Usage: swift Scripts/make_icon.swift <appiconset folder>
//

import AppKit
import CoreGraphics

let outputFolder = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
                       ?? "Miro/Assets.xcassets/AppIcon.appiconset")

/// A four-pointed sparkle with softly concave sides.
func sparklePath(center: CGPoint, rx: CGFloat, ry: CGFloat, pinch: CGFloat = 0.13) -> CGPath {
    let path = CGMutablePath()
    let top = CGPoint(x: center.x, y: center.y + ry)
    let right = CGPoint(x: center.x + rx, y: center.y)
    let bottom = CGPoint(x: center.x, y: center.y - ry)
    let left = CGPoint(x: center.x - rx, y: center.y)
    let kx = rx * pinch, ky = ry * pinch
    path.move(to: top)
    path.addQuadCurve(to: right, control: CGPoint(x: center.x + kx, y: center.y + ky))
    path.addQuadCurve(to: bottom, control: CGPoint(x: center.x + kx, y: center.y - ky))
    path.addQuadCurve(to: left, control: CGPoint(x: center.x - kx, y: center.y - ky))
    path.addQuadCurve(to: top, control: CGPoint(x: center.x - kx, y: center.y + ky))
    path.closeSubpath()
    return path
}

func renderIcon(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let scale = size / 1024
    let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: scale, y: scale)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // macOS icon grid: 824pt rounded square centred in a 1024pt canvas
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)

    // Drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28,
                  color: CGColor(gray: 0, alpha: 0.28))
    ctx.addPath(tilePath)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // White → soft silver background
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let background = CGGradient(colorsSpace: colorSpace, colors: [
        CGColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1),
        CGColor(red: 0.93, green: 0.93, blue: 0.95, alpha: 1)
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // Sparkles (layout follows the reference: big star + two small ones)
    let unit: CGFloat = 3.5
    let origin = CGPoint(x: 512, y: 512)
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        // reference coordinates are y-down around (129, 115)
        CGPoint(x: origin.x + (x - 129) * unit, y: origin.y - (y - 115) * unit)
    }
    let stars: [CGPath] = [
        sparklePath(center: point(126, 118), rx: 70 * unit, ry: 77 * unit),
        sparklePath(center: point(182, 62), rx: 15 * unit, ry: 16.5 * unit),
        sparklePath(center: point(92, 172), rx: 18.5 * unit, ry: 20 * unit)
    ]
    let ink = CGGradient(colorsSpace: colorSpace, colors: [
        CGColor(red: 0.20, green: 0.20, blue: 0.23, alpha: 1),
        CGColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1)
    ] as CFArray, locations: [0, 1])!
    for star in stars {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: CGColor(gray: 0, alpha: 0.18))
        ctx.addPath(star)
        ctx.setFillColor(CGColor(gray: 0.08, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(star)
        ctx.clip()
        let box = star.boundingBox
        ctx.drawLinearGradient(ink, start: CGPoint(x: box.minX, y: box.maxY),
                               end: CGPoint(x: box.maxX, y: box.minY), options: [])
        ctx.restoreGState()
    }

    // Hairline edge like Apple's icons
    ctx.addPath(tilePath)
    ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.08))
    ctx.setLineWidth(2)
    ctx.strokePath()
    ctx.restoreGState()

    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])!
}

struct Entry { let file: String; let size: String; let scale: String; let pixels: Int }
let entries: [Entry] = [16, 32, 128, 256, 512].flatMap { base in
    [Entry(file: "icon_\(base)x\(base).png", size: "\(base)x\(base)", scale: "1x", pixels: base),
     Entry(file: "icon_\(base)x\(base)@2x.png", size: "\(base)x\(base)", scale: "2x", pixels: base * 2)]
}

let fileManager = FileManager.default
if let old = try? fileManager.contentsOfDirectory(at: outputFolder, includingPropertiesForKeys: nil) {
    for file in old where file.pathExtension == "png" { try? fileManager.removeItem(at: file) }
}
for entry in entries {
    try! renderIcon(pixels: entry.pixels).write(to: outputFolder.appending(path: entry.file))
}
let images = entries.map { ["filename": $0.file, "idiom": "mac", "scale": $0.scale, "size": $0.size] }
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: outputFolder.appending(path: "Contents.json"))
print("Wrote \(entries.count) icon images to \(outputFolder.path)")
