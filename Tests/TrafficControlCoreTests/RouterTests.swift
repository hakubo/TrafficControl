import Foundation
import Testing
@testable import TrafficControlCore

private let chrome = "com.google.Chrome"
private let safari = "com.apple.Safari"
private let firefox = "org.mozilla.firefox"
private let installed: Set<String> = [chrome, safari, firefox]

private func link(_ string: String, from source: String? = nil, name: String? = nil) -> LinkContext {
    LinkContext(url: URL(string: string)!, sourceBundleID: source, sourceAppName: name)
}

@Suite struct ConditionTests {
    @Test func domainMatchesItselfAndSubdomainsOnly() {
        let c = Condition(field: .host, op: .isDomain, value: "github.com")
        #expect(c.matches(link("https://github.com/x")))
        #expect(c.matches(link("https://gist.GitHub.com/x")))
        #expect(!c.matches(link("https://notgithub.com")))
    }

    @Test func wildcardIsAnchoredAndCaseInsensitive() {
        let c = Condition(field: .url, op: .wildcard, value: "https://*.zoom.us/j/*")
        #expect(c.matches(link("https://us02web.ZOOM.us/j/123")))
        #expect(!c.matches(link("https://zoom.us.evil.com/j/1")))
    }

    @Test func regexAndInvalidRegex() {
        #expect(Condition(field: .path, op: .regex, value: "^/pull/\\d+$").matches(link("https://x.com/pull/42")))
        #expect(!Condition(field: .url, op: .regex, value: "(").matches(link("https://x.com")))
    }

    @Test func sourceAppMatchesBundleIDOrName() {
        let byID = Condition(field: .sourceApp, op: .equals, value: "com.tinyspeck.slackmacgap")
        let byName = Condition(field: .sourceApp, op: .contains, value: "slack")
        let ctx = link("https://a.com", from: "com.tinyspeck.slackmacgap", name: "Slack")
        #expect(byID.matches(ctx))
        #expect(byName.matches(ctx))
        #expect(!byName.matches(link("https://a.com")))
    }

    @Test func emptyValueNeverMatches() {
        #expect(!Condition(field: .url, op: .contains, value: "  ").matches(link("https://a.com")))
    }
}

@Suite struct RouterTests {
    @Test func firstMatchingRuleWins() {
        var s = AppSettings()
        s.rules = [
            Rule(conditions: [Condition(field: .host, value: "github.com")], action: .open(browserID: firefox)),
            Rule(conditions: [Condition(field: .url, op: .contains, value: "github")], action: .open(browserID: chrome)),
        ]
        let d = Router.decide(link("https://github.com"), settings: s, environment: .init(installedBrowserIDs: installed))
        #expect(d == .open(BrowserTarget(browserID: firefox), ruleID: s.rules[0].id))
    }

    @Test func ruleForMissingBrowserFallsThrough() {
        var s = AppSettings()
        s.defaultBehavior = .primaryBrowser
        s.primaryBrowser = BrowserTarget(browserID: safari)
        s.rules = [Rule(conditions: [Condition(field: .host, value: "a.com")], action: .open(browserID: "com.gone"))]
        let d = Router.decide(link("https://a.com"), settings: s, environment: .init(installedBrowserIDs: installed))
        #expect(d == .open(BrowserTarget(browserID: safari), ruleID: nil))
    }

    @Test func disabledRulesAndAnyMode() {
        var s = AppSettings()
        s.rules = [
            Rule(isEnabled: false, conditions: [Condition(field: .host, value: "a.com")], action: .open(browserID: chrome)),
            Rule(matchMode: .any, conditions: [
                Condition(field: .host, value: "b.com"),
                Condition(field: .host, value: "a.com"),
            ], action: .open(browserID: safari)),
        ]
        let d = Router.decide(link("https://a.com"), settings: s, environment: .init(installedBrowserIDs: installed))
        #expect(d == .open(BrowserTarget(browserID: safari), ruleID: s.rules[1].id))
    }

    @Test func modifierForcesPicker() {
        var s = AppSettings()
        s.rules = [Rule(conditions: [Condition(field: .host, value: "a.com")], action: .open(browserID: chrome))]
        let env = RoutingEnvironment(installedBrowserIDs: installed, forcePicker: true)
        #expect(Router.decide(link("https://a.com"), settings: s, environment: env) == .ask)
    }

    @Test func runningBrowserBehaviorIgnoresHiddenBrowsers() {
        var s = AppSettings()
        s.defaultBehavior = .runningBrowser
        let env = RoutingEnvironment(installedBrowserIDs: installed, runningBrowserIDs: [chrome, safari])
        #expect(Router.decide(link("https://a.com"), settings: s, environment: env) == .ask)
        s.hiddenBrowserIDs = [safari]
        #expect(Router.decide(link("https://a.com"), settings: s, environment: env) == .open(BrowserTarget(browserID: chrome), ruleID: nil))
    }

    @Test func lastActiveBrowserMustStillBeRunning() {
        var s = AppSettings()
        s.defaultBehavior = .lastActiveBrowser
        let env = RoutingEnvironment(installedBrowserIDs: installed, runningBrowserIDs: [chrome, firefox], lastActiveBrowserID: firefox)
        #expect(Router.decide(link("https://a.com"), settings: s, environment: env) == .open(BrowserTarget(browserID: firefox), ruleID: nil))
        let quit = RoutingEnvironment(installedBrowserIDs: installed, runningBrowserIDs: [chrome, firefox], lastActiveBrowserID: safari)
        #expect(Router.decide(link("https://a.com"), settings: s, environment: quit) == .ask)
    }
}

@Suite struct PickerEntryTests {
    private let work = BrowserTarget(browserID: chrome, profileID: "Profile 1")
    private let home = BrowserTarget(browserID: chrome, profileID: "Default")
    private let plainSafari = BrowserTarget(browserID: safari)

    @Test func choiceOrderPutsUnknownEntriesLast() {
        var s = AppSettings()
        s.choiceOrder = [work, plainSafari]
        #expect(s.sortedByChoiceOrder([home, plainSafari, work], target: { $0 }) == [work, plainSafari, home])
    }

    @Test func emptyChoiceOrderKeepsIncomingOrder() {
        #expect(AppSettings().sortedByChoiceOrder([home, plainSafari, work], target: { $0 }) == [home, plainSafari, work])
    }

    @Test func showingAProfileOfAHiddenBrowserKeepsItsSiblingsHidden() {
        var s = AppSettings()
        s.hiddenBrowserIDs = [chrome]
        #expect(s.isHidden(work) && s.isHidden(home))
        s.setHidden(false, work, siblings: [home, work])
        #expect(!s.isHidden(work))
        #expect(s.isHidden(home))
        #expect(s.hiddenBrowserIDs.isEmpty)
    }

    @Test func hidingPlainBrowser() {
        var s = AppSettings()
        s.setHidden(true, plainSafari)
        #expect(s.hiddenBrowserIDs == [safari])
        s.setHidden(false, plainSafari)
        #expect(!s.isHidden(plainSafari))
    }
}

@Suite struct SettingsStoreTests {
    @Test func roundTripsAndToleratesMissingKeys() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "s.json")
        let store = SettingsStore(fileURL: url)
        var s = AppSettings()
        s.rules = [Rule(name: "Work", conditions: [Condition(field: .host, value: "corp.com")], action: .open(browserID: chrome))]
        s.defaultBehavior = .lastActiveBrowser
        try store.save(s)
        #expect(store.load() == s)

        let partial = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"showMenuBarIcon": false}"#.utf8))
        #expect(partial.showMenuBarIcon == false)
        #expect(partial.defaultBehavior == .alwaysAsk)
    }
}

@Suite struct ProfileTests {
    private let localState = Data(#"""
    {"profile": {
      "profiles_order": ["Profile 2", "Default"],
      "info_cache": {
        "Default": {"name": "Personal", "user_name": "me@example.com", "gaia_picture_file_name": "Google Profile Picture.png"},
        "Profile 2": {"name": "Work", "user_name": ""},
        "Profile 9": {"name": "Temp", "is_ephemeral": true}
      }
    }}
    """#.utf8)

    @Test func parsesProfilesInBrowserOrderAndSkipsEphemeral() {
        let dir = URL(filePath: "/tmp/Chrome")
        let profiles = ChromiumProfiles.parseLocalState(localState, userDataDirectory: dir)
        #expect(profiles.map(\.id) == ["Profile 2", "Default"])
        #expect(profiles.map(\.name) == ["Work", "Personal"])
        #expect(profiles[0].userName == nil)
        #expect(profiles[1].avatarPath == "/tmp/Chrome/Default/Google Profile Picture.png")
    }

    @Test func defaultComesFirstWithoutRecordedOrder() {
        let data = Data(#"{"profile":{"info_cache":{"Profile 1":{"name":"A"},"Default":{"name":"Z"}}}}"#.utf8)
        #expect(ChromiumProfiles.parseLocalState(data).map(\.id) == ["Default", "Profile 1"])
    }

    @Test func garbageYieldsNoProfiles() {
        #expect(ChromiumProfiles.parseLocalState(Data("nope".utf8)).isEmpty)
    }

    @Test func launchArgumentsSelectProfile() {
        let args = ChromiumProfiles.launchArguments(profileID: "Profile 2", urls: [URL(string: "https://a.com/x?y=1")!])
        #expect(args == ["--profile-directory=Profile 2", "https://a.com/x?y=1"])
    }

    @Test func ruleOpensSpecificProfile() {
        var s = AppSettings()
        s.rules = [Rule(conditions: [Condition(field: .host, value: "corp.com")], action: .open(browserID: chrome, profileID: "Profile 2"))]
        let env = RoutingEnvironment(installedBrowserIDs: installed, installedProfiles: [chrome: ["Default", "Profile 2"]])
        #expect(Router.decide(link("https://docs.corp.com"), settings: s, environment: env)
                == .open(BrowserTarget(browserID: chrome, profileID: "Profile 2"), ruleID: s.rules[0].id))
    }

    @Test func ruleForDeletedProfileFallsThrough() {
        var s = AppSettings()
        s.defaultBehavior = .primaryBrowser
        s.primaryBrowser = BrowserTarget(browserID: chrome, profileID: "Default")
        s.rules = [Rule(conditions: [Condition(field: .host, value: "corp.com")], action: .open(browserID: chrome, profileID: "Profile 7"))]
        let env = RoutingEnvironment(installedBrowserIDs: installed, installedProfiles: [chrome: ["Default"]])
        #expect(Router.decide(link("https://corp.com"), settings: s, environment: env)
                == .open(BrowserTarget(browserID: chrome, profileID: "Default"), ruleID: nil))
    }
}

@Suite struct AppLinkTests {
    private let linearURL = URL(string: "https://linear.app/buffer/project/retool-and-classic-admin-migration-a02fd684c5c4/activity#project-update-f9e936e0")!

    @Test func linearKeepsPathAndFragment() {
        #expect(AppLink.linear.deepLink(linearURL)?.absoluteString
                == "linear://buffer/project/retool-and-classic-admin-migration-a02fd684c5c4/activity#project-update-f9e936e0")
        #expect(AppLink.linear.deepLink(URL(string: "https://linear.app/buffer/issue/ENG-12?tab=x")!)?.absoluteString
                == "linear://buffer/issue/ENG-12?tab=x")
    }

    @Test func linearIgnoresMarketingPages() {
        #expect(AppLink.linear.deepLink(URL(string: "https://linear.app/pricing")!) == nil)
        #expect(AppLink.linear.deepLink(URL(string: "https://linear.app/changelog/2024-01-01-x")!) == nil)
        #expect(AppLink.linear.deepLink(URL(string: "https://evil.com/buffer/issue/ENG-1")!) == nil)
    }

    @Test func notionZoomSpotify() {
        #expect(AppLink.notion.deepLink(URL(string: "https://www.notion.so/buffer/Roadmap-0123456789abcdef0123456789abcdef?pvs=4")!)?.absoluteString
                == "notion://www.notion.so/buffer/Roadmap-0123456789abcdef0123456789abcdef?pvs=4")
        #expect(AppLink.notion.deepLink(URL(string: "https://www.notion.so/product")!) == nil)
        #expect(AppLink.zoom.deepLink(URL(string: "https://us02web.zoom.us/j/8812345678?pwd=abc")!)?.absoluteString
                == "zoommtg://zoom.us/join?action=join&confno=8812345678&pwd=abc")
        #expect(AppLink.spotify.deepLink(URL(string: "https://open.spotify.com/intl-de/track/4uLU6hMCjMI75M1A2tKUQC?si=1")!)?.absoluteString
                == "spotify:track:4uLU6hMCjMI75M1A2tKUQC")
    }

    @Test func routesToAppOnlyWhenModeAllows() {
        var s = AppSettings()
        s.rules = [Rule(conditions: [Condition(field: .host, value: "linear.app")], action: .open(browserID: chrome))]
        let deepLink = AppLink.linear.deepLink(linearURL)!
        let ctx = LinkContext(url: linearURL)

        let notRunning = RoutingEnvironment(installedBrowserIDs: installed, installedAppIDs: ["com.linear"])
        #expect(Router.decide(ctx, settings: s, environment: notRunning) == .open(BrowserTarget(browserID: chrome), ruleID: s.rules[0].id))

        let running = RoutingEnvironment(installedBrowserIDs: installed, installedAppIDs: ["com.linear"], runningAppIDs: ["com.linear"])
        #expect(Router.decide(ctx, settings: s, environment: running) == .openInApp(bundleID: "com.linear", url: deepLink))

        s.appLinkModes["linear"] = .whenInstalled
        #expect(Router.decide(ctx, settings: s, environment: notRunning) == .openInApp(bundleID: "com.linear", url: deepLink))

        s.appLinkModes["linear"] = .never
        #expect(Router.decide(ctx, settings: s, environment: running) == .open(BrowserTarget(browserID: chrome), ruleID: s.rules[0].id))

        let forced = RoutingEnvironment(installedBrowserIDs: installed, runningAppIDs: ["com.linear"], forcePicker: true)
        s.appLinkModes["linear"] = nil
        #expect(Router.decide(ctx, settings: s, environment: forced) == .ask)
    }
}

@Suite struct HistoryTests {
    private let work = LinkDestination.browser(BrowserTarget(browserID: chrome, profileID: "Profile 2"))
    private let personal = LinkDestination.browser(BrowserTarget(browserID: chrome, profileID: "Default"))

    @Test func domainStripsWWWAndIgnoresOtherSchemes() {
        #expect(LinkHistory.domain(for: URL(string: "https://WWW.GitHub.com/x")!) == "github.com")
        #expect(LinkHistory.domain(for: URL(string: "https://docs.google.com/a")!) == "docs.google.com")
        #expect(LinkHistory.domain(for: URL(string: "mailto:a@b.com")!) == nil)
    }

    @Test func remembersMostUsedDestinationWithRecencyTieBreak() {
        var h = LinkHistory()
        let t0 = Date(timeIntervalSince1970: 0)
        h.record(URL(string: "https://github.com/a")!, destination: work, at: t0)
        h.record(URL(string: "https://www.github.com/b")!, destination: personal, at: t0 + 1)
        #expect(h.records["github.com"]?.visits == 2)
        #expect(h.records["github.com"]?.preferred == personal)
        h.record(URL(string: "https://github.com/c")!, destination: work, at: t0 + 2)
        h.record(URL(string: "https://github.com/d")!, destination: personal, at: t0 + 3)
        h.record(URL(string: "https://github.com/e")!, destination: work, at: t0 + 4)
        #expect(h.record(for: URL(string: "https://github.com/z")!)?.preferred == work)
    }

    @Test func preferredBrowserSkipsAppDestinations() {
        var h = LinkHistory()
        let url = URL(string: "https://linear.app/buffer/issue/X-1")!
        h.record(url, destination: .app(bundleID: "com.linear"))
        h.record(url, destination: .app(bundleID: "com.linear"))
        h.record(url, destination: work)
        let r = h.records["linear.app"]!
        #expect(r.preferred == .app(bundleID: "com.linear"))
        #expect(r.preferredBrowser == BrowserTarget(browserID: chrome, profileID: "Profile 2"))
    }

    @Test func evictsOldestPastLimit() {
        var h = LinkHistory()
        for i in 0...LinkHistory.limit {
            h.record(URL(string: "https://d\(i).com")!, destination: work, at: Date(timeIntervalSince1970: Double(i)))
        }
        #expect(h.records.count == LinkHistory.limit)
        #expect(h.records["d0.com"] == nil)
        #expect(h.recent.first?.domain == "d\(LinkHistory.limit).com")
    }

    @Test func ruleForDomainMatchesSubdomains() {
        let rule = Rule.forAddress("github.com", to: BrowserTarget(browserID: chrome, profileID: "Profile 2"))
        #expect(rule.matches(link("https://gist.github.com/x")))
        #expect(rule.action == .open(browserID: chrome, profileID: "Profile 2"))
    }

    @Test func storeRoundTrips() throws {
        let store = HistoryStore(fileURL: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "h.json"))
        var h = LinkHistory()
        h.record(URL(string: "https://a.com")!, destination: work, at: Date(timeIntervalSince1970: 100))
        try store.save(h)
        #expect(store.load() == h)
    }
}

@Suite struct TabMatchingTests {
    private func same(_ a: String, _ b: String) -> Bool { TabMatching.same(URL(string: a)!, URL(string: b)!) }

    @Test func ignoresCosmeticDifferences() {
        #expect(same("https://www.GitHub.com/apple/swift/", "http://github.com/apple/swift"))
        #expect(same("https://linear.app/buffer/project/x/activity#project-update-1", "https://linear.app/buffer/project/x/activity"))
        #expect(same("https://a.com/p?id=1&utm_source=slack&fbclid=z", "https://a.com/p?id=1"))
    }

    @Test func keepsMeaningfulDifferences() {
        #expect(!same("https://a.com/p?id=1", "https://a.com/p?id=2"))
        #expect(!same("https://a.com/p", "https://a.com/q"))
        #expect(!same("https://a.com:8080/p", "https://a.com/p"))
        #expect(!same("https://docs.a.com/p", "https://a.com/p"))
        #expect(!same("mailto:x@a.com", "mailto:x@a.com"))
    }

    @Test func findsFrontmostMatchingTab() {
        let windows: [(id: Int, tabs: [String])] = [
            (id: 7, tabs: ["https://a.com", "https://b.com/x"]),
            (id: 3, tabs: ["https://b.com/x/", "chrome://newtab", ""]),
        ]
        let hit = TabMatching.find(URL(string: "https://b.com/x?utm_medium=email")!, in: windows)
        #expect(hit?.window == 7)
        #expect(hit?.tabIndex == 2)
        #expect(TabMatching.find(URL(string: "https://c.com")!, in: windows) == nil)
    }
}

@Suite struct PathRuleTests {
    private let personal = BrowserTarget(browserID: chrome, profileID: "Default")
    private let work = BrowserTarget(browserID: chrome, profileID: "Profile 2")

    @Test func domainAndPathRuleMatchesWholeSegmentsOnly() {
        let rule = Rule.forAddress("github.com/buffer", to: work)
        #expect(rule.conditions.map(\.field) == [.host, .path])
        #expect(rule.matches(link("https://github.com/buffer")))
        #expect(rule.matches(link("https://www.github.com/buffer/api/pull/88?w=1")))
        #expect(rule.matches(link("https://GitHub.com/Buffer/")))
        #expect(!rule.matches(link("https://github.com/buffer-labs")))
        #expect(!rule.matches(link("https://github.com/hakubo")))
        #expect(!rule.matches(link("https://gitlab.com/buffer")))
    }

    @Test func rulesFromPastedURLsAndBareDomains() {
        #expect(Rule.forAddress("https://www.github.com/hakubo/", to: nil).matches(link("https://github.com/hakubo/x")))
        let domainOnly = Rule.forAddress("github.com", to: nil)
        #expect(domainOnly.conditions.count == 1)
        #expect(domainOnly.matches(link("https://gist.github.com/a")))
    }

    @Test func linkConditionsFrom014LoadAsDomainAndPath() throws {
        let json = #"""
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Work","isEnabled":true,"matchMode":"any",
         "conditions":[{"id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","field":"address","op":"isUnder","value":"github.com/buffer"}],
         "action":{"ask":{}}}
        """#
        let rule = try JSONDecoder().decode(Rule.self, from: Data(json.utf8))
        #expect(rule.matchMode == .all)
        #expect(rule.conditions.map(\.field) == [.host, .path])
        #expect(rule.conditions.map(\.op) == [.isDomain, .isUnder])
        #expect(rule.conditions.map(\.value) == ["github.com", "/buffer"])
        #expect(rule.matches(link("https://github.com/buffer/x")))
        #expect(!rule.matches(link("https://github.com/hakubo")))
    }

    @Test func pathIsOrIsUnderWithOrWithoutSlash() {
        #expect(Condition(field: .path, op: .isUnder, value: "buffer").matches(link("https://github.com/buffer/api")))
        #expect(Condition(field: .path, op: .isUnder, value: "/buffer/").matches(link("https://github.com/buffer")))
        #expect(!Condition(field: .path, op: .isUnder, value: "/buffer").matches(link("https://github.com/bufferx")))
    }

    @Test func personalAndWorkGitHubRules() {
        var s = AppSettings()
        s.rules = [
            Rule.forAddress("github.com/hakubo", to: personal),
            Rule.forAddress("github.com/buffer", to: work),
        ]
        let env = RoutingEnvironment(installedBrowserIDs: installed, installedProfiles: [chrome: ["Default", "Profile 2"]])
        #expect(Router.decide(link("https://github.com/hakubo/TrafficControl"), settings: s, environment: env)
                == .open(personal, ruleID: s.rules[0].id))
        #expect(Router.decide(link("https://github.com/buffer/web/pull/1"), settings: s, environment: env)
                == .open(work, ruleID: s.rules[1].id))
        #expect(Router.decide(link("https://github.com/apple/swift"), settings: s, environment: env) == .ask)
    }

    @Test func pathRulesGoAboveBroaderRules() {
        let rules = [Rule.forAddress("example.com", to: nil), Rule.forAddress("github.com", to: work)]
        #expect(Rule.insertionIndex(for: "github.com/hakubo", in: rules) == 1)
        #expect(Rule.insertionIndex(for: "gitlab.com/x", in: rules) == 2)
        #expect(Rule.insertionIndex(for: "github.com", in: rules) == 2)
    }

    @Test func addressDepth() {
        let url = URL(string: "https://www.github.com/hakubo/TrafficControl/pulls")!
        #expect(LinkAddress.of(url, depth: 0) == "github.com")
        #expect(LinkAddress.of(url, depth: 1) == "github.com/hakubo")
        #expect(LinkAddress.of(url, depth: 2) == "github.com/hakubo/TrafficControl")
    }

    @Test func historyRemembersChoicePerPath() {
        var h = LinkHistory()
        let t0 = Date(timeIntervalSince1970: 0)
        for i in 0..<3 { h.record(URL(string: "https://github.com/buffer/r\(i)")!, destination: .browser(work), at: t0 + Double(i)) }
        h.record(URL(string: "https://github.com/hakubo/x")!, destination: .browser(personal), at: t0 + 10)
        #expect(h.preferred(for: URL(string: "https://github.com/hakubo/y")!) == .browser(personal))
        #expect(h.preferred(for: URL(string: "https://github.com/buffer/z")!) == .browser(work))
        #expect(h.preferred(for: URL(string: "https://github.com/apple")!) == .browser(work))
        #expect(h.records["github.com"]?.paths.map(\.segment) == ["buffer", "hakubo"])
    }

    @Test func oldHistoryWithoutPathsStillLoads() throws {
        let json = #"{"records":{"a.com":{"domain":"a.com","visits":2,"lastOpened":0,"destinations":[]}}}"#
        let h = try JSONDecoder().decode(LinkHistory.self, from: Data(json.utf8))
        #expect(h.records["a.com"]?.visits == 2)
        #expect(h.records["a.com"]?.paths.isEmpty == true)
    }
}
