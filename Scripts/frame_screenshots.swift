//
//  frame_screenshots.swift
//  Miro
//
//  Puts raw window captures (`screencapture -o -l <window id>`) on a soft background with a shadow,
//  all at the same scale so text is the same size in every picture.
//
//      swift Scripts/frame_screenshots.swift docs/screenshots/raw docs/screenshots
//

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    print("usage: swift frame_screenshots.swift <raw folder> <output folder>")
    exit(1)
}
let input = URL(filePath: CommandLine.arguments[1], directoryHint: .isDirectory)
let output = URL(filePath: CommandLine.arguments[2], directoryHint: .isDirectory)
let files = try FileManager.default.contentsOfDirectory(atPath: input.path(percentEncoded: false))
    .filter { $0.hasSuffix(".png") }.sorted()

/// Output pixels per captured pixel (captures are 2× Retina)
let scale: CGFloat = 0.58
let padding: CGFloat = 120
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

for file in files {
    guard let source = CGImageSourceCreateWithURL(input.appending(path: file) as CFURL, nil),
          let window = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
    let canvas = CGSize(width: CGFloat(window.width) + padding * 2, height: CGFloat(window.height) + padding * 2)
    let width = Int((canvas.width * scale).rounded()), height = Int((canvas.height * scale).rounded())
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: scale, y: scale)

    let background = CGGradient(colorsSpace: srgb, colors: [color(0xE6ECFF), color(0xF1E8FF), color(0xFCEFF4)] as CFArray,
                                locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: 0, y: canvas.height), end: CGPoint(x: canvas.width, y: 0), options: [])

    let frame = CGRect(x: padding, y: padding, width: CGFloat(window.width), height: CGFloat(window.height))
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 90, color: color(0x1B1F3B, 0.28))
    ctx.draw(window, in: frame)
    ctx.restoreGState()

    let destination = CGImageDestinationCreateWithURL(output.appending(path: file) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(file)") }
    print("\(file): \(width)×\(height)")
}
