import Foundation
import os

/// Per-stage timings for routing a link, to find what delays a click. Compiled in only for debug builds
/// and `TIMING_LOGS=1 make app`; in release builds every call is a no-op. Read them with:
/// `/usr/bin/log stream --predicate 'subsystem == "io.github.hakubo.TrafficControl" && category == "timing"'`
enum Timing {
    #if DEBUG || TIMING_LOGS
        private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TrafficControl", category: "timing")
    #endif

    @inline(__always)
    static func measure<T>(_ label: @autoclosure () -> String, _ body: () throws -> T) rethrows -> T {
        #if DEBUG || TIMING_LOGS
            let start = ContinuousClock.now
            defer { report(label(), since: start) }
        #endif
        return try body()
    }

    @inline(__always)
    static func report(_ label: @autoclosure () -> String, since start: ContinuousClock.Instant) {
        #if DEBUG || TIMING_LOGS
            let ms = (ContinuousClock.now - start) / .milliseconds(1)
            let label = label()
            log.notice("\(label, privacy: .public): \(ms, format: .fixed(precision: 1), privacy: .public) ms")
        #endif
    }

    @inline(__always)
    static func note(_ message: @autoclosure () -> String) {
        #if DEBUG || TIMING_LOGS
            let message = message()
            log.notice("\(message, privacy: .public)")
        #endif
    }
}
