// Draws the app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift   (needs iconutil, which ships with macOS)
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Drawn on a 1024 grid (y up); the body follows the macOS icon template (824pt square, 100pt margin).
/// An air traffic control tower at dusk, its beacon sending out signals.
func drawIcon(in ctx: CGContext) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)
    func gradient(_ colors: [NSColor], _ locations: [CGFloat]) -> CGGradient {
        CGGradient(colorsSpace: space, colors: colors.map(\.cgColor) as CFArray, locations: locations)!
    }
    func polygon(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        return path
    }

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.35).cgColor)
    ctx.addPath(bodyPath)
    ctx.setFillColor(color(0x1B2A4A).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()

    // Dusk sky: deep blue overhead fading to a warm horizon.
    ctx.drawLinearGradient(
        gradient([color(0x16264A), color(0x2D4D86), color(0xF0925A)], [0, 0.55, 1]),
        start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 230), options: [.drawsAfterEndLocation])
    for (x, y, r) in [(220.0, 820.0, 5.0), (300, 700, 3.5), (760, 840, 4.5), (840, 720, 3.5), (690, 900, 3), (180, 640, 3)] {
        ctx.setFillColor(color(0xFFFFFF, 0.8).cgColor)
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    // Ground.
    ctx.setFillColor(color(0x0E1628).cgColor)
    ctx.fill(CGRect(x: 100, y: 100, width: 824, height: 132))

    // Signal waves either side of the beacon.
    let beacon = CGPoint(x: 512, y: 868)
    ctx.setLineCap(.round)
    for (radius, alpha) in [(70.0, 0.75), (120.0, 0.45), (170.0, 0.22)] {
        ctx.setStrokeColor(color(0x9BE7FF, alpha).cgColor)
        ctx.setLineWidth(16)
        for (start, end) in [(-0.45, 0.45), (Double.pi - 0.45, Double.pi + 0.45)] {
            ctx.addArc(center: beacon, radius: radius, startAngle: start, endAngle: end, clockwise: false)
            ctx.strokePath()
        }
    }

    // Shaft, lit from the left.
    let shaft = polygon([CGPoint(x: 418, y: 200), CGPoint(x: 606, y: 200), CGPoint(x: 572, y: 560), CGPoint(x: 452, y: 560)])
    ctx.saveGState()
    ctx.addPath(shaft)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([color(0xEEF2F8), color(0xB4C0D6)], [0, 1]),
        start: CGPoint(x: 418, y: 0), end: CGPoint(x: 606, y: 0), options: [])
    ctx.restoreGState()
    ctx.setFillColor(color(0x5B6B8C, 0.55).cgColor)
    for y in stride(from: 270.0, through: 500, by: 70) {
        ctx.fill(CGRect(x: 498, y: y, width: 28, height: 34))
    }

    // Base.
    ctx.setFillColor(color(0xC9D3E5).cgColor)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 360, y: 200, width: 304, height: 40), cornerWidth: 10, cornerHeight: 10, transform: nil))
    ctx.fillPath()

    // Balcony under the cab.
    ctx.setFillColor(color(0xE6ECF5).cgColor)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 384, y: 556, width: 256, height: 40), cornerWidth: 10, cornerHeight: 10, transform: nil))
    ctx.fillPath()

    // Glass cab, wider at the top, glowing from inside.
    let cab = polygon([CGPoint(x: 392, y: 596), CGPoint(x: 632, y: 596), CGPoint(x: 682, y: 748), CGPoint(x: 342, y: 748)])
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 50, color: color(0x6FE0FF, 0.55).cgColor)
    ctx.addPath(cab)
    ctx.setFillColor(color(0x3FB6E6).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(cab)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([color(0xA8F0FF), color(0x2A9FD8)], [0, 1]),
        start: CGPoint(x: 512, y: 748), end: CGPoint(x: 512, y: 596), options: [])
    // Window frames.
    ctx.setStrokeColor(color(0x123056, 0.85).cgColor)
    ctx.setLineWidth(12)
    for (bottomX, topX) in [(452.0, 427.0), (512, 512), (572, 597)] {
        ctx.move(to: CGPoint(x: bottomX, y: 596))
        ctx.addLine(to: CGPoint(x: topX, y: 748))
        ctx.strokePath()
    }
    ctx.restoreGState()

    // Roof, cap and antenna.
    ctx.setFillColor(color(0xE6ECF5).cgColor)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 326, y: 744, width: 372, height: 44), cornerWidth: 14, cornerHeight: 14, transform: nil))
    ctx.fillPath()
    ctx.setFillColor(color(0xC9D3E5).cgColor)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 452, y: 786, width: 120, height: 26), cornerWidth: 8, cornerHeight: 8, transform: nil))
    ctx.fillPath()
    ctx.setStrokeColor(color(0xC9D3E5).cgColor)
    ctx.setLineWidth(12)
    ctx.move(to: CGPoint(x: 512, y: 810))
    ctx.addLine(to: CGPoint(x: 512, y: beacon.y))
    ctx.strokePath()

    // Red beacon.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 40, color: color(0xFF453A, 0.95).cgColor)
    ctx.setFillColor(color(0xFF453A).cgColor)
    ctx.fillEllipse(in: CGRect(x: beacon.x - 24, y: beacon.y - 24, width: 48, height: 48))
    ctx.restoreGState()
    ctx.setFillColor(color(0xFFFFFF, 0.7).cgColor)
    ctx.fillEllipse(in: CGRect(x: beacon.x - 12, y: beacon.y + 2, width: 12, height: 12))

    ctx.restoreGState()
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    let ctx = graphics.cgContext
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    drawIcon(in: ctx)
    graphics.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try png(size: base).write(to: iconset.appending(path: "icon_\(base)x\(base).png"))
    try png(size: base * 2).write(to: iconset.appending(path: "icon_\(base)x\(base)@2x.png"))
}

let output = root.appending(path: "Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
try png(size: 512).write(to: root.appending(path: "docs/icon.png"))
print("Wrote \(output.path)")
