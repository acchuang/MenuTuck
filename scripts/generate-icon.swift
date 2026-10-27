#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

/// Renders the MenuTuck macOS app icon (Option C: macOS Tactile Graphite & Rounded Bar) at a given pixel dimension.
func renderIcon(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
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
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    cg.interpolationQuality = .high
    cg.setShouldAntialias(true)

    let s = CGFloat(size) / 1024.0
    cg.scaleBy(x: s, y: s)

    // 1. Apple HIG macOS squircle geometry (824x824 centered in 1024x1024 transparent canvas).
    let squircleRect = NSRect(x: 100, y: 100, width: 824, height: 824)
    let cornerRadius: CGFloat = 185.0
    let squirclePath = NSBezierPath(roundedRect: squircleRect, xRadius: cornerRadius, yRadius: cornerRadius)

    let black = NSColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
    let cutoutDark = NSColor(srgbRed: 0.08, green: 0.08, blue: 0.09, alpha: 1.0)
    let cream = NSColor(srgbRed: 244.0 / 255.0, green: 242.0 / 255.0, blue: 235.0 / 255.0, alpha: 1.0)

    // Outer ambient shadow (standard macOS Dock elevation)
    cg.saveGState()
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -24)
    shadow.shadowBlurRadius = 44
    shadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.42)
    shadow.set()
    black.setFill()
    squirclePath.fill()
    cg.restoreGState()

    // Clip to squircle
    cg.saveGState()
    squirclePath.addClip()

    // Subtle tactile dark graphite gradient for macOS Dock depth
    let bgGradient = NSGradient(
        starting: NSColor(srgbRed: 0.14, green: 0.14, blue: 0.16, alpha: 1.0),
        ending: NSColor(srgbRed: 0.03, green: 0.03, blue: 0.04, alpha: 1.0)
    )!
    bgGradient.draw(in: squircleRect, angle: -90)

    // Geometry constants
    let barRect = NSRect(x: 244.0, y: 393.5, width: 536.0, height: 99.0)
    let barTopY = barRect.maxY          // 492.5
    let barCenterY = barRect.midY       // 443.0
    let gap: CGFloat = 11.5             // Uniform separation / cutout stroke width
    let circleRadius: CGFloat = 71.5    // All three circular icons share the same radius

    // 2. Horizontal rounded menu bar strip
    cream.setFill()
    NSBezierPath(roundedRect: barRect, xRadius: 22.0, yRadius: 22.0).fill()

    // 3. Left circle (fully above the bar, separated by `gap`)
    let leftCenter = NSPoint(x: 341.5, y: barTopY + gap + circleRadius)
    let leftRect = NSRect(
        x: leftCenter.x - circleRadius,
        y: leftCenter.y - circleRadius,
        width: circleRadius * 2,
        height: circleRadius * 2
    )
    cream.setFill()
    NSBezierPath(ovalIn: leftRect).fill()

    // 4. Right circle dome (tucked behind the bar, clipped cleanly at `barTopY + gap`)
    let rightCenter = NSPoint(x: 682.5, y: 486.3)
    let rightRect = NSRect(
        x: rightCenter.x - circleRadius,
        y: rightCenter.y - circleRadius,
        width: circleRadius * 2,
        height: circleRadius * 2
    )
    cg.saveGState()
    NSRect(x: 100, y: barTopY + gap, width: 824, height: 500).clip()
    cream.setFill()
    NSBezierPath(ovalIn: rightRect).fill()
    cg.restoreGState()

    // 5. Middle circle (half-tucked overlapping the bar with a clean cutout ring)
    let midCenter = NSPoint(x: 512.0, y: 522.0)
    let midOuterRadius = circleRadius + gap
    let midOuterRect = NSRect(
        x: midCenter.x - midOuterRadius,
        y: midCenter.y - midOuterRadius,
        width: midOuterRadius * 2,
        height: midOuterRadius * 2
    )
    cutoutDark.setFill()
    NSBezierPath(ovalIn: midOuterRect).fill()

    let midInnerRect = NSRect(
        x: midCenter.x - circleRadius,
        y: midCenter.y - circleRadius,
        width: circleRadius * 2,
        height: circleRadius * 2
    )
    cream.setFill()
    NSBezierPath(ovalIn: midInnerRect).fill()

    // 6. Right-pointing rounded chevron `>` inside the right side of the bar
    let chevron = NSBezierPath()
    chevron.move(to: NSPoint(x: 678.3, y: barCenterY + 30.0))
    chevron.line(to: NSPoint(x: 708.3, y: barCenterY))
    chevron.line(to: NSPoint(x: 678.3, y: barCenterY - 30.0))
    chevron.lineCapStyle = .round
    chevron.lineJoinStyle = .round
    chevron.lineWidth = 16.0
    cutoutDark.setStroke()
    chevron.stroke()

    // Inner specular border
    NSColor(calibratedWhite: 1.0, alpha: 0.18).setStroke()
    squirclePath.lineWidth = 3.0
    squirclePath.stroke()

    cg.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
let rootDir = URL(fileURLWithPath: fm.currentDirectoryPath)
let resourcesDir = rootDir.appendingPathComponent("Resources", isDirectory: true)
let iconsetDir = resourcesDir.appendingPathComponent("AppIcon.iconset", isDirectory: true)

try? fm.removeItem(at: iconsetDir)
try fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let specs: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for spec in specs {
    let rep = renderIcon(size: spec.pixels)
    let pngData = rep.representation(using: .png, properties: [:])!
    let fileURL = iconsetDir.appendingPathComponent(spec.name)
    try pngData.write(to: fileURL)
    if spec.pixels == 1024 {
        try pngData.write(to: resourcesDir.appendingPathComponent("AppIcon-1024.png"))
    }
}

let icnsURL = resourcesDir.appendingPathComponent("AppIcon.icns")
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsURL.path]
try proc.run()
proc.waitUntilExit()
try? fm.removeItem(at: iconsetDir)

guard proc.terminationStatus == 0 else {
    fputs("iconutil failed with status \(proc.terminationStatus)\n", stderr)
    exit(1)
}
print("Generated \(icnsURL.path)")
