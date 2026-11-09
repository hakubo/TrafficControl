import Foundation
import Testing
@testable import TrafficControlCore

@Suite struct PointerGateTests {
    @Test func pointerAtItsOpeningPositionHasNotMoved() {
        var gate = PointerGate(origin: CGPoint(x: 100, y: 50))
        let moved = gate.moved(to: CGPoint(x: 100, y: 50))
        #expect(!moved)
        #expect(!gate.hasMoved)
    }

    @Test func anyDisplacementCountsAsMoved() {
        var gate = PointerGate(origin: CGPoint(x: 100, y: 50))
        let moved = gate.moved(to: CGPoint(x: 101, y: 50))
        #expect(moved)
        #expect(gate.hasMoved)
    }

    @Test func movedStaysMovedEvenWhenPointerReturnsToOrigin() {
        var gate = PointerGate(origin: CGPoint(x: 100, y: 50))
        _ = gate.moved(to: CGPoint(x: 140, y: 50))
        let moved = gate.moved(to: CGPoint(x: 100, y: 50))
        #expect(moved)
    }
}
