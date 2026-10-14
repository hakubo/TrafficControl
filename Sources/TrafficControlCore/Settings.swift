import Foundation

/// What to do with a link that no rule claims.
public enum DefaultBehavior: String, Codable, CaseIterable, Sendable, Hashable {
    case alwaysAsk
    case primaryBrowser
    case runningBrowser
    case lastActiveBrowser

    public var label: String {
        switch self {
        case .alwaysAsk: "Always show the picker"
        case .primaryBrowser: "Open in the primary browser"
        case .runningBrowser: "Use the running browser if only one is open"
        case .lastActiveBrowser: "Use the most recently used running browser"
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var defaultBehavior: DefaultBehavior = .alwaysAsk
    public var primaryBrowser: BrowserTarget?
    public var browserOrder: [String] = []
    /// Order of picker entries, where each profile of a multi-profile browser is its own entry.
    /// Wins over `browserOrder`; entries missing from it keep their `browserOrder` place, after these.
    public var choiceOrder: [BrowserTarget] = []
    public var hiddenBrowserIDs: [String] = []
    public var hiddenProfiles: [BrowserTarget] = []
    public var rules: [Rule] = []
    /// Per `AppLink.id`; apps not listed use `defaultAppLinkMode`.
    public var appLinkModes: [String: AppLinkMode] = [:]
    public var showURLInPicker = true
    public var showMenuBarIcon = true
    /// Holding `pickerModifier` while clicking a link skips everything and shows the picker.
    public var forcePickerWithOption = true
    public var pickerModifier = ModifierKey.shift
    public var rememberDomains = true
    public var tabReuse = TabReuseMode.anyBrowser

    public init() {}

    public static let defaultAppLinkMode = AppLinkMode.whenRunning

    public func appLinkMode(for id: String) -> AppLinkMode {
        appLinkModes[id] ?? Self.defaultAppLinkMode
    }

    private enum CodingKeys: String, CodingKey {
        case defaultBehavior, primaryBrowser, browserOrder, choiceOrder, hiddenBrowserIDs, hiddenProfiles, rules, appLinkModes
        case showURLInPicker, showMenuBarIcon, forcePickerWithOption, pickerModifier, rememberDomains, tabReuse
    }

    // Every key is optional so settings files written by older versions keep loading.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        defaultBehavior = try c.decodeIfPresent(DefaultBehavior.self, forKey: .defaultBehavior) ?? d.defaultBehavior
        primaryBrowser = try c.decodeIfPresent(BrowserTarget.self, forKey: .primaryBrowser)
        browserOrder = try c.decodeIfPresent([String].self, forKey: .browserOrder) ?? d.browserOrder
        choiceOrder = try c.decodeIfPresent([BrowserTarget].self, forKey: .choiceOrder) ?? d.choiceOrder
        hiddenBrowserIDs = try c.decodeIfPresent([String].self, forKey: .hiddenBrowserIDs) ?? d.hiddenBrowserIDs
        hiddenProfiles = try c.decodeIfPresent([BrowserTarget].self, forKey: .hiddenProfiles) ?? d.hiddenProfiles
        rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? d.rules
        appLinkModes = try c.decodeIfPresent([String: AppLinkMode].self, forKey: .appLinkModes) ?? d.appLinkModes
        showURLInPicker = try c.decodeIfPresent(Bool.self, forKey: .showURLInPicker) ?? d.showURLInPicker
        showMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? d.showMenuBarIcon
        forcePickerWithOption = try c.decodeIfPresent(Bool.self, forKey: .forcePickerWithOption) ?? d.forcePickerWithOption
        pickerModifier = try c.decodeIfPresent(ModifierKey.self, forKey: .pickerModifier) ?? d.pickerModifier
        rememberDomains = try c.decodeIfPresent(Bool.self, forKey: .rememberDomains) ?? d.rememberDomains
        tabReuse = try c.decodeIfPresent(TabReuseMode.self, forKey: .tabReuse) ?? d.tabReuse
    }
}

// MARK: - Picker entries

extension AppSettings {
    /// Sorts picker entries by `choiceOrder`. Entries it doesn't mention (a profile added since)
    /// go last, keeping the order they came in.
    public func sortedByChoiceOrder<T>(_ items: [T], target: (T) -> BrowserTarget) -> [T] {
        var rank: [BrowserTarget: Int] = [:]
        for (i, t) in choiceOrder.enumerated() where rank[t] == nil { rank[t] = i }
        return items.enumerated()
            .sorted { (rank[target($0.element)] ?? Int.max, $0.offset) < (rank[target($1.element)] ?? Int.max, $1.offset) }
            .map(\.element)
    }

    /// Whether the picker leaves this entry out: its whole browser is hidden, or just this profile.
    public func isHidden(_ target: BrowserTarget) -> Bool {
        hiddenBrowserIDs.contains(target.browserID) || (target.profileID != nil && hiddenProfiles.contains(target))
    }

    /// Shows or hides one entry. `siblings` are the other profiles of the same browser: showing a
    /// profile of a browser hidden as a whole unhides the browser but keeps those siblings hidden.
    public mutating func setHidden(_ hidden: Bool, _ target: BrowserTarget, siblings: [BrowserTarget] = []) {
        guard target.profileID != nil else {
            hiddenBrowserIDs.removeAll { $0 == target.browserID }
            if hidden { hiddenBrowserIDs.append(target.browserID) }
            return
        }
        if !hidden, hiddenBrowserIDs.contains(target.browserID) {
            hiddenBrowserIDs.removeAll { $0 == target.browserID }
            for sibling in siblings where sibling != target && !hiddenProfiles.contains(sibling) {
                hiddenProfiles.append(sibling)
            }
        }
        hiddenProfiles.removeAll { $0 == target }
        if hidden { hiddenProfiles.append(target) }
    }
}

public struct SettingsStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = SettingsStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    public static var defaultFileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "TrafficControl", directoryHint: .isDirectory)
            .appending(path: "settings.json")
    }

    public func load() -> AppSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return settings
    }

    public func save(_ settings: AppSettings) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
