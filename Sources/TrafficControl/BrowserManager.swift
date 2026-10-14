import AppKit
import TrafficControlCore

struct Browser: Identifiable, Hashable {
    /// The bundle identifier.
    let id: String
    let name: String
    let appURL: URL

    var icon: NSImage { NSWorkspace.shared.icon(forFile: appURL.path) }
}

/// One choice in the picker or in a menu: a browser, one profile of a multi-profile browser,
/// or a desktop app that can open the link itself (then `browser` is that app).
struct BrowserChoice: Identifiable {
    let browser: Browser
    let profile: BrowserProfile?
    var avatar: NSImage? = nil
    var deepLink: URL? = nil

    var id: String { browser.id + "/" + (profile?.id ?? "") }
    var target: BrowserTarget { BrowserTarget(browserID: browser.id, profileID: profile?.id) }
    var destination: LinkDestination { deepLink != nil ? .app(bundleID: browser.id) : .browser(target) }
    var title: String { profile?.name ?? browser.name }
    var menuTitle: String { profile.map { "\(browser.name) – \($0.name)" } ?? browser.name }
}

/// Finds installed browsers, tracks which ones are running and opens links in them.
@MainActor
final class BrowserManager: ObservableObject {
    @Published private(set) var installed: [Browser] = []
    /// Profiles of Chromium-based browsers, keyed by bundle identifier.
    @Published private(set) var profiles: [String: [BrowserProfile]] = [:]
    private(set) var lastActiveBrowserID: String?
    private var activationObserver: NSObjectProtocol?

    init() {
        refresh()
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, browser(withID: front) != nil {
            lastActiveBrowserID = front
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let id = app?.bundleIdentifier else { return }
            MainActor.assumeIsolated {
                guard let self, self.browser(withID: id) != nil else { return }
                self.lastActiveBrowserID = id
            }
        }
    }

    /// Every app registered for https, except TrafficControl itself.
    func refresh() {
        let probe = URL(string: "https://example.com")!
        var seen: Set<String> = []
        if let own = Bundle.main.bundleIdentifier { seen.insert(own) }
        installed = NSWorkspace.shared.urlsForApplications(toOpen: probe).compactMap { url in
            guard let bundle = Bundle(url: url),
                  let id = bundle.bundleIdentifier,
                  seen.insert(id).inserted
            else { return nil }
            let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? url.deletingPathExtension().lastPathComponent
            return Browser(id: id, name: name, appURL: url)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        refreshProfiles()
    }

    /// Cheap enough to run on every click, so profiles added in Chrome show up straight away.
    func refreshProfiles() {
        var found: [String: [BrowserProfile]] = [:]
        for browser in installed where ChromiumProfiles.supports(browser.id) {
            let list = ChromiumProfiles.load(for: browser.id)
            if !list.isEmpty { found[browser.id] = list }
        }
        if found != profiles { profiles = found }
    }

    /// Profiles worth choosing between; a browser with a single profile is just the browser.
    func selectableProfiles(for browserID: String) -> [BrowserProfile] {
        let list = profiles[browserID] ?? []
        return list.count > 1 ? list : []
    }

    /// What the picker shows: the desktop app for this link (if any), then visible browsers,
    /// with multi-profile browsers expanded into their visible profiles.
    func pickerChoices(_ settings: AppSettings, for url: URL? = nil) -> [BrowserChoice] {
        var app: [BrowserChoice] = []
        if let url, let (link, deepLink) = AppLink.first(for: url), settings.appLinkMode(for: link.id) != .never,
           let appURL = appURL(for: link.bundleID) {
            app = [BrowserChoice(browser: Browser(id: link.bundleID, name: link.name, appURL: appURL), profile: nil, deepLink: deepLink)]
        }
        let hidden = Set(settings.hiddenProfiles)
        return app + ordered(settings, includeHidden: false).flatMap { browser -> [BrowserChoice] in
            let list = selectableProfiles(for: browser.id)
            guard !list.isEmpty else { return [BrowserChoice(browser: browser, profile: nil)] }
            return list
                .filter { !hidden.contains(BrowserTarget(browserID: browser.id, profileID: $0.id)) }
                .map { BrowserChoice(browser: browser, profile: $0, avatar: $0.avatarPath.flatMap(NSImage.init(contentsOfFile:))) }
        }
    }

    /// Every browser plus each of its profiles, for rule and primary-browser menus.
    func menuChoices(_ settings: AppSettings) -> [BrowserChoice] {
        ordered(settings, includeHidden: true).flatMap { browser in
            [BrowserChoice(browser: browser, profile: nil)]
                + selectableProfiles(for: browser.id).map { BrowserChoice(browser: browser, profile: $0) }
        }
    }

    func title(for destination: LinkDestination) -> String {
        switch destination {
        case .browser(let target): title(for: target)
        case .app(let id): AppLink.all.first { $0.bundleID == id }?.name ?? id
        }
    }

    func title(for target: BrowserTarget) -> String {
        guard let browser = browser(withID: target.browserID) else { return target.browserID }
        guard let id = target.profileID else { return browser.name }
        let name = profiles[browser.id]?.first { $0.id == id }?.name ?? id
        return "\(browser.name) – \(name)"
    }

    // MARK: Desktop apps

    func appURL(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    var installedAppLinkIDs: Set<String> {
        Set(AppLink.all.map(\.bundleID).filter { appURL(for: $0) != nil })
    }

    var runningAppLinkIDs: Set<String> {
        let ids = Set(AppLink.all.map(\.bundleID))
        return Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier).filter(ids.contains))
    }

    func openInApp(_ deepLink: URL, bundleID: String) {
        guard let app = appURL(for: bundleID) else { return }
        NSWorkspace.shared.open([deepLink], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { NSLog("TrafficControl: failed to open \(deepLink) in \(bundleID): \(error)") }
        }
    }

    func browser(withID id: String) -> Browser? {
        installed.first { $0.id == id }
    }

    var runningBrowserIDs: [String] {
        let ids = Set(installed.map(\.id))
        return NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier).filter(ids.contains)
    }

    /// Browsers in the user's chosen order; unordered ones go last, alphabetically.
    func ordered(_ settings: AppSettings, includeHidden: Bool) -> [Browser] {
        let rank = settings.browserOrder.enumerated().reduce(into: [String: Int]()) { result, pair in
            result[pair.element] = result[pair.element] ?? pair.offset
        }
        let hidden = Set(settings.hiddenBrowserIDs)
        return installed
            .filter { includeHidden || !hidden.contains($0.id) }
            .enumerated()
            .sorted { (rank[$0.element.id] ?? Int.max, $0.offset) < (rank[$1.element.id] ?? Int.max, $1.offset) }
            .map(\.element)
    }

    /// Switches to a tab of `browser` already showing the link when `reuseTab` is set, otherwise opens it.
    func openOrSwitch(_ url: URL, in browser: Browser, profileID: String?, inBackground: Bool, reuseTab: Bool) {
        if reuseTab, let tab = OpenTabFinder.find(url, in: [browser.id]), OpenTabFinder.focus(tab, activate: !inBackground) {
            return
        }
        open([url], in: browser, profileID: profileID, inBackground: inBackground)
    }

    func open(_ urls: [URL], in browser: Browser, profileID: String? = nil, inBackground: Bool) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = !inBackground
        if let profileID {
            // Like `open -n --args`: a fresh process receives the arguments and hands them to the
            // running browser, which opens the links in that profile's window.
            config.createsNewApplicationInstance = true
            config.arguments = ChromiumProfiles.launchArguments(profileID: profileID, urls: urls)
            NSWorkspace.shared.openApplication(at: browser.appURL, configuration: config) { _, error in
                if let error { NSLog("TrafficControl: failed to open in \(browser.name) (\(profileID)): \(error)") }
            }
            return
        }
        NSWorkspace.shared.open(urls, withApplicationAt: browser.appURL, configuration: config) { _, error in
            if let error { NSLog("TrafficControl: failed to open in \(browser.name): \(error)") }
        }
    }
}
