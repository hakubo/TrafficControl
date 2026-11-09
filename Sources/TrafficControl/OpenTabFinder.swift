import AppKit
import TrafficControlCore

struct OpenTab {
    let browserID: String
    let windowID: Int
    let tabIndex: Int
}

/// Finds and focuses tabs in running browsers through AppleScript.
/// Lookup only queries allowed browsers; consent requests run independently of link handling.
enum OpenTabFinder {
    @MainActor private static let worker = TabLookupWorker()

    @MainActor private static let automation = AutomationWorker()
    @MainActor private static var permissionChecks: Set<String> = []
    @MainActor private static var consentRequested: Set<String> = []
    @MainActor private static var permissions: [String: Permission] = [:]
    @MainActor private static var permissionObserver: NSObjectProtocol?
    /// Consent dialogs block until answered: one at a time, on a thread of their own rather than the
    /// cooperative pool.
    private static let consentQueue = DispatchQueue(label: "TrafficControl.AutomationConsent", qos: .userInitiated)

    nonisolated private static func requestConsent(for id: String) async -> Permission {
        await withCheckedContinuation { continuation in
            consentQueue.async { continuation.resume(returning: permission(for: id, prompt: true)) }
        }
    }

    /// Permission checks run separately from lookup; consent is requested once per browser per session.
    @MainActor
    static func reuse(_ url: URL, in browserIDs: [String], activate: Bool = true) async -> Bool {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let ids = browserIDs.filter { running.contains($0) && supports($0) }
        if permissionObserver == nil {
            permissionObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { _ in
                Task { @MainActor in permissions.removeAll() }
            }
        }
        for id in ids where permissions[id] == nil && permissionChecks.insert(id).inserted {
            Task {
                defer { permissionChecks.remove(id) }
                var status = await Task.detached(priority: .userInitiated) {
                    permission(for: id, prompt: false)
                }.value
                if status == .notAsked, !consentRequested.contains(id) {
                    status = await requestConsent(for: id)
                    // Only a real answer counts; a browser that quit mid-prompt gets asked again.
                    if status == .allowed || status == .denied { consentRequested.insert(id) }
                }
                if status == .allowed || status == .denied { permissions[id] = status }
            }
        }
        let candidates = ids.filter { permissions[$0] != .denied }
        guard !candidates.isEmpty else { return false }
        let known = permissions
        let automation = automation
        return await worker.run(timeout: 1.5) { attempt in
            // A browser not in the cache yet (after launch or reactivation) is checked here, off the main
            // actor and without prompting, so the first link still reuses its tab. Undecided ones open normally.
            let allowedIDs = candidates.filter {
                known[$0] == .allowed || (known[$0] == nil && permission(for: $0, prompt: false) == .allowed)
            }
            guard let tab = automation.find(url, in: allowedIDs, deadline: attempt.deadline), attempt.commit() else { return false }
            // Focus has its own one-second AppleScript timeout after the commit point.
            return automation.focus(tab, activate: activate, deadline: .now() + 1)
        }
    }

    private enum Dialect { case chromium, safari }

    private static let dialects: [String: Dialect] = {
        var map = Dictionary(uniqueKeysWithValues: ChromiumProfiles.userDataDirectories.keys.map { ($0, Dialect.chromium) })
        map["com.apple.Safari"] = .safari
        map["com.apple.SafariTechnologyPreview"] = .safari
        return map
    }()

    static func supports(_ browserID: String) -> Bool {
        dialects[browserID] != nil
    }

    /// Whether macOS lets TrafficControl control a browser (System Settings → Privacy & Security → Automation).
    enum Permission: Sendable {
        case allowed, denied, notAsked
        /// macOS can only answer for a running browser.
        case notRunning
        case unknown
    }

    /// Asks macOS for the Automation status of a browser. With `prompt`, shows the consent dialog if the user
    /// hasn't decided yet and blocks until they do, so call it off the main thread.
    nonisolated static func permission(for browserID: String, prompt: Bool) -> Permission {
        let target = NSAppleEventDescriptor(bundleIdentifier: browserID)
        guard let desc = target.aeDesc else { return .unknown }
        // A concrete event rather than typeWildCard: wildcards can't trigger the prompt.
        // 'core'/'getd' is what reading tab URLs sends.
        let status = AEDeterminePermissionToAutomateTarget(desc, AEEventClass(kCoreEventClass), AEEventID(kAEGetData), prompt)
        switch status {
        case noErr: return .allowed
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notAsked
        case OSStatus(procNotFound): return .notRunning
        default: return .unknown
        }
    }

    /// NSAppleScript instances and their cache are confined to TabLookupWorker's serial queue.
    private final class AutomationWorker: @unchecked Sendable {
        private var compiledScripts: [String: NSAppleScript] = [:]

        /// Searches the given browsers in order; browsers that aren't running are skipped, never launched.
        func find(_ url: URL, in browserIDs: [String], deadline: DispatchTime) -> OpenTab? {
            guard TabMatching.key(for: url) != nil else { return nil }
            for id in browserIDs {
                guard DispatchTime.now() < deadline else { return nil }
                guard supports(id) else { continue }
                if let hit = TabMatching.find(url, in: Timing.measure("read tabs of \(id)") { windows(of: id, deadline: deadline) }) {
                    return OpenTab(browserID: id, windowID: hit.window, tabIndex: hit.tabIndex)
                }
            }
            return nil
        }

        /// Selects the tab and, unless `activate` is false, brings its window and browser to the front.
        @discardableResult
        func focus(_ tab: OpenTab, activate: Bool, deadline: DispatchTime) -> Bool {
            guard let dialect = dialects[tab.browserID] else { return false }
            let selectTab: String
            let unminimize: String
            switch dialect {
            case .chromium:
                selectTab = "set active tab index of w to \(tab.tabIndex)"
                unminimize = "set minimized of w to false"
            case .safari:
                selectTab = "set current tab of w to tab \(tab.tabIndex) of w"
                unminimize = "set miniaturized of w to false"
            }
            let raise =
                activate
                ? """
                    try
                        \(unminimize)
                    end try
                    set index of w to 1
                    activate
                """ : ""
            let script = """
                tell application id "\(tab.browserID)"
                    set w to window id \(tab.windowID)
                    \(selectTab)
                    \(raise)
                end tell
                """
            return run(script, deadline: deadline).result != nil
        }

        /// Every window's id and tab URLs, front to back. Windows without tabs (e.g. Settings) are skipped.
        private func windows(of browserID: String, deadline: DispatchTime) -> [(id: Int, tabs: [String])] {
            // Two Apple events in total instead of two per window. Fails if any window has no tabs, so fall back.
            let fast = """
                tell application id "\(browserID)" to return {id of every window, URL of every tab of every window}
                """
            let fastReply = run(fast, deadline: deadline, cached: true, quiet: true)
            if let result = fastReply.result {
                let parts = items(of: result)
                if parts.count == 2 {
                    let ids = items(of: parts[0])
                    let tabs = items(of: parts[1])
                    if ids.count == tabs.count {
                        return zip(ids, tabs).map { id, list in
                            (id: Int(id.int32Value), tabs: items(of: list).map { $0.stringValue ?? "" })
                        }
                    }
                }
            }
            // A timed-out browser should not receive another expensive query. Reserve a full event budget.
            guard fastReply.errorNumber != -1712, DispatchTime.now() + 1 < deadline else { return [] }
            let script = """
                tell application id "\(browserID)"
                    set out to {}
                    repeat with w in windows
                        try
                            set end of out to {id of w, URL of every tab of w}
                        on error number errorNumber
                            -- A browser that stopped answering won't answer for the next window either.
                            if errorNumber is -1712 then exit repeat
                        end try
                    end repeat
                    return out
                end tell
                """
            guard let result = run(script, deadline: deadline, cached: true).result else { return [] }
            return items(of: result).compactMap { window in
                let parts = items(of: window)
                guard parts.count == 2 else { return nil }
                let tabs = items(of: parts[1]).map { $0.stringValue ?? "" }
                return (id: Int(parts[0].int32Value), tabs: tabs)
            }
        }

        private func items(of descriptor: NSAppleEventDescriptor) -> [NSAppleEventDescriptor] {
            guard descriptor.numberOfItems > 0 else { return [] }
            return (1...descriptor.numberOfItems).compactMap { descriptor.atIndex($0) }
        }

        /// `cached` is for sources that never change per browser; per-call sources (window and tab ids) compile each time.
        private func run(_ source: String, deadline: DispatchTime, cached: Bool = false, quiet: Bool = false) -> (result: NSAppleEventDescriptor?, errorNumber: Int?) {
            guard DispatchTime.now() < deadline else { return (nil, nil) }
            let source = "with timeout of 1 second\n" + source + "\nend timeout"
            var error: NSDictionary?
            var script = cached ? compiledScripts[source] : nil
            if script == nil {
                script = NSAppleScript(source: source)
                if script?.compileAndReturnError(&error) == false {
                    NSLog("TrafficControl: AppleScript failed to compile: \(String(describing: error))")
                    return (nil, nil)
                }
                if cached { compiledScripts[source] = script }
            }
            guard DispatchTime.now() < deadline else { return (nil, nil) }
            let result = script?.executeAndReturnError(&error)
            if let error {
                if !quiet { NSLog("TrafficControl: AppleScript failed: \(error)") }
                return (nil, error[NSAppleScript.errorNumber] as? Int)
            }
            return (result, nil)
        }
    }
}
