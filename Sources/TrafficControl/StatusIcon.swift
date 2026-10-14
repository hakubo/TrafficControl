import AppKit

/// The menu bar glyph: the app icon's control tower as a solid silhouette that reads at 16–18pt.
enum StatusIcon {
    static let size = NSSize(width: 18, height: 18)

    /// The tower on an 18×18 grid (y up): tapered shaft, balcony, cab with a cut-out window band, roof and antenna.
    static func towerPath(offsetX: CGFloat = 0) -> NSBezierPath {
        let path = NSBezierPath()
        path.windingRule = .evenOdd
        func polygon(_ points: [(CGFloat, CGFloat)]) {
            path.move(to: NSPoint(x: points[0].0 + offsetX, y: points[0].1))
            for point in points.dropFirst() { path.line(to: NSPoint(x: point.0 + offsetX, y: point.1)) }
            path.close()
        }
        func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
            polygon([(x, y), (x + width, y), (x + width, y + height), (x, y + height)])
        }
        polygon([(6.5, 1), (11.5, 1), (10.5, 9), (7.5, 9)])  // shaft
        rect(5, 8.5, 8, 1.5)  // balcony
        polygon([(6, 10), (12, 10), (13.5, 13.5), (4.5, 13.5)])  // cab
        rect(3.5, 13.5, 11, 1.5)  // roof
        rect(8.25, 15, 1.5, 2.5)  // antenna
        // Window band, cut out of the cab.
        polygon([(6.5, 10.9), (11.5, 10.9), (12.25, 12.6), (5.75, 12.6)])
        return path
    }

    /// Template image: the menu bar colors it, and `contentTintColor` can tint it.
    static func template() -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()
            towerPath().fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "TrafficControl"
        return image
    }

    /// The tower in the menu bar's text color with an orange dot at the top right.
    /// Drawn at display time, so `labelColor` follows light and dark menu bars.
    static func withWarningDot(towerColor: NSColor = .labelColor, dotColor: NSColor = .systemOrange) -> NSImage {
        let image = NSImage(size: NSSize(width: size.width + 3, height: size.height), flipped: false) { rect in
            towerColor.setFill()
            // Nudged left so the roof clears the dot.
            towerPath(offsetX: -1.5).fill()
            let dot = NSRect(x: rect.maxX - 7, y: rect.maxY - 7, width: 7, height: 7)
            dotColor.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "TrafficControl isn't your default browser"
        return image
    }
}
