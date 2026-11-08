import AppKit
import TrafficControlCore

struct OpenTab {
    let browserID: String
    let windowID: Int
    let tabIndex: Int
}

/// Finds and focuses tabs in running browsers through AppleScript.
/// Only browsers already allowed in Automation settings are queried; link handling never prompts.
enum OpenTabFinder {
    @MainActor private static let worker = TabLookupWorker()

    /// The deadline covers the entire search and focus, across every browser.
    @MainActor
    static func reuse(_ url: URL, in browserIDs: [String], activate: Bool = true) async -> Bool {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return await worker.run(timeout: 1.5) { deadline in
            lookupDeadline = deadline
            defer { lookupDeadline = nil }
            guard let tab = find(url, in: browserIDs.filter { running.contains($0) }) else { return false }
            return focus(tab, activate: activate)
        }
    }

    // All mutable Automation state and NSAppleScript instances belong to the serial worker.
    private static var lookupDeadline: DispatchTime?

    private enum Dialect { case chromium, safari }

    private static let dialects: [String: Dialect] = {
        var map = Dictionary(uniqueKeysWithValues: ChromiumProfiles.userDataDirectories.keys.map { ($0, Dialect.chromium) })
        map["com.apple.Safari"] = .safari
        map["com.apple.SafariTechnologyPreview"] = .safari
        return map
    }()

    /// Compiled static scripts, keyed by source (which embeds the browser ID), so each is compiled once.
    private static var compiledScripts: [String: NSAppleScript] = [:]

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

    /// Searches the given browsers in order; browsers that aren't running are skipped, never launched.
    private static func find(_ url: URL, in browserIDs: [String]) -> OpenTab? {
        guard TabMatching.key(for: url) != nil else { return nil }
        for id in browserIDs {
            guard let deadline = lookupDeadline, DispatchTime.now() < deadline else { return nil }
            guard supports(id), permission(for: id, prompt: false) == .allowed else { continue }
            if let hit = TabMatching.find(url, in: Timing.measure("read tabs of \(id)") { windows(of: id) }) {
                return OpenTab(browserID: id, windowID: hit.window, tabIndex: hit.tabIndex)
            }
        }
        return nil
    }

    /// Selects the tab and, unless `activate` is false, brings its window and browser to the front.
    @discardableResult
    private static func focus(_ tab: OpenTab, activate: Bool = true) -> Bool {
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
        return run(script, browserID: tab.browserID) != nil
    }

    /// Every window's id and tab URLs, front to back. Windows without tabs (e.g. Settings) are skipped.
    private static func windows(of browserID: String) -> [(id: Int, tabs: [String])] {
        // Two Apple events in total instead of two per window. Fails if any window has no tabs, so fall back.
        let fast = """
            tell application id "\(browserID)" to return {id of every window, URL of every tab of every window}
            """
        if let result = run(fast, browserID: browserID, cached: true, quiet: true) {
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
        let script = """
            tell application id "\(browserID)"
                set out to {}
                repeat with w in windows
                    try
                        set end of out to {id of w, URL of every tab of w}
                    end try
                end repeat
                return out
            end tell
            """
        guard let result = run(script, browserID: browserID, cached: true) else { return [] }
        return items(of: result).compactMap { window in
            let parts = items(of: window)
            guard parts.count == 2 else { return nil }
            let tabs = items(of: parts[1]).map { $0.stringValue ?? "" }
            return (id: Int(parts[0].int32Value), tabs: tabs)
        }
    }

    private static func items(of descriptor: NSAppleEventDescriptor) -> [NSAppleEventDescriptor] {
        guard descriptor.numberOfItems > 0 else { return [] }
        return (1...descriptor.numberOfItems).compactMap { descriptor.atIndex($0) }
    }

    /// `cached` is for sources that never change per browser; per-call sources (window and tab ids) compile each time.
    private static func run(_ source: String, browserID: String, cached: Bool = false, quiet: Bool = false) -> NSAppleEventDescriptor? {
        guard let deadline = lookupDeadline, DispatchTime.now() < deadline else { return nil }
        let source = "with timeout of 1 second\n" + source + "\nend timeout"
        var error: NSDictionary?
        var script = cached ? compiledScripts[source] : nil
        if script == nil {
            script = NSAppleScript(source: source)
            if script?.compileAndReturnError(&error) == false {
                NSLog("TrafficControl: AppleScript failed to compile: \(String(describing: error))")
                return nil
            }
            if cached { compiledScripts[source] = script }
        }
        guard DispatchTime.now() < deadline else { return nil }
        let result = script?.executeAndReturnError(&error)
        if let error {
            if !quiet { NSLog("TrafficControl: AppleScript failed: \(error)") }
            return nil
        }
        return result
    }
}
