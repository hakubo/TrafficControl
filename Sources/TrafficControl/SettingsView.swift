import SwiftUI
import TrafficControlCore

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView().tabItem { Label("General", systemImage: "gearshape") }
            BrowsersSettingsView().tabItem { Label("Browsers", systemImage: "safari") }
            RulesSettingsView().tabItem { Label("Rules", systemImage: "list.bullet.rectangle") }
            AppsSettingsView().tabItem { Label("Apps", systemImage: "app.badge") }
        }
        .frame(minWidth: 760, minHeight: 500)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @EnvironmentObject private var model: SettingsModel
    @EnvironmentObject private var browsers: BrowserManager
    @EnvironmentObject private var updater: UpdaterModel
    @State private var isDefault = DefaultBrowser.isDefault
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section("Default browser") {
                HStack {
                    Image(systemName: isDefault ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(isDefault ? .green : .orange)
                    Text(isDefault
                         ? "TrafficControl is your default browser."
                         : "TrafficControl only sees links once it is your default browser.")
                    Spacer()
                    if !isDefault {
                        Button("Make Default") {
                            DefaultBrowser.makeDefault { isDefault = DefaultBrowser.isDefault }
                        }
                    }
                }
            }

            Section("When no rule matches") {
                Picker("Behavior", selection: $model.settings.defaultBehavior) {
                    ForEach(DefaultBehavior.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Primary browser", selection: $model.settings.primaryBrowser) {
                    Text("None").tag(BrowserTarget?.none)
                    ForEach(browsers.menuChoices(model.settings)) { Text($0.menuTitle).tag(BrowserTarget?.some($0.target)) }
                }
                Text("If the behavior can't pick a browser, the picker is shown.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Picker("If the link is already open in a tab", selection: $model.settings.tabReuse) {
                    ForEach(TabReuseMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Open tabs")
            } footer: {
                Text("Works with Safari and Chrome-based browsers (Chrome, Brave, Edge, Vivaldi, Chromium). macOS asks once per browser whether TrafficControl may control it. Hold ⌥ Option to skip the check.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Picker") {
                Toggle("Show the link address", isOn: $model.settings.showURLInPicker)
                Toggle("Hold ⌥ Option while clicking a link to always show the picker",
                       isOn: $model.settings.forcePickerWithOption)
            }

            Section("App") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { LoginItem.setEnabled($0); launchAtLogin = LoginItem.isEnabled }))
                Toggle("Show menu bar icon", isOn: $model.settings.showMenuBarIcon)
                if !model.settings.showMenuBarIcon {
                    Text("Open TrafficControl from Finder or Spotlight to get back here.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if updater.isAvailable {
                Section("Updates") {
                    Toggle("Check for updates automatically", isOn: Binding(
                        get: { updater.automaticallyChecks },
                        set: { updater.automaticallyChecks = $0 }))
                    Toggle("Download and install updates automatically", isOn: Binding(
                        get: { updater.automaticallyDownloads },
                        set: { updater.automaticallyDownloads = $0 }))
                        .disabled(!updater.automaticallyChecks)
                    HStack {
                        if let last = updater.lastCheck {
                            Text("Last checked \(last.formatted(.relative(presentation: .named)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Check Now") { updater.checkForUpdates() }
                    }
                }
            }

            Section("About") {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TrafficControl").font(.headline)
                        Text("Version \(appVersion)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Website") { NSWorkspace.shared.open(Links.website) }
                    Button("GitHub") { NSWorkspace.shared.open(Links.repository) }
                }
                HStack {
                    Text("TrafficControl is free. If it saves you some tab juggling, you can buy me a coffee.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Buy Me a Coffee") { NSWorkspace.shared.open(Links.buyMeACoffee) }
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isDefault = DefaultBrowser.isDefault
            launchAtLogin = LoginItem.isEnabled
        }
    }
}

private var appVersion: String {
    let info = Bundle.main.infoDictionary
    let version = info?["CFBundleShortVersionString"] as? String ?? "–"
    let build = info?["CFBundleVersion"] as? String
    return build.map { "\(version) (\($0))" } ?? version
}

// MARK: - Browsers

struct BrowsersSettingsView: View {
    @EnvironmentObject private var model: SettingsModel
    @EnvironmentObject private var browsers: BrowserManager

    var body: some View {
        let ordered = browsers.ordered(model.settings, includeHidden: true)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Drag to set the order in the picker. Uncheck browsers or profiles you don't want to see.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") { browsers.refresh() }
            }
            List {
                ForEach(ordered) { browser in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 10) {
                            Toggle("", isOn: visibility(of: browser.id)).labelsHidden()
                            Image(nsImage: browser.icon).resizable().frame(width: 28, height: 28)
                            VStack(alignment: .leading) {
                                Text(browser.name)
                                Text(browser.id).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.settings.primaryBrowser?.browserID == browser.id {
                                Text("Primary").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        ForEach(browsers.selectableProfiles(for: browser.id)) { profile in
                            HStack(spacing: 8) {
                                Toggle("", isOn: visibility(of: BrowserTarget(browserID: browser.id, profileID: profile.id)))
                                    .labelsHidden()
                                Text(profile.name)
                                if let user = profile.userName {
                                    Text(user).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.leading, 62)
                            .disabled(model.settings.hiddenBrowserIDs.contains(browser.id))
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onMove { from, to in
                    var ids = ordered.map(\.id)
                    ids.move(fromOffsets: from, toOffset: to)
                    model.settings.browserOrder = ids
                }
            }
        }
        .padding()
    }

    private func visibility(of target: BrowserTarget) -> Binding<Bool> {
        Binding(
            get: { !model.settings.hiddenProfiles.contains(target) },
            set: { visible in
                model.settings.hiddenProfiles.removeAll { $0 == target }
                if !visible { model.settings.hiddenProfiles.append(target) }
            })
    }

    private func visibility(of id: String) -> Binding<Bool> {
        Binding(
            get: { !model.settings.hiddenBrowserIDs.contains(id) },
            set: { visible in
                model.settings.hiddenBrowserIDs.removeAll { $0 == id }
                if !visible { model.settings.hiddenBrowserIDs.append(id) }
            })
    }
}

// MARK: - Apps

struct AppsSettingsView: View {
    @EnvironmentObject private var model: SettingsModel
    @EnvironmentObject private var browsers: BrowserManager

    var body: some View {
        Form {
            Section {
                ForEach(AppLink.all) { app in
                    let appURL = browsers.appURL(for: app.bundleID)
                    HStack(spacing: 10) {
                        Group {
                            if let appURL {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path)).resizable()
                            } else {
                                Image(systemName: "app.dashed").resizable().foregroundStyle(.tertiary)
                            }
                        }
                        .frame(width: 28, height: 28)
                        VStack(alignment: .leading) {
                            Text(app.name)
                            Text(appURL == nil ? "Not installed" : app.summary)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: mode(of: app.id)) {
                            ForEach(AppLinkMode.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .disabled(appURL == nil)
                    }
                }
            } header: {
                Text("Open links in desktop apps")
            } footer: {
                Text("These are checked before your rules. Hold ⌥ Option while clicking to get the picker instead; the app is offered there too.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func mode(of id: String) -> Binding<AppLinkMode> {
        Binding(
            get: { model.settings.appLinkMode(for: id) },
            set: { model.settings.appLinkModes[id] = $0 })
    }
}

// MARK: - Rules

struct RulesSettingsView: View {
    private enum Pane: String, CaseIterable {
        case rules = "Rules"
        case domains = "Recent Domains"
    }

    @EnvironmentObject private var model: SettingsModel
    @EnvironmentObject private var browsers: BrowserManager
    @EnvironmentObject private var history: HistoryModel
    @State private var pane = Pane.rules
    @State private var selection: Rule.ID?
    @State private var domainSelection: String?
    @State private var testURL = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    Picker("", selection: $pane) {
                        ForEach(Pane.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(8)

                    switch pane {
                    case .rules: rulesList
                    case .domains: RecentDomainsList(selection: $domainSelection, onCreateRule: createRule(address:target:))
                    }
                }
                .frame(width: 260)

                Divider()

                switch pane {
                case .rules: ruleDetail
                case .domains: domainDetail
                }
            }
            Divider()
            HStack {
                TextField("Try a link, e.g. https://github.com/apple/swift", text: $testURL)
                    .textFieldStyle(.roundedBorder)
                Text(testResult).foregroundStyle(.secondary).lineLimit(1)
                if let url = testedURL {
                    Menu("Create Rule") {
                        ForEach(ruleScopes(for: url), id: \.self) { address in
                            Button(address) { createRule(address: address, target: suggestedTarget(for: url)) }
                        }
                    }
                    .fixedSize()
                    .help("Make a rule for this link's domain or one of its paths")
                }
            }
            .padding(10)
        }
    }

    private var rulesList: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach($model.settings.rules) { $rule in
                    HStack {
                        Toggle("", isOn: $rule.isEnabled).labelsHidden()
                        Text(rule.name.isEmpty ? "Untitled rule" : rule.name)
                            .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                    }
                    .tag(rule.id)
                }
                .onMove { model.settings.rules.move(fromOffsets: $0, toOffset: $1) }
            }
            Divider()
            HStack(spacing: 2) {
                Button { addRule() } label: { Image(systemName: "plus").frame(width: 20, height: 20) }
                Button { removeSelected() } label: { Image(systemName: "minus").frame(width: 20, height: 20) }
                    .disabled(selection == nil)
                Spacer()
                Text("First match wins").font(.caption).foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .padding(6)
        }
    }

    @ViewBuilder
    private var ruleDetail: some View {
        if let binding = binding(for: selection) {
            RuleEditor(rule: binding)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch").font(.largeTitle).foregroundStyle(.tertiary)
                Text("Rules send matching links straight to a browser.").foregroundStyle(.secondary)
                HStack {
                    Button("Add Rule") { addRule() }
                    Button("Pick from Recent Domains") { pane = .domains }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var domainDetail: some View {
        if let domain = domainSelection, let record = history.history.records[domain] {
            DomainDetailView(
                record: record,
                onCreateRule: createRule(address:target:),
                onShowRule: { rule in
                    selection = rule.id
                    pane = .rules
                },
                onRemove: {
                    history.remove(domain)
                    domainSelection = nil
                })
            .id(domain)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath").font(.largeTitle).foregroundStyle(.tertiary)
                Text(history.history.records.isEmpty
                     ? "Domains of the links you open will show up here."
                     : "Pick a domain to see where its links went, or click ＋ to make it a rule.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Adds a rule for a domain or path; path rules go above broader rules that would hide them.
    private func createRule(address: String, target: BrowserTarget?) {
        let rule = Rule.forAddress(address, to: target)
        model.settings.rules.insert(rule, at: Rule.insertionIndex(for: address, in: model.settings.rules))
        selection = rule.id
        pane = .rules
    }

    private var testedURL: URL? {
        let trimmed = testURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), LinkAddress.of(url) != nil else { return nil }
        return url
    }

    /// "github.com", "github.com/hakubo", "github.com/hakubo/TrafficControl" for the tested link.
    private func ruleScopes(for url: URL) -> [String] {
        let depth = min(2, LinkAddress.segments(of: url).count)
        return (0...depth).compactMap { LinkAddress.of(url, depth: $0) }
    }

    /// What you usually pick for this link, else the first browser in the picker.
    private func suggestedTarget(for url: URL) -> BrowserTarget? {
        if case .browser(let target) = history.history.preferred(for: url) { return target }
        return browsers.pickerChoices(model.settings).first?.target
    }

    private var testResult: String {
        let trimmed = testURL.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        guard let url = URL(string: trimmed), url.host() != nil else { return "Not a valid link" }
        if let (app, _) = AppLink.first(for: url), model.settings.appLinkMode(for: app.id) != .never {
            let when = model.settings.appLinkMode(for: app.id) == .whenRunning ? "if running" : "if installed"
            return "\(app.name) app (\(when)); else: " + ruleResult(url)
        }
        return ruleResult(url)
    }

    private func ruleResult(_ url: URL) -> String {
        guard let rule = Router.firstMatchingRule(LinkContext(url: url), in: model.settings.rules) else {
            return "No rule matches → default behavior"
        }
        let name = rule.name.isEmpty ? "Untitled rule" : rule.name
        switch rule.action {
        case .ask: return "“\(name)” → show picker"
        case .open(let id, let profile):
            return "“\(name)” → \(browsers.title(for: BrowserTarget(browserID: id, profileID: profile)))"
        }
    }

    private func binding(for id: Rule.ID?) -> Binding<Rule>? {
        guard let id, let index = model.settings.rules.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { model.settings.rules.indices.contains(index) ? model.settings.rules[index] : Rule() },
            set: { new in
                if let i = model.settings.rules.firstIndex(where: { $0.id == id }) { model.settings.rules[i] = new }
            })
    }

    private func addRule() {
        let first = browsers.pickerChoices(model.settings).first
        let rule = Rule(name: "New rule", action: first.map { .open(browserID: $0.browser.id, profileID: $0.profile?.id) } ?? .ask)
        model.settings.rules.append(rule)
        selection = rule.id
    }

    private func removeSelected() {
        guard let selection else { return }
        model.settings.rules.removeAll { $0.id == selection }
        self.selection = nil
    }
}

private struct RuleEditor: View {
    @Binding var rule: Rule
    @EnvironmentObject private var model: SettingsModel
    @EnvironmentObject private var browsers: BrowserManager

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $rule.name)
                Picker("If", selection: $rule.matchMode) {
                    Text("all conditions match").tag(MatchMode.all)
                    Text("any condition matches").tag(MatchMode.any)
                }
            }

            Section("Conditions") {
                ForEach($rule.conditions) { $condition in
                    HStack {
                        Picker("", selection: $condition.field) {
                            ForEach(ConditionField.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                        Picker("", selection: $condition.op) {
                            ForEach(condition.field.operators, id: \.self) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                        TextField("", text: $condition.value, prompt: Text(condition.field.placeholder))
                            .labelsHidden()
                        Button {
                            rule.conditions.removeAll { $0.id == condition.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                    .onChange(of: condition.field) { _, field in
                        if !field.operators.contains(condition.op) { $condition.op.wrappedValue = field.operators[0] }
                    }
                }
                Button("Add Condition") { rule.conditions.append(Condition()) }
            }

            Section("Then") {
                Picker("Open with", selection: $rule.action) {
                    Text("Show the picker").tag(RuleAction.ask)
                    Divider()
                    ForEach(browsers.menuChoices(model.settings)) { choice in
                        Text(choice.menuTitle).tag(RuleAction.open(browserID: choice.browser.id, profileID: choice.profile?.id))
                    }
                    if case .open(let id, let profile) = rule.action, !isListed(id, profile) {
                        Text("\(browsers.title(for: BrowserTarget(browserID: id, profileID: profile))) (missing)").tag(rule.action)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func isListed(_ browserID: String, _ profileID: String?) -> Bool {
        let target = BrowserTarget(browserID: browserID, profileID: profileID)
        return browsers.menuChoices(model.settings).contains { $0.target == target }
    }
}
