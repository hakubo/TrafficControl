import AppKit
import TrafficControlCore

private extension RoutingDecision {
    var isApp: Bool {
        if case .openInApp = self { return true }
        return false
    }
}

/// Turns an incoming link into a decision: open directly, or ask with the picker.
@MainActor
final class LinkRouter {
    private let settings: SettingsModel
    private let browsers: BrowserManager
    private let picker: PickerController
    private let history: HistoryModel

    init(settings: SettingsModel, browsers: BrowserManager, picker: PickerController, history: HistoryModel) {
        self.settings = settings
        self.browsers = browsers
        self.picker = picker
        self.history = history
    }

    func route(_ urls: [URL], senderPID: pid_t?) {
        if browsers.installed.isEmpty { browsers.refresh() } else { browsers.refreshProfiles() }
        let source = sourceApplication(pid: senderPID)
        let current = settings.settings
        let forcePicker = current.forcePickerWithOption && NSEvent.modifierFlags.contains(.option)

        for url in urls {
            let context = LinkContext(
                url: url, sourceBundleID: source?.bundleIdentifier, sourceAppName: source?.localizedName)
            let environment = RoutingEnvironment(
                installedBrowserIDs: Set(browsers.installed.map(\.id)),
                installedProfiles: browsers.profiles.mapValues { Set($0.map(\.id)) },
                runningBrowserIDs: browsers.runningBrowserIDs,
                installedAppIDs: browsers.installedAppLinkIDs,
                runningAppIDs: browsers.runningAppLinkIDs,
                lastActiveBrowserID: browsers.lastActiveBrowserID,
                forcePicker: forcePicker)

            let decision = Router.decide(context, settings: current, environment: environment)

            // Already open somewhere? Go there instead of opening a duplicate. Desktop apps still win,
            // and holding ⌥ skips this so the picker always appears.
            if current.tabReuse == .anyBrowser, !forcePicker, !decision.isApp,
               let tab = OpenTabFinder.find(url, in: tabSearchOrder(decision)), OpenTabFinder.focus(tab) {
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
