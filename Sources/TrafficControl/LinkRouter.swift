import AppKit
import TrafficControlCore

private extension RoutingDecision {
    var isApp: Bool {
        if case .openInApp = self { return true }
        return false
    }
}

/// Which modifier keys were held for the click that opened a link. Apps hand links to macOS a moment
/// after the click, often after the keys are released, so the keys held at the last mouse click
/// (within a couple of seconds) count as well as those held now. Watching clicks needs no permission.
@MainActor
final class ModifierTracker {
    private var lastClick: (keys: Set<ModifierKey>, at: Date)?
    private var monitor: Any?

    init() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            let keys = Self.keys(in: event.modifierFlags)
            MainActor.assumeIsolated { self?.lastClick = (keys, Date()) }
        }
    }

    func held() -> Set<ModifierKey> {
        var keys = Self.keys(in: NSEvent.modifierFlags)
        if let click = lastClick, Date().timeIntervalSince(click.at) < 2 { keys.formUnion(click.keys) }
        return keys
    }

    nonisolated static func keys(in flags: NSEvent.ModifierFlags) -> Set<ModifierKey> {
        var keys: Set<ModifierKey> = []
        if flags.contains(.control) { keys.insert(.control) }
        if flags.contains(.option) { keys.insert(.option) }
        if flags.contains(.shift) { keys.insert(.shift) }
        if flags.contains(.command) { keys.insert(.command) }
        return keys
    }
}

/// Turns an incoming link into a decision: open directly, or ask with the picker.
@MainActor
final class LinkRouter {
    private let settings: SettingsModel
    private let browsers: BrowserManager
    private let picker: PickerController
    private let history: HistoryModel
    private let modifiers = ModifierTracker()
    /// "Send All Links To" from the menu bar. In memory only: relaunching TrafficControl clears it.
    var override: TemporaryOverride?

    init(settings: SettingsModel, browsers: BrowserManager, picker: PickerController, history: HistoryModel) {
        self.settings = settings
        self.browsers = browsers
        self.picker = picker
        self.history = history
    }

    func route(_ urls: [URL], senderPID: pid_t?) {
        let start = ContinuousClock.now
        defer { Timing.report("route total", since: start) }
        Timing.measure("refresh browsers") { browsers.refresh() }
        let source = sourceApplication(pid: senderPID)
        let current = settings.settings
        let held = modifiers.held()
        let forcePicker = current.forcePickerWithKey && held.contains(current.pickerModifier)

        for url in urls {
            let context = LinkContext(
                url: url, sourceBundleID: source?.bundleIdentifier, sourceAppName: source?.localizedName,
                modifiers: held)
            let environment = RoutingEnvironment(
                installedBrowserIDs: Set(browsers.installed.map(\.id)),
                installedProfiles: browsers.profiles.mapValues { Set($0.map(\.id)) },
                runningBrowserIDs: browsers.runningBrowserIDs,
                installedAppIDs: browsers.installedAppLinkIDs,
                runningAppIDs: browsers.runningAppLinkIDs,
                lastActiveBrowserID: browsers.lastActiveBrowserID,
                forcePicker: forcePicker,
                override: override)

            let decision = Timing.measure("decide") { Router.decide(context, settings: current, environment: environment) }
            Timing.note("\(url.host() ?? "?") -> \(decision)")
            let overridden = override.map { $0.isActive(at: environment.now) && decision == .open($0.target, ruleID: nil) } ?? false

            // Already open somewhere? Go there instead of opening a duplicate. Desktop apps still win,
            // the picker key skips this so the picker always appears, and so does a rule that asks
            // for held keys: holding them says where you want the link. An override keeps links in
            // its browser (say, the one being screen-shared), so it skips this too.
            if current.tabReuse == .anyBrowser, !forcePicker, !decision.isApp, !overridden,
                !Self.ruleUsesKeys(decision, in: current.rules),
                let tab = Timing.measure("find open tab (any browser)") { OpenTabFinder.find(url, in: tabSearchOrder(decision)) },
                Timing.measure("focus tab") { OpenTabFinder.focus(tab) }
            {
                continue
            }

            switch decision {
            case .open(let target, _):
                if let browser = browsers.browser(withID: target.browserID) {
                    browsers.openOrSwitch(
                        url, in: browser, profileID: target.profileID, inBackground: false,
                        reuseTab: current.tabReuse == .targetBrowser)
                    if current.rememberDomains { history.record(url, destination: .browser(target)) }
                } else {
                    picker.enqueue(PickerRequest(url: url, sourceApp: source))
                }
            case .openInApp(let bundleID, let deepLink):
                browsers.openInApp(deepLink, bundleID: bundleID)
                if current.rememberDomains { history.record(url, destination: .app(bundleID: bundleID)) }
            case .ask:
                picker.enqueue(PickerRequest(url: url, sourceApp: source))
            }
        }
    }

    private static func ruleUsesKeys(_ decision: RoutingDecision, in rules: [Rule]) -> Bool {
        guard case .open(_, let ruleID?) = decision, let rule = rules.first(where: { $0.id == ruleID }) else { return false }
        return rule.conditions.contains { $0.field == .modifiers }
    }

    /// The browser the link would open in first, then the one used last, then any other running one.
    private func tabSearchOrder(_ decision: RoutingDecision) -> [String] {
        var order: [String] = []
        if case .open(let target, _) = decision { order.append(target.browserID) }
        if let last = browsers.lastActiveBrowserID { order.append(last) }
        order += browsers.runningBrowserIDs
        var seen: Set<String> = []
        return order.filter { seen.insert($0).inserted }
    }

    /// The app that sent the open event; falls back to the frontmost app when the sender is unknown.
    private func sourceApplication(pid: pid_t?) -> NSRunningApplication? {
        let own = ProcessInfo.processInfo.processIdentifier
        if let pid, pid != own, let app = NSRunningApplication(processIdentifier: pid) {
            return app
        }
        let front = NSWorkspace.shared.frontmostApplication
        return front?.processIdentifier == own ? nil : front
    }
}
