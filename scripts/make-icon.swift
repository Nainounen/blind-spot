#!/usr/bin/env swift
// Generates BlindSpot.icns — no external dependencies, uses only built-in macOS frameworks.
// Run: swift make-icon.swift

import AppKit
import Foundation

// MARK: - Draw one size

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let bmp = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bmp)
    let ctx = NSGraphicsContext.current!.cgContext

    // ── Rounded rect clip (macOS icon shape) ──────────────────────────────────
    let r = s * 0.224
    ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                       cornerWidth: r, cornerHeight: r, transform: nil))
    ctx.clip()

    // ── Purple gradient background ────────────────────────────────────────────
    let space = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(
        colorsSpace: space,
        colors: [
            CGColor(colorSpace: space, components: [0.55, 0.36, 0.97, 1.0])!,  // #8C5CF7 top-left
            CGColor(colorSpace: space, components: [0.20, 0.06, 0.45, 1.0])!,  // #340F73 bottom-right
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: s),
        end:   CGPoint(x: s, y: 0),
        options: []
    )

    // ── Eye outline ───────────────────────────────────────────────────────────
    let eyeL  = s * 0.16
    let eyeR  = s * 0.84
    let eyeCy = s * 0.50
    let bulge = s * 0.22   // how tall the eye arcs are

    ctx.setStrokeColor(CGColor(colorSpace: space, components: [1, 1, 1, 0.88])!)
    ctx.setLineWidth(s * 0.055)
    ctx.setLineCap(.round)

    // upper arc
    let top = CGMutablePath()
    top.move(to: CGPoint(x: eyeL, y: eyeCy))
    top.addQuadCurve(
        to:      CGPoint(x: eyeR,  y: eyeCy),
        control: CGPoint(x: s / 2, y: eyeCy + bulge)
    )
    ctx.addPath(top); ctx.strokePath()

    // lower arc
    let bot = CGMutablePath()
    bot.move(to: CGPoint(x: eyeL, y: eyeCy))
    bot.addQuadCurve(
        to:      CGPoint(x: eyeR,  y: eyeCy),
        control: CGPoint(x: s / 2, y: eyeCy - bulge)
    )
    ctx.addPath(bot); ctx.strokePath()

    // ── 4-pointed sparkle (star) ──────────────────────────────────────────────
    let cx     = s * 0.50
    let cy     = s * 0.50
    let outer  = s * 0.165   // tip length
    let inner  = s * 0.038   // waist width

    let star = CGMutablePath()
    for i in 0..<8 {
        let angle  = CGFloat(i) * .pi / 4.0 - .pi / 2.0
        let radius = i % 2 == 0 ? outer : inner
        let pt = CGPoint(x: cx + cos(angle) * radius,
                         y: cy + sin(angle) * radius)
        if i == 0 { star.move(to: pt) } else { star.addLine(to: pt) }
    }
    star.closeSubpath()

    ctx.setFillColor(CGColor(colorSpace: space, components: [1, 1, 1, 0.97])!)
    ctx.addPath(star)
    ctx.fillPath()

    NSGraphicsContext.restoreGraphicsState()

    guard let png = bmp.representation(using: .png, properties: [:]) else {
        fatalError("PNG conversion failed for size \(size)")
    }
    return png
}

// MARK: - Iconset layout

let specs: [(file: String, size: Int)] = [
    ("icon_16x16.png",      16),
    ("icon_16x16@2x.png",   32),
    ("icon_32x32.png",      32),
    ("icon_32x32@2x.png",   64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png", 1024),
]

// MARK: - Main

let fm  = FileManager.default
let dir = URL(fileURLWithPath: "assets/BlindSpot.iconset")
try? fm.removeItem(at: dir)
try  fm.createDirectory(at: dir, withIntermediateDirectories: true)

// Cache renders (multiple specs share the same pixel size)
var cache: [Int: Data] = [:]
for spec in specs {
    if cache[spec.size] == nil { cache[spec.size] = render(size: spec.size) }
    try cache[spec.size]!.write(to: dir.appendingPathComponent(spec.file))
    print("  ✓ \(spec.file)")
}

// Convert to ICNS
let result = Process()
result.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
result.arguments = ["-c", "icns", "assets/BlindSpot.iconset", "--output", "assets"]
try result.run(); result.waitUntilExit()

try? fm.removeItem(at: dir)

if result.terminationStatus == 0 {
    print("\n✓ BlindSpot.icns created")
    print("  Copy it to your app bundle: cp BlindSpot.icns BlindSpot.app/Contents/Resources/")
} else {
    print("iconutil failed — iconset left in BlindSpot.iconset/")
}
