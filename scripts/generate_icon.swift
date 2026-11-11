#!/usr/bin/env swift

import AppKit
import Foundation

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext
    let margin = size * 0.09
    let rect = CGRect(x: margin, y: margin, width: size - margin * 2, height: size - margin * 2)
    let radius = size * 0.225

    ctx.saveGState()
    let clipPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(clipPath)
    ctx.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        CGColor(red: 0.04, green: 0.14, blue: 0.07, alpha: 1.0),
        CGColor(red: 0.09, green: 0.29, blue: 0.12, alpha: 1.0),
        CGColor(red: 0.24, green: 0.52, blue: 0.16, alpha: 1.0)
    ] as CFArray
    let locations: [CGFloat] = [0.0, 0.58, 1.0]
    let grad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: locations)!
    ctx.drawLinearGradient(
        grad,
        start: CGPoint(x: size * 0.5, y: margin),
        end: CGPoint(x: size * 0.5, y: size - margin),
        options: []
    )

    let bokehSpecs: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (0.32, 0.72, 0.075, 0.26),
        (0.71, 0.68, 0.055, 0.34),
        (0.56, 0.79, 0.040, 0.22)
    ]
    for (bx, by, br, ba) in bokehSpecs {
        ctx.setFillColor(CGColor(red: 0.92, green: 0.98, blue: 0.78, alpha: ba))
        let r = size * br
        ctx.fillEllipse(in: CGRect(x: size * bx - r, y: size * by - r, width: r * 2, height: r * 2))
    }

    let blades: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (0.26, 0.14, 0.36, 0.64, 0.040, 0.65),
        (0.37, 0.12, 0.54, 0.74, 0.048, 0.92),
        (0.49, 0.11, 0.69, 0.70, 0.046, 0.98),
        (0.61, 0.13, 0.79, 0.58, 0.038, 0.78),
        (0.70, 0.14, 0.84, 0.46, 0.032, 0.58)
    ]

    for (x0, y0, x1, y1, widthFrac, lum) in blades {
        let path = NSBezierPath()
        let p0 = NSPoint(x: size * x0, y: size * y0)
        let p3 = NSPoint(x: size * x1, y: size * y1)
        let w = size * widthFrac
        let c1 = NSPoint(x: size * (x0 + (x1 - x0) * 0.18), y: size * (y0 + (y1 - y0) * 0.58))
        let c2 = NSPoint(x: size * (x0 + (x1 - x0) * 0.55), y: size * (y0 + (y1 - y0) * 0.90))

        path.move(to: NSPoint(x: p0.x - w * 0.5, y: p0.y))
        path.curve(to: p3, controlPoint1: NSPoint(x: c1.x - w * 0.35, y: c1.y), controlPoint2: c2)
        path.curve(
            to: NSPoint(x: p0.x + w * 0.5, y: p0.y),
            controlPoint1: NSPoint(x: c2.x + w * 0.18, y: c2.y - w * 0.18),
            controlPoint2: NSPoint(x: c1.x + w * 0.35, y: c1.y - w * 0.1)
        )
        path.close()

        NSColor(
            calibratedRed: 0.42 * lum + 0.12,
            green: 0.78 * lum + 0.16,
            blue: 0.18 * lum + 0.06,
            alpha: 0.96
        ).setFill()
        path.fill()
    }

    let flowerCenter = CGPoint(x: size * 0.66, y: size * 0.66)
    let fR = size * 0.036
    ctx.setFillColor(CGColor(red: 0.99, green: 0.99, blue: 0.95, alpha: 0.96))
    for i in 0..<6 {
        let a = CGFloat(i) * (.pi / 3.0)
        let px = flowerCenter.x + cos(a) * fR * 1.15
        let py = flowerCenter.y + sin(a) * fR * 1.15
        ctx.fillEllipse(in: CGRect(x: px - fR * 0.62, y: py - fR * 0.62, width: fR * 1.24, height: fR * 1.24))
    }
    ctx.setFillColor(CGColor(red: 0.96, green: 0.78, blue: 0.20, alpha: 1.0))
    ctx.fillEllipse(in: CGRect(x: flowerCenter.x - fR * 0.52, y: flowerCenter.y - fR * 0.52, width: fR * 1.04, height: fR * 1.04))

    ctx.restoreGState()
    ctx.setStrokeColor(CGColor(red: 0.75, green: 0.95, blue: 0.62, alpha: 0.22))
    ctx.setLineWidth(max(1.0, size * 0.012))
    ctx.addPath(clipPath)
    ctx.strokePath()

    image.unlockFocus()
    return image
}

func pngData(from image: NSImage, size: CGFloat) -> Data? {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size),
        pixelsHigh: Int(size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("Usage: generate_icon.swift <output-dir>\n", stderr)
    exit(1)
}

let outDir = args[1]
let fm = FileManager.default
let sizes: [(Int, String)] = [
    (16, "icon_16x16"),
    (32, "icon_16x16@2x"),
    (32, "icon_32x32"),
    (64, "icon_32x32@2x"),
    (128, "icon_128x128"),
    (256, "icon_128x128@2x"),
    (256, "icon_256x256"),
    (512, "icon_256x256@2x"),
    (512, "icon_512x512"),
    (1024, "icon_512x512@2x")
]

let iconsetDir = "\(outDir)/AppIcon.iconset"
try? fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

for (px, name) in sizes {
    let img = drawIcon(size: CGFloat(px))
    let data = pngData(from: img, size: CGFloat(px))!
    try! data.write(to: URL(fileURLWithPath: "\(iconsetDir)/\(name).png"))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconsetDir, "-o", "\(outDir)/AppIcon.icns"]
try! task.run()
task.waitUntilExit()

if task.terminationStatus == 0 {
    try? fm.removeItem(atPath: iconsetDir)
} else {
    fputs("iconutil failed\n", stderr)
    exit(1)
}
