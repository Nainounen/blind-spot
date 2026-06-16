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

// MARK: - Solid white background

ctx.setFillColor(CGColor(colorSpace: space, components: [1, 1, 1, 1])!)
ctx.fill(CGRect(x: 0, y: 0, width: pixelW, height: pixelH))

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
     color: NSColor(white: 0.15, alpha: 1),
     centeredAtY: pixelH - 165)

draw("Drag the app onto Applications to install",
     font: NSFont.systemFont(ofSize: 22, weight: .regular),
     color: NSColor(white: 0.4, alpha: 1),
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

let arrowColor = CGColor(colorSpace: space, components: [0.5, 0.5, 0.5, 0.8])!
ctx.setStrokeColor(arrowColor)
ctx.setFillColor(arrowColor)
ctx.setLineCap(.round)
ctx.setLineWidth(6)

// Shaft (stops short so the head fills cleanly)
ctx.move(to: CGPoint(x: arrowStartX, y: iconRowY))
ctx.addLine(to: CGPoint(x: arrowEndX - 18, y: iconRowY))
ctx.strokePath()

// Solid triangular head
let headW: CGFloat = 28
let headH: CGFloat = 18
ctx.move(to: CGPoint(x: arrowEndX, y: iconRowY))
ctx.addLine(to: CGPoint(x: arrowEndX - headW, y: iconRowY + headH))
ctx.addLine(to: CGPoint(x: arrowEndX - headW, y: iconRowY - headH))
ctx.closePath()
ctx.fillPath()

NSGraphicsContext.restoreGraphicsState()

// MARK: - Save as PNG with 2x DPI

bmp.size = NSSize(width: logicalW, height: logicalH) // marks the file as 2x

guard let png = bmp.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("PNG encoding failed\n".utf8))
    exit(1)
}

let outURL = URL(fileURLWithPath: "assets/BlindSpot-dmg-bg.png")
try png.write(to: outURL)
print("✓ Wrote \(outURL.path) (\(Int(pixelW))x\(Int(pixelH)) px, logical \(Int(logicalW))x\(Int(logicalH)))")
