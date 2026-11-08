import Foundation

/// Keeps link decisions in arrival order, including while an earlier lookup is suspended.
@MainActor
public final class LinkWorkQueue {
    private var jobs: [@MainActor () async -> Void] = []
    private var running = false

    public init() {}

    public func enqueue(_ job: @escaping @MainActor () async -> Void) {
        jobs.append(job)
        guard !running else { return }
        running = true
        Task {
            while !jobs.isEmpty {
                await jobs.removeFirst()()
            }
            running = false
        }
    }
}

/// Serializes blocking lookups. After a timeout, callers fail fast until the worker returns.
@MainActor
public final class TabLookupWorker {
    private let queue = DispatchQueue(label: "TrafficControl.TabLookup", qos: .userInitiated)
    private var running = false
    private let schedule: (DispatchTime, @escaping @Sendable () -> Void) -> Void
    private let now: @Sendable () -> DispatchTime
    private let didFinish: () -> Void

    public convenience init() {
        self.init(
            now: { .now() },
            schedule: { deadline, action in
                DispatchQueue.main.asyncAfter(deadline: deadline, execute: action)
            })
    }

    // Injected scheduling lets tests order timeout, commit and completion without sleeping.
    init(
        now: @escaping @Sendable () -> DispatchTime,
        schedule: @escaping (DispatchTime, @escaping @Sendable () -> Void) -> Void,
        didFinish: @escaping () -> Void = {}
    ) {
        self.now = now
        self.schedule = schedule
        self.didFinish = didFinish
    }

    public func run(timeout: TimeInterval, operation: @escaping @Sendable (Attempt) -> Bool) async -> Bool {
        guard !running else { return false }
        running = true
        let deadline = now() + timeout
        return await withCheckedContinuation { continuation in
            let attempt = Attempt(deadline: deadline, now: now, continuation: continuation)
            schedule(deadline) { attempt.timeOut() }
            queue.async {
                let reused = attempt.isPending && operation(attempt)
                DispatchQueue.main.async {
                    self.running = false
                    attempt.finish(reused)
                    self.didFinish()
                }
            }
        }
    }

    /// State and continuation are protected by the lock, including the worker/timeout race.
    public final class Attempt: @unchecked Sendable {
        public let deadline: DispatchTime
        private enum State { case pending, committed, timedOut }
        private var state = State.pending
        private let lock = NSLock()
        private let now: @Sendable () -> DispatchTime
        private var continuation: CheckedContinuation<Bool, Never>?

        fileprivate init(
            deadline: DispatchTime, now: @escaping @Sendable () -> DispatchTime,
            continuation: CheckedContinuation<Bool, Never>
        ) {
            self.deadline = deadline
            self.now = now
            self.continuation = continuation
        }

        fileprivate var isPending: Bool {
            lock.lock()
            defer { lock.unlock() }
            return state == .pending && now() < deadline
        }

        /// Call immediately before focus. Once committed, the caller awaits its bounded result.
        public func commit() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard state == .pending, now() < deadline else { return false }
            state = .committed
            return true
        }

        fileprivate func timeOut() {
            lock.lock()
            guard state == .pending else { lock.unlock(); return }
            state = .timedOut
            let reply = continuation
            continuation = nil
            lock.unlock()
            reply?.resume(returning: false)
        }

        fileprivate func finish(_ value: Bool) {
            lock.lock()
            let reply = continuation
            continuation = nil
            lock.unlock()
            reply?.resume(returning: value)
        }
    }
}
