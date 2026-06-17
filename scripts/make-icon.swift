#!/usr/bin/env swift
// Generates BlindSpot.icns — no external dependencies, uses only built-in
// macOS frameworks (NSImage SVG support on macOS 26+).
// Also generates the menu bar template icon (PDF + PNG).
//
// Source priority:
//   1. assets/blindspot.svg — vector design source (if available)
//   2. assets/BlindSpot.icns   — extracts 1024px rep from existing icns
//
// Run: swift scripts/make-icon.swift

import AppKit
import Foundation

let fm = FileManager.default
let repo = URL(fileURLWithPath: fm.currentDirectoryPath)
let assetsDir = repo.appendingPathComponent("assets")

// MARK: - Load source image

let svgPath = assetsDir.appendingPathComponent("blindspot.svg").path
let icnsPath = assetsDir.appendingPathComponent("BlindSpot.icns").path

let sourceImage: NSImage
let sourceDescription: String

if fm.fileExists(atPath: svgPath), let img = NSImage(contentsOfFile: svgPath) {
    sourceImage = img
    sourceDescription = "SVG (assets/blindspot.svg)"
} else if fm.fileExists(atPath: icnsPath), let img = NSImage(contentsOfFile: icnsPath) {
    sourceImage = img
    sourceDescription = "existing ICNS (assets/BlindSpot.icns)"
} else {
    fputs("Error: no source found — place blindspot.svg in assets/ or run after a prior build\n", stderr)
    exit(1)
}

// MARK: - Render at a given pixel size

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let rect = CGRect(x: 0, y: 0, width: s, height: s)

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

    // Rounded-rect clip for macOS icon shape
    let r = s * 0.224
    let clipPath = CGPath(
        roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
        cornerWidth: r, cornerHeight: r, transform: nil
    )
    NSGraphicsContext.current!.cgContext.addPath(clipPath)
    NSGraphicsContext.current!.cgContext.clip()

    sourceImage.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)

    NSGraphicsContext.restoreGraphicsState()

    guard let png = bmp.representation(using: .png, properties: [:]) else {
        fatalError("PNG conversion failed for size \(size)")
    }
    return png
}

// MARK: - Iconset layout

let iconSpecs: [(file: String, size: Int)] = [
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

// MARK: - Generate App Icon

print("Generating BlindSpot.icns from \(sourceDescription)…")

let iconsetDir = assetsDir.appendingPathComponent("BlindSpot.iconset")
try? fm.removeItem(at: iconsetDir)
try fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

var cache: [Int: Data] = [:]
for spec in iconSpecs {
    if cache[spec.size] == nil { cache[spec.size] = render(size: spec.size) }
    try cache[spec.size]!.write(to: iconsetDir.appendingPathComponent(spec.file))
    print("  ✓ \(spec.file)")
}

// Convert iconset → icns
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsPath]
try iconutil.run()
iconutil.waitUntilExit()

try? fm.removeItem(at: iconsetDir)

if iconutil.terminationStatus == 0 {
    print("  ✓ BlindSpot.icns created")
} else {
    fputs("Error: iconutil failed\n", stderr)
    exit(1)
}

// MARK: - Generate Menu Bar Template Icon
// Uses assets/menu-bar-icon.svg — a hand-crafted template with the four
// corner shapes + centered sparkle star. Edit that SVG to tweak the icon.

print("\nMenu bar template icon:")

let menuBarSvgPath = assetsDir.appendingPathComponent("menu-bar-icon.svg").path
if fm.fileExists(atPath: menuBarSvgPath),
   let mbImage = NSImage(contentsOfFile: menuBarSvgPath) {

    let sizes: [(file: String, px: Int)] = [
        ("menu-bar-icon@2x.png", 48),
        ("menu-bar-icon.png",    24),
    ]
    for s in sizes {
        guard let png = imgToPNG(mbImage, size: s.px) else {
            fputs("  ⚠ Failed to render \(s.file)\n", stderr)
            exit(1)
        }
        try png.write(to: assetsDir.appendingPathComponent(s.file))
    }

    if let pdf = createTemplatePDF(from: mbImage, size: NSSize(width: 24, height: 24)) {
        try pdf.write(to: assetsDir.appendingPathComponent("menu-bar-icon.pdf"))
    }

    // Copy to Resources
    let resourcesDir = repo.appendingPathComponent("Sources/BlindSpot/Resources")
    for file in ["menu-bar-icon.pdf", "menu-bar-icon.png", "menu-bar-icon@2x.png"] {
        let dest = resourcesDir.appendingPathComponent(file)
        try? fm.removeItem(at: dest)
        try? fm.copyItem(at: assetsDir.appendingPathComponent(file), to: dest)
    }

    print("  ✓ menu-bar-icon.pdf (24pt)")
    print("  ✓ menu-bar-icon.png (24px)")
    print("  ✓ menu-bar-icon@2x.png (48px)")
    print("  ✓ Copied to Sources/BlindSpot/Resources/")
} else {
    print("  ⚠ No assets/menu-bar-icon.svg — skipping menu bar icon")
}

print("\n✓ Icon generation complete")


// MARK: - Helpers

func imgToPNG(_ image: NSImage, size: Int) -> Data? {
    let bmp = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bmp)
    image.draw(in: CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size)),
               from: .zero, operation: .copy, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
    return bmp.representation(using: .png, properties: [:])
}

/// Creates a PDF data blob containing the template image at the given size.
func createTemplatePDF(from image: NSImage, size: NSSize) -> Data? {
    let pdfData = NSMutableData()
    var mediaBox = CGRect(origin: .zero, size: size)
    guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
          let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

    ctx.beginPDFPage(nil)
    NSGraphicsContext.saveGraphicsState()
    let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.current = nsCtx
    image.draw(in: mediaBox, from: .zero, operation: .copy, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
    ctx.endPDFPage()
    ctx.closePDF()

    return pdfData as Data
}
