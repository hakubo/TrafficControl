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

/// Serializes blocking work without making a caller wait indefinitely for it.
/// Expired queued work is skipped; a late result can never complete a request twice.
@MainActor
public final class TabLookupWorker {
    private let queue = DispatchQueue(label: "TrafficControl.TabLookup", qos: .userInitiated)

    public init() {}

    public func run(timeout: TimeInterval, operation: @escaping @Sendable (DispatchTime) -> Bool) async -> Bool {
        let deadline = DispatchTime.now() + timeout
        return await withCheckedContinuation { continuation in
            let result = ResultOnce(continuation)
            DispatchQueue.main.asyncAfter(deadline: deadline) { result.finish(false) }
            queue.async {
                let reused = DispatchTime.now() < deadline && operation(deadline)
                DispatchQueue.main.async {
                    result.finish(DispatchTime.now() < deadline && reused)
                }
            }
        }
    }

    /// Accessed only on the main actor, including the timeout and worker callbacks.
    @MainActor
    private final class ResultOnce {
        private var continuation: CheckedContinuation<Bool, Never>?

        init(_ continuation: CheckedContinuation<Bool, Never>) {
            self.continuation = continuation
        }

        func finish(_ value: Bool) {
            continuation?.resume(returning: value)
            continuation = nil
        }
    }
}
