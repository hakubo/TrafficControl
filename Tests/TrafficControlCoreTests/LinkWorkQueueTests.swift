import Foundation
import Testing
@testable import TrafficControlCore

@Suite @MainActor struct LinkWorkQueueTests {
    @Test func suspendedJobsKeepArrivalOrder() async {
        let queue = LinkWorkQueue()
        let worker = TabLookupWorker()
        let release = DispatchSemaphore(value: 0)
        var events: [Int] = []
        await withCheckedContinuation { started in
            queue.enqueue {
                events.append(1)
                started.resume()
                let reused = await worker.run(timeout: 1) { _ in
                    release.wait()
                    return true
                }
                #expect(reused)
                events.append(2)
            }
        }
        await withCheckedContinuation { done in
            queue.enqueue {
                events.append(3)
                done.resume()
            }
            // The main actor stays available while the first job waits on Automation.
            events.append(0)
            release.signal()
        }
        #expect(events == [1, 0, 2, 3])
    }

    @Test func failureAndSuccessPropagateOffMainThread() async {
        let worker = TabLookupWorker()
        let success = await worker.run(timeout: 1) { _ in
            #expect(!Thread.isMainThread)
            return true
        }
        let failure = await worker.run(timeout: 1) { _ in false }
        #expect(success)
        #expect(!failure)
    }

    @Test func timeoutFallsBackOnceAndSkipsExpiredWork() async {
        let worker = TabLookupWorker()
        let release = DispatchSemaphore(value: 0)
        var opens = 0
        let first = await worker.run(timeout: 0.1) { _ in
            release.wait()
            return true  // A successful but late lookup must not complete again.
        }
        #expect(!first)
        if !first { opens += 1 }
        // The worker is still busy, but the next caller also has a bounded wait.
        let second = await worker.run(timeout: 0.1) { _ in
            Issue.record("Expired queued lookup must never execute")
            return true
        }
        #expect(!second)
        if !second { opens += 1 }
        release.signal()
        // Drain the serial worker to ensure the late reply and expired job were processed.
        let drained = await worker.run(timeout: 2) { _ in true }
        #expect(drained)
        #expect(opens == 2)
    }
}
