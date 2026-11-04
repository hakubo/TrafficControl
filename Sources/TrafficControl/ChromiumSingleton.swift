import Darwin
import Foundation
import TrafficControlCore

/// Hands links to a running Chromium browser the way a second launch of the browser would, by writing its
/// command line to the browser's `SingletonSocket`, but without starting a process. Starting the browser's
/// executable costs ~100 ms, and seconds once the browser has updated itself on disk without a relaunch:
/// the new executable then loads a framework the running browser doesn't share, often from disk.
enum ChromiumSingleton {
    /// Long enough for a busy browser to answer, short enough that a stuck one doesn't hold up the link.
    private static let timeout = timeval(tv_sec: 1, tv_usec: 0)

    /// Hand-offs run one at a time, so links clicked in quick succession reach the browser in click order.
    static let queue = DispatchQueue(label: "TrafficControl.ChromiumSingleton", qos: .userInteractive)

    /// Blocks until the browser answers or `timeout` passes, so call it on `queue`.
    /// Returns false when the browser didn't take the link: it couldn't be reached, it is shutting down, or it
    /// closed the connection without an "ACK" (it rejected the message). The caller then launches the
    /// browser instead. A browser that took the whole message but is slow to answer counts as delivered:
    /// it will still open the link, and a fallback launch would open it twice.
    static func send(bundleID: String, executable: URL, arguments: [String]) -> Bool {
        guard let link = ChromiumProfiles.singletonSocket(for: bundleID),
            let target = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path(percentEncoded: false))
        else { return false }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(target.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count < capacity else { return false }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: pathBytes)
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var noSigPipe: Int32 = 1
        var limit = timeout
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))

        let connected = retryingOnEINTR {
            withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
        }
        guard connected == 0 else { return false }

        let message = ChromiumProfiles.singletonMessage(
            executable: executable.path(percentEncoded: false), arguments: arguments)
        guard writeAll(message, to: fd) else {
            // Part of the message may already be in the socket. Reset the connection instead of closing it,
            // so the browser sees an error rather than a short message it might act on with a cut-off URL.
            var abort = linger(l_onoff: 1, l_linger: 0)
            setsockopt(fd, SOL_SOCKET, SO_LINGER, &abort, socklen_t(MemoryLayout<linger>.size))
            return false
        }
        shutdown(fd, SHUT_WR)

        var reply = [UInt8](repeating: 0, count: 32)
        let count = retryingOnEINTR { read(fd, &reply, reply.count) }
        if count > 0 {
            // "ACK" when the browser took the link; "SHUTDOWN" when it is quitting and a new launch should take over.
            return reply.starts(with: Array("ACK".utf8))
        }
        if count == 0 {
            // Closed without an answer: the browser rejected the message.
            NSLog("TrafficControl: \(bundleID) closed its singleton socket without taking the link")
            return false
        }
        NSLog("TrafficControl: \(bundleID) didn't acknowledge the link in time (errno \(errno))")
        return true
    }

    private static func writeAll(_ data: Data, to fd: Int32) -> Bool {
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = retryingOnEINTR { write(fd, buffer.baseAddress! + offset, buffer.count - offset) }
                guard written > 0 else { return false }
                offset += written
            }
            return true
        }
    }

    private static func retryingOnEINTR<T: BinaryInteger>(_ call: () -> T) -> T {
        var result: T
        repeat { result = call() } while result == -1 && errno == EINTR
        return result
    }
}
