#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

/// Renders the MenuTuck macOS app icon at a given pixel dimension.
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
    let s = CGFloat(size) / 1024.0
    cg.scaleBy(x: s, y: s)

    // 1. Apple HIG macOS squircle geometry (824x824 centered in 1024x1024).
    let squircleRect = NSRect(x: 100, y: 100, width: 824, height: 824)
    let cornerRadius: CGFloat = 185.0
    let squirclePath = NSBezierPath(roundedRect: squircleRect, xRadius: cornerRadius, yRadius: cornerRadius)

    // Outer ambient shadow
    cg.saveGState()
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -26)
    shadow.shadowBlurRadius = 48
    shadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.48)
    shadow.set()
    NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.14, alpha: 1.0).setFill()
    squirclePath.fill()
    cg.restoreGState()

    // Clip to squircle
    cg.saveGState()
    squirclePath.addClip()

    // 2. Background gradient: deep midnight slate to rich indigo-navy
    let bgGradient = NSGradient(colorsAndLocations:
        (NSColor(calibratedRed: 0.06, green: 0.08, blue: 0.14, alpha: 1.0), 0.0),
        (NSColor(calibratedRed: 0.09, green: 0.13, blue: 0.22, alpha: 1.0), 0.55),
        (NSColor(calibratedRed: 0.13, green: 0.20, blue: 0.34, alpha: 1.0), 1.0)
    )!
    bgGradient.draw(in: squircleRect, angle: 115)

    // Subtle radial cyan glow behind the divider/chevron focal point
    let glowCenter = NSPoint(x: 520, y: 540)
    let glowGradient = NSGradient(
        starting: NSColor(calibratedRed: 0.20, green: 0.78, blue: 0.96, alpha: 0.28),
        ending: NSColor(calibratedRed: 0.20, green: 0.78, blue: 0.96, alpha: 0.0)
    )!
    glowGradient.draw(fromCenter: glowCenter, radius: 10, toCenter: glowCenter, radius: 380, options: [])

    // 3. Elevated translucent macOS menu bar strip across the icon
    let barRect = NSRect(x: 156, y: 404, width: 712, height: 216)
    let barPath = NSBezierPath(roundedRect: barRect, xRadius: 56, yRadius: 56)

    cg.saveGState()
    let barShadow = NSShadow()
    barShadow.shadowOffset = NSSize(width: 0, height: -18)
    barShadow.shadowBlurRadius = 36
    barShadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.45)
    barShadow.set()
    NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.26, alpha: 0.92).setFill()
    barPath.fill()
    cg.restoreGState()

    // Glass fill on the menu bar pill
    let barGlass = NSGradient(colorsAndLocations:
        (NSColor(calibratedWhite: 1.0, alpha: 0.16), 0.0),
        (NSColor(calibratedWhite: 1.0, alpha: 0.06), 1.0)
    )!
    barGlass.draw(in: barPath, angle: -90)

    // Left (tucked/hidden) zone tint inside the bar
    cg.saveGState()
    barPath.addClip()
    let hiddenZoneRect = NSRect(x: 156, y: 404, width: 334, height: 216)
    NSColor(calibratedRed: 0.04, green: 0.06, blue: 0.11, alpha: 0.48).setFill()
    hiddenZoneRect.fill()
    cg.restoreGState()

    // Subtle glass border on the menu bar pill
    NSColor(calibratedWhite: 1.0, alpha: 0.22).setStroke()
    barPath.lineWidth = 3.0
    barPath.stroke()

    // 4. Left side: "Tucked / Hidden" ghost icons (faded & dashed to show they are hidden)
    let ghostColor = NSColor(calibratedRed: 0.56, green: 0.68, blue: 0.86, alpha: 0.34)
    ghostColor.setFill()
    ghostColor.setStroke()

    // Ghost icon 1: circle with inner dot
    let ghost1 = NSRect(x: 212, y: 476, width: 72, height: 72)
    let ghost1Path = NSBezierPath(ovalIn: ghost1)
    ghost1Path.lineWidth = 5.0
    let dashPattern: [CGFloat] = [10.0, 7.0]
    ghost1Path.setLineDash(dashPattern, count: 2, phase: 0)
    ghost1Path.stroke()
    NSBezierPath(ovalIn: ghost1.insetBy(dx: 22, dy: 22)).fill()

    // Ghost icon 2: rounded square app tile (semi-faded, sliding behind divider)
    let ghost2 = NSRect(x: 324, y: 476, width: 72, height: 72)
    let ghost2Path = NSBezierPath(roundedRect: ghost2, xRadius: 18, yRadius: 18)
    NSColor(calibratedRed: 0.56, green: 0.68, blue: 0.86, alpha: 0.22).setFill()
    ghost2Path.fill()
    ghost2Path.lineWidth = 5.0
    ghost2Path.setLineDash(dashPattern, count: 2, phase: 0)
    ghostColor.setStroke()
    ghost2Path.stroke()

    // 5. Center focal element: Glowing cyan/sky divider bar `|` + chevron pill `‹`
    let dividerX: CGFloat = 466
    let dividerRect = NSRect(x: dividerX - 8, y: 364, width: 16, height: 296)
    let dividerPath = NSBezierPath(roundedRect: dividerRect, xRadius: 8, yRadius: 8)

    cg.saveGState()
    let divGlow = NSShadow()
    divGlow.shadowOffset = .zero
    divGlow.shadowBlurRadius = 24
    divGlow.shadowColor = NSColor(calibratedRed: 0.22, green: 0.84, blue: 1.0, alpha: 0.85)
    divGlow.set()
    let divGrad = NSGradient(
        starting: NSColor(calibratedRed: 0.42, green: 0.93, blue: 1.0, alpha: 1.0),
        ending: NSColor(calibratedRed: 0.16, green: 0.64, blue: 0.98, alpha: 1.0)
    )!
    divGrad.draw(in: dividerPath, angle: -90)
    cg.restoreGState()

    // Highlighted toggle chevron badge `<` next to the divider
    let badgeRect = NSRect(x: 508, y: 444, width: 136, height: 136)
    let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 36, yRadius: 36)
    let badgeGrad = NSGradient(
        starting: NSColor(calibratedRed: 0.24, green: 0.82, blue: 0.98, alpha: 1.0),
        ending: NSColor(calibratedRed: 0.14, green: 0.52, blue: 0.94, alpha: 1.0)
    )!
    cg.saveGState()
    let badgeShadow = NSShadow()
    badgeShadow.shadowOffset = NSSize(width: 0, height: -10)
    badgeShadow.shadowBlurRadius = 22
    badgeShadow.shadowColor = NSColor(calibratedRed: 0.08, green: 0.42, blue: 0.88, alpha: 0.55)
    badgeShadow.set()
    badgeGrad.draw(in: badgePath, angle: -90)
    cg.restoreGState()

    // Crisp white left-pointing chevron `<` inside the badge
    let chev = NSBezierPath()
    chev.move(to: NSPoint(x: 592, y: 548))
    chev.line(to: NSPoint(x: 554, y: 512))
    chev.line(to: NSPoint(x: 592, y: 476))
    chev.lineCapStyle = .round
    chev.lineJoinStyle = .round
    chev.lineWidth = 16.0
    NSColor.white.setStroke()
    chev.stroke()

    // 6. Right side: Crisp visible status item sliders/icons
    let activeWhite = NSColor(calibratedWhite: 0.98, alpha: 0.95)
    activeWhite.setFill()
    activeWhite.setStroke()

    // Visible status icon: two clean Control-Center style toggle pills
    let pillTop = NSRect(x: 688, y: 522, width: 118, height: 36)
    let pillBot = NSRect(x: 688, y: 466, width: 118, height: 36)
    NSColor(calibratedWhite: 1.0, alpha: 0.22).setFill()
    NSBezierPath(roundedRect: pillTop, xRadius: 18, yRadius: 18).fill()
    NSBezierPath(roundedRect: pillBot, xRadius: 18, yRadius: 18).fill()

    activeWhite.setFill()
    NSBezierPath(ovalIn: NSRect(x: 772, y: 525, width: 30, height: 30)).fill()
    NSBezierPath(ovalIn: NSRect(x: 692, y: 469, width: 30, height: 30)).fill()

    // 7. Subtle top-bottom section indicator pills for visual balance
    let topIndicator = NSRect(x: 412, y: 720, width: 200, height: 14)
    NSColor(calibratedWhite: 1.0, alpha: 0.14).setFill()
    NSBezierPath(roundedRect: topIndicator, xRadius: 7, yRadius: 7).fill()

    // Inner squircle specular border
    NSColor(calibratedWhite: 1.0, alpha: 0.18).setStroke()
    squirclePath.lineWidth = 4.0
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
