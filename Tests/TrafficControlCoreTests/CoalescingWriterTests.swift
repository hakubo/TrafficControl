import Foundation
import Testing
@testable import TrafficControlCore

/// Records every write, safe to read from the test while the writer's queue appends.
private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int] = []
    func append(_ value: Int) { lock.withLock { values.append(value) } }
    var written: [Int] { lock.withLock { values } }
}

private func writer(delay: DispatchTimeInterval) -> (CoalescingWriter<Int>, Recorder) {
    let recorder = Recorder()
    let writer = CoalescingWriter<Int>(label: "test.coalescing-writer", delay: delay) {
        recorder.append($0)
        return true
    }
    return (writer, recorder)
}

@Suite struct CoalescingWriterTests {
    @Test func submitDoesNotWriteSynchronously() {
        let (w, r) = writer(delay: .seconds(60))
        w.submit(1)
        #expect(r.written.isEmpty)
    }

    @Test func burstIsWrittenOnceAfterTheDelay() async throws {
        let (w, r) = writer(delay: .milliseconds(50))
        for i in 1...20 { w.submit(i) }
        try await Task.sleep(for: .milliseconds(400))
        #expect(r.written == [20])
    }

    @Test func flushWritesThePendingValueOnce() {
        let (w, r) = writer(delay: .seconds(60))
        for i in 1...5 { w.submit(i) }
        w.flush()
        #expect(r.written == [5])
        w.flush()
        #expect(r.written == [5])
    }

    @Test func flushWithNothingPendingWritesNothing() {
        let (w, r) = writer(delay: .milliseconds(10))
        w.flush()
        #expect(r.written.isEmpty)
    }

    @Test func olderValueNeverLandsAfterNewer() async throws {
        let (w, r) = writer(delay: .milliseconds(50))
        w.submit(1)
        w.flush()
        w.submit(2)
        // The timer scheduled for 1 fires after 2 was submitted; it must not write 1 again or skip 2.
        try await Task.sleep(for: .milliseconds(400))
        #expect(r.written == [1, 2])
    }

    @Test func pendingValueSurvivesUntilFlushEvenWhenTimersAreSuperseded() async throws {
        let (w, r) = writer(delay: .milliseconds(20))
        w.submit(1)
        try await Task.sleep(for: .milliseconds(200))
        w.submit(2)
        w.submit(3)
        w.flush()
        try await Task.sleep(for: .milliseconds(200))
        #expect(r.written == [1, 3])
    }

    @Test func failedWriteStaysPendingForTheNextFlush() {
        let recorder = Recorder()
        let failing = Failing(times: 1)
        let w = CoalescingWriter<Int>(label: "test.coalescing-writer", delay: .seconds(60)) { value in
            guard !failing.next() else { return false }
            recorder.append(value)
            return true
        }
        w.submit(1)
        w.flush()
        #expect(recorder.written.isEmpty)
        w.flush()
        #expect(recorder.written == [1])
    }

    @Test func failedWriteNeverReplacesANewerValue() {
        let recorder = Recorder()
        let failing = Failing(times: 1)
        let w = CoalescingWriter<Int>(label: "test.coalescing-writer", delay: .seconds(60)) { value in
            guard !failing.next() else { return false }
            recorder.append(value)
            return true
        }
        w.submit(1)
        w.flush()
        w.submit(2)
        w.flush()
        #expect(recorder.written == [2])
    }
}

/// Fails the first `times` writes.
private final class Failing: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int
    init(times: Int) { remaining = times }
    func next() -> Bool {
        lock.withLock {
            defer { remaining -= 1 }
            return remaining > 0
        }
    }
}
