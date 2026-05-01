#!/usr/bin/env swift
// Generates BlindSpot-dmg-bg.png — the background image shown when the user
// mounts BlindSpot.dmg. No external dependencies; uses Core Graphics only.
//
// Run: swift make-dmg-bg.swift
//
// Pixel size 1200x800 (= logical 600x400 @2x), matching the Finder window
// bounds set by make-release.sh.

import AppKit
import Foundation

let pixelW: CGFloat = 1200
let pixelH: CGFloat = 800
let logicalW: CGFloat = pixelW / 2
let logicalH: CGFloat = pixelH / 2

let bmp = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(pixelW), pixelsHigh: Int(pixelH),
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .calibratedRGB,
    bytesPerRow: 0, bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bmp)
let ctx = NSGraphicsContext.current!.cgContext
let space = CGColorSpaceCreateDeviceRGB()

// MARK: - Diagonal purple gradient (matches the app icon palette)

let bgGradient = CGGradient(
    colorsSpace: space,
    colors: [
        CGColor(colorSpace: space, components: [0.10, 0.06, 0.20, 1.0])!, // top-left, dark
        CGColor(colorSpace: space, components: [0.22, 0.13, 0.40, 1.0])!, // bottom-right, lighter purple
    ] as CFArray,
    locations: [0.0, 1.0]
)!
ctx.drawLinearGradient(
    bgGradient,
    start: CGPoint(x: 0, y: pixelH),
    end:   CGPoint(x: pixelW, y: 0),
    options: []
)

// Soft radial glow centred behind the title for depth
let glow = CGGradient(
    colorsSpace: space,
    colors: [
        CGColor(colorSpace: space, components: [0.55, 0.36, 0.97, 0.18])!,
        CGColor(colorSpace: space, components: [0.55, 0.36, 0.97, 0.0])!,
    ] as CFArray,
    locations: [0.0, 1.0]
)!
ctx.drawRadialGradient(
    glow,
    startCenter: CGPoint(x: pixelW / 2, y: pixelH * 0.78),
    startRadius: 0,
    endCenter:   CGPoint(x: pixelW / 2, y: pixelH * 0.78),
    endRadius:   pixelW * 0.42,
    options: []
)

// MARK: - Sparkle (matches the app icon's 4-pointed star)

func drawSparkle(at center: CGPoint, size: CGFloat, alpha: CGFloat = 0.85) {
    let outer = size * 0.5
    let inner = size * 0.10
    let path = CGMutablePath()
    for i in 0..<8 {
        let angle = CGFloat(i) * .pi / 4.0 - .pi / 2.0
        let radius = i % 2 == 0 ? outer : inner
        let pt = CGPoint(x: center.x + cos(angle) * radius,
                         y: center.y + sin(angle) * radius)
        if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
    }
    path.closeSubpath()
    ctx.setFillColor(CGColor(colorSpace: space, components: [1, 1, 1, alpha])!)
    ctx.addPath(path)
    ctx.fillPath()
}

// Sparkle just to the left of the title baseline
drawSparkle(at: CGPoint(x: pixelW / 2 - 230, y: pixelH - 138), size: 36)

// MARK: - Title & subtitle

func draw(_ string: String, font: NSFont, color: NSColor, centeredAtY y: CGFloat) {
    let attr: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
    ]
    let s = NSAttributedString(string: string, attributes: attr)
    let size = s.size()
    s.draw(at: NSPoint(x: (pixelW - size.width) / 2, y: y))
}

draw("BlindSpot",
     font: NSFont.systemFont(ofSize: 56, weight: .bold),
     color: .white,
     centeredAtY: pixelH - 165)

draw("Drag the app onto Applications to install",
     font: NSFont.systemFont(ofSize: 22, weight: .regular),
     color: NSColor.white.withAlphaComponent(0.62),
     centeredAtY: pixelH - 220)

// MARK: - Arrow between the icon positions
//
// make-release.sh places the app icon at Finder (160, 220) and the Applications
// alias at (440, 220), both in 600x400 logical coords. Convert to pixel coords
// with the bottom-left origin AppKit uses: pixel y = pixelH - 2 * logicalY.

let iconRowY: CGFloat = pixelH - 2 * 220 // = 360
let leftIconX: CGFloat = 2 * 160         // = 320
let rightIconX: CGFloat = 2 * 440        // = 880
let iconHalfPx: CGFloat = 128            // half of 128px logical icon × 2 ≈ 128 px on each side
let arrowStartX = leftIconX + iconHalfPx + 24
let arrowEndX   = rightIconX - iconHalfPx - 24

let strokeColor = CGColor(colorSpace: space, components: [1, 1, 1, 0.55])!
ctx.setStrokeColor(strokeColor)
ctx.setFillColor(strokeColor)
ctx.setLineCap(.round)
ctx.setLineWidth(8)

// Shaft (stops short so the head fills cleanly)
ctx.move(to: CGPoint(x: arrowStartX, y: iconRowY))
ctx.addLine(to: CGPoint(x: arrowEndX - 18, y: iconRowY))
ctx.strokePath()

// Solid triangular head
let headW: CGFloat = 32
let headH: CGFloat = 20
ctx.move(to: CGPoint(x: arrowEndX, y: iconRowY))
ctx.addLine(to: CGPoint(x: arrowEndX - headW, y: iconRowY + headH))
ctx.addLine(to: CGPoint(x: arrowEndX - headW, y: iconRowY - headH))
ctx.closePath()
ctx.fillPath()

// MARK: - Label legibility pills
//
// Finder renders icon labels in the system appearance color (black in light
// mode). The dark background makes them unreadable. Draw a soft white-tinted
// pill behind each label row so labels are legible in both light and dark mode.
//
// Icon centers (logical): BlindSpot=(160,220), Applications=(440,220)
// Icon radius (logical): 64 → pixel 128
// Label sits ~8px below icon bottom, roughly 18px tall (logical)
// In pixel CG coords (origin bottom-left):
//   icon center y = pixelH - 220*2 = 360
//   label top     = 360 - 128 - 8  = 224
//   label bottom  = 224 - 36       = 188

func drawLabelPill(centerX: CGFloat) {
    let pillW: CGFloat = 260
    let pillH: CGFloat = 40
    let pillX = centerX - pillW / 2
    let pillY: CGFloat = 184
    let radius: CGFloat = pillH / 2
    let rect = CGRect(x: pillX, y: pillY, width: pillW, height: pillH)
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.setFillColor(CGColor(colorSpace: space, components: [1, 1, 1, 0.18])!)
    ctx.addPath(path)
    ctx.fillPath()
}

drawLabelPill(centerX: leftIconX)   // BlindSpot
drawLabelPill(centerX: rightIconX)  // Applications

NSGraphicsContext.restoreGraphicsState()

// MARK: - Save as PNG with 2x DPI

bmp.size = NSSize(width: logicalW, height: logicalH) // marks the file as 2x

guard let png = bmp.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("PNG encoding failed\n".utf8))
    exit(1)
}

let outURL = URL(fileURLWithPath: "BlindSpot-dmg-bg.png")
try png.write(to: outURL)
print("✓ Wrote \(outURL.path) (\(Int(pixelW))x\(Int(pixelH)) px, logical \(Int(logicalW))x\(Int(logicalH)))")
