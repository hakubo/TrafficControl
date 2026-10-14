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
    /// Order of picker entries, where each profile of a multi-profile browser is its own entry.
    /// A profile-less target orders every profile of that browser (see `sortedByChoiceOrder`).
    public var choiceOrder: [BrowserTarget] = []
    public var hiddenBrowserIDs: [String] = []
    public var hiddenProfiles: [BrowserTarget] = []
    public var rules: [Rule] = []
    /// Per `AppLink.id`; apps not listed use `defaultAppLinkMode`.
    public var appLinkModes: [String: AppLinkMode] = [:]
    public var showURLInPicker = true
    public var showMenuBarIcon = true
    /// Holding `pickerModifier` while clicking a link skips everything and shows the picker.
    public var forcePickerWithKey = true
    public var pickerModifier = ModifierKey.shift
    public var rememberDomains = true
    public var tabReuse = TabReuseMode.anyBrowser

    public init() {}

    public static let defaultAppLinkMode = AppLinkMode.whenRunning

    public func appLinkMode(for id: String) -> AppLinkMode {
        appLinkModes[id] ?? Self.defaultAppLinkMode
    }

    private enum CodingKeys: String, CodingKey {
        case defaultBehavior, primaryBrowser, choiceOrder, hiddenBrowserIDs, hiddenProfiles, rules, appLinkModes
        case showURLInPicker, showMenuBarIcon, forcePickerWithKey = "forcePickerWithOption", pickerModifier, rememberDomains, tabReuse
    }

    /// Keys that are read but never written again.
    private enum LegacyKeys: String, CodingKey {
        /// Bundle IDs in picker order; superseded by `choiceOrder`.
        case browserOrder
    }

    // Every key is optional so settings files written by older versions keep loading.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        defaultBehavior = try c.decodeIfPresent(DefaultBehavior.self, forKey: .defaultBehavior) ?? d.defaultBehavior
        primaryBrowser = try c.decodeIfPresent(BrowserTarget.self, forKey: .primaryBrowser)
        choiceOrder = try c.decodeIfPresent([BrowserTarget].self, forKey: .choiceOrder) ?? d.choiceOrder
        // Migrate the old bundle-ID order. Once `choiceOrder` exists it is complete (the UI writes
        // every entry), so `browserOrder` only matters when `choiceOrder` is empty.
        if choiceOrder.isEmpty,
            let legacy = try? decoder.container(keyedBy: LegacyKeys.self),
            let ids = try legacy.decodeIfPresent([String].self, forKey: .browserOrder)
        {
            choiceOrder = ids.map { BrowserTarget(browserID: $0) }
        }
        hiddenBrowserIDs = try c.decodeIfPresent([String].self, forKey: .hiddenBrowserIDs) ?? d.hiddenBrowserIDs
        hiddenProfiles = try c.decodeIfPresent([BrowserTarget].self, forKey: .hiddenProfiles) ?? d.hiddenProfiles
        rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? d.rules
        appLinkModes = try c.decodeIfPresent([String: AppLinkMode].self, forKey: .appLinkModes) ?? d.appLinkModes
        showURLInPicker = try c.decodeIfPresent(Bool.self, forKey: .showURLInPicker) ?? d.showURLInPicker
        showMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? d.showMenuBarIcon
        forcePickerWithKey = try c.decodeIfPresent(Bool.self, forKey: .forcePickerWithKey) ?? d.forcePickerWithKey
        pickerModifier = try c.decodeIfPresent(ModifierKey.self, forKey: .pickerModifier) ?? d.pickerModifier
        rememberDomains = try c.decodeIfPresent(Bool.self, forKey: .rememberDomains) ?? d.rememberDomains
        tabReuse = try c.decodeIfPresent(TabReuseMode.self, forKey: .tabReuse) ?? d.tabReuse
    }
}

// MARK: - Picker entries

extension AppSettings {
    /// Sorts picker entries by `choiceOrder`. Entries it doesn't mention (a profile added since)
    /// go last, keeping the order they came in. A profile entry with no slot of its own takes its
    /// browser's profile-less slot (how a migrated `browserOrder` is stored), keeping incoming order among siblings.
    public func sortedByChoiceOrder<T>(_ items: [T], target: (T) -> BrowserTarget) -> [T] {
        var rank: [BrowserTarget: Int] = [:]
        for (i, t) in choiceOrder.enumerated() where rank[t] == nil { rank[t] = i }
        func slot(_ t: BrowserTarget) -> Int {
            rank[t] ?? rank[BrowserTarget(browserID: t.browserID)] ?? Int.max
        }
        return items.enumerated()
            .sorted { (slot(target($0.element)), $0.offset) < (slot(target($1.element)), $1.offset) }
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
