import Foundation

/// Coalesces bursts of values into one write on a serial background queue.
///
/// `submit` only records the latest value and returns; the write happens `delay` after the last
/// submit, so a burst (typing in a text field) produces a single write of its final value. Values are
/// taken and written on one serial queue, so an older value can never land after a newer one.
public final class CoalescingWriter<Value: Sendable>: @unchecked Sendable {
    private let delay: DispatchTimeInterval
    private let queue: DispatchQueue
    private let write: @Sendable (Value) -> Void
    private let lock = NSLock()
    private var pending: Value?
    /// Bumped on every submit; a scheduled write only runs if no newer submit has come in since.
    private var generation = 0

    public init(label: String, delay: DispatchTimeInterval, write: @escaping @Sendable (Value) -> Void) {
        self.delay = delay
        self.queue = DispatchQueue(label: label, qos: .utility)
        self.write = write
    }

    /// Records `value` as the next one to write, replacing any value still waiting.
    public func submit(_ value: Value) {
        let scheduled = lock.withLock {
            pending = value
            generation += 1
            return generation
        }
        queue.asyncAfter(deadline: .now() + delay) { [self] in
            if let value = takePending(onlyIf: scheduled) { write(value) }
        }
    }

    /// Writes any waiting value now and returns once it, and any write already running, is on disk.
    /// Call when the app quits.
    public func flush() {
        queue.sync {
            if let value = takePending(onlyIf: nil) { write(value) }
        }
    }

    private func takePending(onlyIf scheduled: Int?) -> Value? {
        lock.withLock {
            guard scheduled == nil || scheduled == generation, let value = pending else { return nil }
            pending = nil
            return value
        }
    }
}
