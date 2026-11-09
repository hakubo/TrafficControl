import Foundation
import Testing
@testable import TrafficControlCore

@Suite @MainActor struct LinkWorkQueueTests {
    @MainActor private final class Scheduler {
        let clock = Clock()
        var timers: [@Sendable () -> Void] = []
        var completed: (() -> Void)?
        lazy var worker = TabLookupWorker(
            now: { [clock] in clock.now },
            schedule: { [unowned self] _, action in timers.append(action) },
            didFinish: { [unowned self] in completed?() })

        func expire() { timers.removeFirst()() }
    }

    /// Only the simulated time crosses threads; all accesses are protected by the lock.
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var time = DispatchTime(uptimeNanoseconds: 1_000_000_000)
        var now: DispatchTime {
            lock.lock()
            defer { lock.unlock() }
            return time
        }
        func advance(to deadline: DispatchTime? = nil) {
            lock.lock()
            time = deadline ?? (time + 10)
            lock.unlock()
        }
    }

    @Test func suspendedJobsKeepArrivalOrderAndCanEnqueue() async {
        let queue = LinkWorkQueue()
        let scheduler = Scheduler()
        let worker = scheduler.worker
        let release = DispatchSemaphore(value: 0)
        var events: [Int] = []
        await withCheckedContinuation { started in
            queue.enqueue {
                events.append(1)
                let reused = await worker.run(timeout: 1) { attempt in
                    started.resume()
                    release.wait()
                    return attempt.commit()
                }
                #expect(reused)
                events.append(2)
                queue.enqueue { events.append(4) }
            }
        }
        await withCheckedContinuation { done in
            queue.enqueue {
                events.append(3)
                // A nested enqueue must remain behind work already reserved.
                queue.enqueue { done.resume() }
            }
            events.append(0)
            release.signal()
        }
        #expect(events == [1, 0, 2, 3, 4])
    }

    @Test func failureAndSuccessPropagateOffMainThread() async {
        let scheduler = Scheduler()
        let success = await scheduler.worker.run(timeout: 1) { attempt in
            #expect(!Thread.isMainThread)
            return attempt.commit()
        }
        let failure = await scheduler.worker.run(timeout: 1) { _ in false }
        #expect(success)
        #expect(!failure)
    }

    @Test func committedFocusSurvivesTimeoutAndLateDelivery() async {
        let scheduler = Scheduler()
        let worker = scheduler.worker
        let release = DispatchSemaphore(value: 0)
        var task: Task<Bool, Never>!
        await withCheckedContinuation { committed in
            task = Task {
                await worker.run(timeout: 1) { attempt in
                    #expect(attempt.commit())
                    committed.resume()
                    release.wait()
                    return true
                }
            }
        }
        scheduler.clock.advance()
        scheduler.expire()
        release.signal()
        #expect(await task.value)
    }

    @Test func committedFocusFailureFallsBack() async {
        let scheduler = Scheduler()
        let result = await scheduler.worker.run(timeout: 1) { attempt in
            #expect(attempt.commit())
            return false
        }
        #expect(!result)
    }

    @Test func timeoutSkipsFocusAndQueuedLinksFailFastUntilRecovery() async {
        let scheduler = Scheduler()
        let worker = scheduler.worker
        let queue = LinkWorkQueue()
        let release = DispatchSemaphore(value: 0)
        var events: [Int] = []
        await withCheckedContinuation { started in
            queue.enqueue {
                let reused = await worker.run(timeout: 1) { attempt in
                    started.resume()
                    release.wait()
                    #expect(!attempt.commit(), "A late lookup must never start focus")
                    return false
                }
                if !reused { events.append(0) }
            }
        }
        await withCheckedContinuation { done in
            for index in 1...5 {
                queue.enqueue {
                    let reused = await worker.run(timeout: 1) { _ in
                        Issue.record("A stuck worker must reject subsequent lookups")
                        return true
                    }
                    if !reused { events.append(index) }
                }
            }
            queue.enqueue { done.resume() }
            scheduler.expire()
        }
        #expect(events == [0, 1, 2, 3, 4, 5])
        #expect(scheduler.timers.isEmpty, "Fail-fast links must not schedule another timeout")
        await withCheckedContinuation { finished in
            scheduler.completed = { finished.resume() }
            release.signal()
        }
        scheduler.completed = nil
        #expect(await worker.run(timeout: 1) { $0.commit() })
    }

    @Test func resultAtDeadlineCannotCommitEvenBeforeTimerDelivery() async {
        let scheduler = Scheduler()
        let clock = scheduler.clock
        let result = await scheduler.worker.run(timeout: 1) { attempt in
            clock.advance(to: attempt.deadline)
            #expect(!attempt.commit())
            return false
        }
        #expect(!result)
    }
}
