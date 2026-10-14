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
/// A control tower on a radar scope: flat white tower, amber-lit cab, sweep and range rings behind it.
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
    /// Fills a polygon with softly rounded corners by stroking it in the same paint.
    func fillRounded(_ path: CGPath, radius: CGFloat, _ paint: () -> Void) {
        let rounded = path.copy(strokingWithWidth: radius * 2, lineCap: .round, lineJoin: .round, miterLimit: 1)
        for shape in [path, rounded] {
            ctx.saveGState()
            ctx.addPath(shape)
            ctx.clip()
            paint()
            ctx.restoreGState()
        }
    }

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.4).cgColor)
    ctx.addPath(bodyPath)
    ctx.setFillColor(color(0x0E1A33).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()

    // Scope background.
    ctx.drawLinearGradient(
        gradient([color(0x22386A), color(0x0B1428)], [0, 1]),
        start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // Radar centred on the cab: range rings, then a sweep fading behind its leading edge.
    let center = CGPoint(x: 512, y: 640)
    ctx.setLineWidth(5)
    for radius in stride(from: 130.0, through: 560, by: 130) {
        ctx.setStrokeColor(color(0xFFFFFF, 0.07).cgColor)
        ctx.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
    let lead = CGFloat.pi * 0.28
    let span = CGFloat.pi * 0.42
    let slices = 60
    for i in 0..<slices {
        let t = CGFloat(i) / CGFloat(slices)
        let a0 = lead - span * (1 - t)
        let a1 = lead - span * (1 - t - 1 / CGFloat(slices)) + 0.012
        ctx.move(to: center)
        ctx.addArc(center: center, radius: 620, startAngle: a0, endAngle: a1, clockwise: false)
        ctx.closePath()
        ctx.setFillColor(color(0xFFB547, 0.5 * pow(t, 1.6)).cgColor)
        ctx.fillPath()
    }
    ctx.setStrokeColor(color(0xFFC86B, 0.9).cgColor)
    ctx.setLineWidth(7)
    ctx.setLineCap(.round)
    ctx.move(to: center)
    ctx.addLine(to: CGPoint(x: center.x + cos(lead) * 620, y: center.y + sin(lead) * 620))
    ctx.strokePath()

    // Blips the sweep just passed.
    for (x, y, r, a) in [(742.0, 790.0, 13.0, 0.95), (668, 862, 9, 0.6), (812, 700, 9, 0.75)] {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 18, color: color(0xFFC86B, 0.9).cgColor)
        ctx.setFillColor(color(0xFFD48A, a).cgColor)
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        ctx.restoreGState()
    }

    // Tower: one white silhouette with a soft vertical shade.
    let white = { ctx.drawLinearGradient(
        gradient([color(0xFFFFFF), color(0xD5DDEA)], [0, 1]),
        start: CGPoint(x: 512, y: 760), end: CGPoint(x: 512, y: 100), options: [.drawsAfterEndLocation, .drawsBeforeStartLocation]) }

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 36, color: color(0x000000, 0.45).cgColor)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    fillRounded(polygon([CGPoint(x: 432, y: 60), CGPoint(x: 592, y: 60), CGPoint(x: 560, y: 560), CGPoint(x: 464, y: 560)]), radius: 6, white)
    fillRounded(polygon([CGPoint(x: 388, y: 548), CGPoint(x: 636, y: 548), CGPoint(x: 636, y: 588), CGPoint(x: 388, y: 588)]), radius: 14, white)
    fillRounded(polygon([CGPoint(x: 336, y: 708), CGPoint(x: 688, y: 708), CGPoint(x: 688, y: 752), CGPoint(x: 336, y: 752)]), radius: 16, white)
    fillRounded(polygon([CGPoint(x: 468, y: 748), CGPoint(x: 556, y: 748), CGPoint(x: 546, y: 790), CGPoint(x: 478, y: 790)]), radius: 6, white)
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // Lit cab glass between balcony and roof.
    let cab = polygon([CGPoint(x: 402, y: 588), CGPoint(x: 622, y: 588), CGPoint(x: 668, y: 708), CGPoint(x: 356, y: 708)])
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 60, color: color(0xFFB547, 0.7).cgColor)
    fillRounded(cab, radius: 4) {
        ctx.drawLinearGradient(
            gradient([color(0xFFD27A), color(0xF08A24)], [0, 1]),
            start: CGPoint(x: 512, y: 708), end: CGPoint(x: 512, y: 588), options: [])
    }
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(cab)
    ctx.clip()
    ctx.setStrokeColor(color(0x0E1A33, 0.55).cgColor)
    ctx.setLineWidth(14)
    for (bottomX, topX) in [(475.0, 460.0), (549, 564)] {
        ctx.move(to: CGPoint(x: bottomX, y: 588))
        ctx.addLine(to: CGPoint(x: topX, y: 708))
        ctx.strokePath()
    }
    ctx.restoreGState()

    // Antenna and beacon.
    ctx.setStrokeColor(color(0xE6ECF5).cgColor)
    ctx.setLineWidth(12)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: 512, y: 788))
    ctx.addLine(to: CGPoint(x: 512, y: 846))
    ctx.strokePath()
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 30, color: color(0xFF5A4E, 0.95).cgColor)
    ctx.setFillColor(color(0xFF5A4E).cgColor)
    ctx.fillEllipse(in: CGRect(x: 494, y: 840, width: 36, height: 36))
    ctx.restoreGState()

    // Glass highlight along the top edge of the body.
    ctx.drawLinearGradient(
        gradient([color(0xFFFFFF, 0.14), color(0xFFFFFF, 0)], [0, 1]),
        start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 760), options: [])
    ctx.restoreGState()
    ctx.addPath(bodyPath)
    ctx.setStrokeColor(color(0xFFFFFF, 0.12).cgColor)
    ctx.setLineWidth(3)
    ctx.strokePath()
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
