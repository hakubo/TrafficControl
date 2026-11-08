import CoreGraphics
import Foundation

/// Tells a pointer that merely rests where the picker opened from one that has really moved.
///
/// The picker opens centred on the pointer, so a tile is usually already "hovered" before the user
/// touched anything. That hover must not override the preselected browser; only a moved pointer may.
public struct PointerGate: Sendable {
    private let origin: CGPoint
    public private(set) var hasMoved = false

    public init(origin: CGPoint) {
        self.origin = origin
    }

    /// Whether the pointer, now at `location`, counts as moved. Once it has, it stays moved.
    public mutating func moved(to location: CGPoint) -> Bool {
        if location != origin { hasMoved = true }
        return hasMoved
    }
}
