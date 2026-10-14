import AppKit
import TrafficControlCore

struct OpenTab {
    let browserID: String
    let windowID: Int
    let tabIndex: Int
}

/// Finds and focuses tabs in running browsers through AppleScript.
/// macOS asks the user once per browser before TrafficControl may control it; if denied, nothing is found.
@MainActor
enum OpenTabFinder {
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

    /// Searches the given browsers in order; browsers that aren't running are skipped, never launched.
    static func find(_ url: URL, in browserIDs: [String]) -> OpenTab? {
        guard TabMatching.key(for: url) != nil else { return nil }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        for id in browserIDs where supports(id) && running.contains(id) {
            if let hit = TabMatching.find(url, in: windows(of: id)) {
                return OpenTab(browserID: id, windowID: hit.window, tabIndex: hit.tabIndex)
            }
        }
        return nil
    }

    /// Selects the tab and, unless `activate` is false, brings its window and browser to the front.
    @discardableResult
    static func focus(_ tab: OpenTab, activate: Bool = true) -> Bool {
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
        let raise = activate ? """
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
        return run(script) != nil
    }

    /// Every window's id and tab URLs, front to back. Windows without tabs (e.g. Settings) are skipped.
    private static func windows(of browserID: String) -> [(id: Int, tabs: [String])] {
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
        guard let result = run(script) else { return [] }
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

    private static func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            // -1743: the user hasn't allowed TrafficControl to control this browser.
            NSLog("TrafficControl: AppleScript failed: \(error)")
            return nil
        }
        return result
    }
}
