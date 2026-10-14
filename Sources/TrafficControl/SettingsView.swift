import SwiftUI
import TrafficControlCore

/// The sections of the Settings window, shown in its sidebar.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, browsers, rules, apps, updates

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .browsers: "Browsers"
        case .rules: "Rules"
        case .apps: "Apps"
        case .updates: "Software Update"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .browsers: "globe"
        case .rules: "arrow.triangle.branch"
        case .apps: "square.grid.2x2.fill"
        case .updates: "arrow.triangle.2.circlepath"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .browsers: .blue
        case .rules: .purple
        case .apps: .orange
        case .updates: .green
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var updater: UpdaterModel
    @EnvironmentObject private var defaultStatus: DefaultBrowserStatus
    @State private var pane: SettingsPane? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $pane) {
                Section {
                    ForEach([SettingsPane.general, .browsers, .rules, .apps]) { sidebarRow($0) }
                }
                if updater.isAvailable {
                    Section { sidebarRow(.updates) }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch pane ?? .general {
                case .general: GeneralSettingsView()
                case .browsers: BrowsersSettingsView()
                case .rules: RulesSettingsView()
                case .apps: AppsSettingsView()
                case .updates: UpdatesSettingsView()
                }
            }
            .background(WindowTitle(title: (pane ?? .general).title))
        }
        .frame(minWidth: 780, minHeight: 520)
    }

    private func sidebarRow(_ pane: SettingsPane) -> some View {
        NavigationLink(value: pane) {
            HStack {
                Label { Text(pane.title) } icon: { IconTile(symbol: pane.symbol, tint: pane.tint) }
                Spacer()
                if pane == .general && !defaultStatus.isDefault {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.white, .orange)
                        .help("TrafficControl isn't your default browser")
                }
            }
        }
    }
}

/// Shows the selected pane's name in the title bar, as System Settings does.
private struct WindowTitle: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { view.window?.title = title }
    }
}

/// A white SF Symbol on a rounded, tinted square, like the icons in System Settings.
struct IconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(tint.gradient))
            .shadow(color: .black.opacity(0.12), radius: 0.5, y: 0.5)
    }
}

/// The centered icon, title and blurb at the top of a pane.
struct PaneHeader<Icon: View, Accessory: View>: View {
    let title: String
    let message: String
    @ViewBuilder var icon: Icon
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(spacing: 6) {
            icon.padding(.bottom, 4)
            Text(title).font(.title2.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
            accessory.padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

extension PaneHeader where Icon == IconTile {
    init(_ pane: SettingsPane, message: String, @ViewBuilder accessory: () -> Accessory) {
        self.init(title: pane.title, message: message,
                  icon: { IconTile(symbol: pane.symbol, tint: pane.tint, size: 56) }, accessory: accessory)
    }
}

extension PaneHeader where Icon == IconTile, Accessory == EmptyView {
    init(_ pane: SettingsPane, message: String) {
        self.init(pane, message: message) { EmptyView() }
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @EnvironmentObject private var model: SettingsModel
    @EnvironmentObject private var browsers: BrowserManager
    @EnvironmentObject private var defaultStatus: DefaultBrowserStatus
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section {
                PaneHeader(title: "TrafficControl", message: defaultStatus.isDefault
                           ? "Every link you click passes through here and goes to the right place."
                           : "TrafficControl only sees links once it is your default browser.") {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                } accessory: {
                    VStack(spacing: 12) {
                        if defaultStatus.isDefault {
                            Label("Default browser", systemImage: "checkmark.circle.fill")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.green)
                        } else {
                            Button("Make Default Browser") {
                                defaultStatus.makeDefault()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                        HStack(spacing: 6) {
                            Text("Version \(appVersion)")
                            Text("·")
                            Button("Website") { NSWorkspace.shared.open(Links.website) }
                            Text("·")
                            Button("GitHub") { NSWorkspace.shared.open(Links.repository) }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .buttonStyle(.link)
                    }
                }
            }

            Section {
                Picker(selection: $model.settings.defaultBehavior) {
                    ForEach(DefaultBehavior.allCases, id: \.self) { Text($0.label).tag($0) }
                } label: {
                    Text("Behavior")
                    Text("What happens to a link that no rule claims")
                }
                Picker(selection: $model.settings.primaryBrowser) {
                    Text("None").tag(BrowserTarget?.none)
                    ForEach(browsers.menuChoices(model.settings)) { Text($0.menuTitle).tag(BrowserTarget?.some($0.target)) }
                } label: {
                    Text("Primary browser")
                    Text("If the behavior can't pick a browser, the picker is shown")
                }
            } header: {
                Text("When no rule matches")
            }

            Section {
                Picker(selection: $model.settings.tabReuse) {
                    ForEach(TabReuseMode.allCases, id: \.self) { Text($0.label).tag($0) }
                } label: {
                    Text("Link already open in a tab")
                    Text("Hold \(model.settings.pickerModifier.symbol) \(model.settings.pickerModifier.name) while clicking to skip the check")
                }
            } header: {
                Text("Open tabs")
            } footer: {
                Text("Works with Safari and Chrome-based browsers (Chrome, Brave, Edge, Vivaldi, Chromium). macOS asks once per browser whether TrafficControl may control it.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Picker") {
                Toggle(isOn: $model.settings.showURLInPicker) {
                    Text("Show the link address")
                    Text("See where a link goes before choosing a browser")
                }
                Toggle(isOn: $model.settings.forcePickerWithOption) {
                    Text("Hold a key while clicking a link to always show the picker")
                    Text("Skips rules, desktop apps and open tabs so you can choose by hand")
                }
                if model.settings.forcePickerWithOption {
                    Picker(selection: $model.settings.pickerModifier) {
                        // No ⌃ Control: Control-click is a right-click on macOS.
                        ForEach([ModifierKey.shift, .option, .command], id: \.self) { key in
                            Text("\(key.symbol) \(key.name)").tag(key)
                        }
                    } label: {
                        Text("Key")
                        Text("Some apps use ⌥-click themselves (Slack marks the message unread), so pick another key if it does nothing there")
                    }
                }
            }

            Section("App") {
                Toggle(isOn: Binding(
                    get: { launchAtLogin },
                    set: { LoginItem.setEnabled($0); launchAtLogin = LoginItem.isEnabled })) {
                    Text("Launch at login")
                    Text("Open TrafficControl automatically when you log in")
                }
                Toggle(isOn: $model.settings.showMenuBarIcon) {
                    Text("Show menu bar icon")
                    Text(model.settings.showMenuBarIcon
                         ? "Quick access to Settings and recent links"
                         : "Open TrafficControl from Finder or Spotlight to get back here")
                }
            }

            Section {
                HStack(spacing: 12) {
                    IconTile(symbol: "cup.and.saucer.fill", tint: .brown, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TrafficControl is free")
                        Text("If it saves you some tab juggling, you can buy me a coffee.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Buy Me a Coffee") { NSWorkspace.shared.open(Links.buyMeACoffee) }
                }
                .padding(.vertical, 2)
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin = LoginItem.isEnabled
        }
    }
}

// MARK: - Software Update

struct UpdatesSettingsView: View {
    @EnvironmentObject private var updater: UpdaterModel

    var body: some View {
        Form {
            Section {
                PaneHeader(.updates, message: updater.lastCheck.map {
                    "TrafficControl \(appVersion). Last checked \($0.formatted(.relative(presentation: .named)))."
                } ?? "TrafficControl \(appVersion).") {
                    Button("Check Now") { updater.checkForUpdates() }
                }
            }

            Section {
                Toggle(isOn: Binding(
                    get: { updater.automaticallyChecks },
                    set: { updater.automaticallyChecks = $0 })) {
                    Text("Check for updates automatically")
                    Text("Look for a new version once a day")
                }
                Toggle(isOn: Binding(
                    get: { updater.automaticallyDownloads },
                    set: { updater.automaticallyDownloads = $0 })) {
                    Text("Download and install automatically")
                    Text("Updates are applied the next time TrafficControl starts")
                }
                .disabled(!updater.automaticallyChecks)
            }
        }
        .formStyle(.grouped)
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
        let choices = browsers.orderedChoices(model.settings, includeHidden: true)
        Form {
            Section {
                PaneHeader(.browsers, message: "Drag to set the order in the picker. Turn off browsers or profiles you don't want to see.")
            }

            Section {
                ReorderableChoiceList(
                    choices: choices,
                    row: { choice in
                        BrowserChoiceRow(
                            choice: choice,
                            isVisible: visibility(of: choice, among: choices),
                            isPrimary: isPrimary(choice))
                    },
                    onReorder: { model.settings.choiceOrder = $0.map(\.target) })
                .listRowInsets(EdgeInsets())
            } footer: {
                HStack {
                    Text("Each profile of Chrome, Brave, Edge or Vivaldi is its own entry.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh") { browsers.refresh() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func isPrimary(_ choice: BrowserChoice) -> Bool {
        guard let primary = model.settings.primaryBrowser, primary.browserID == choice.browser.id else { return false }
        return primary.profileID == nil || primary == choice.target
    }

    private func visibility(of choice: BrowserChoice, among choices: [BrowserChoice]) -> Binding<Bool> {
        let siblings = choices.filter { $0.browser.id == choice.browser.id }.map(\.target)
        return Binding(
            get: { !model.settings.isHidden(choice.target) },
            set: { model.settings.setHidden(!$0, choice.target, siblings: siblings) })
    }
}

/// Rows that reorder by dragging vertically: the grabbed row follows the pointer (up and down only,
/// within the list) while the others slide aside, and the new order is saved on release.
/// One view rather than a row per entry, because grouped forms ignore `onMove`.
private struct ReorderableChoiceList<Row: View>: View {
    let choices: [BrowserChoice]
    @ViewBuilder let row: (BrowserChoice) -> Row
    let onReorder: ([BrowserChoice]) -> Void

    private let rowHeight: CGFloat = 52
    @State private var dragged: String?
    @State private var translation: CGFloat = 0

    var body: some View {
        let order = displayOrder
        VStack(spacing: 0) {
            ForEach(Array(order.enumerated()), id: \.element.id) { index, choice in
                let isDragged = choice.id == dragged
                row(choice)
                    .padding(.horizontal, 10)
                    .frame(height: rowHeight)
                    .background {
                        if isDragged {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.background)
                                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                        }
                    }
                    .overlay(alignment: .top) {
                        if index > 0 && !isDragged && order[index - 1].id != dragged {
                            Divider().padding(.leading, 64)
                        }
                    }
                    .opacity(isDragged ? 0.85 : 1)
                    .offset(y: isDragged ? draggedOffset(at: index) : 0)
                    .zIndex(isDragged ? 1 : 0)
                    // The grabbed row tracks the pointer exactly; only the rows making room animate.
                    .transaction { if isDragged { $0.animation = nil } }
                    .contentShape(Rectangle())
                    .gesture(drag(choice))
            }
        }
        .animation(.easeOut(duration: 0.15), value: order.map(\.id))
        .coordinateSpace(.named(Self.space))
    }

    /// Measured against the list, not the row: the row moves with the pointer, so its own
    /// coordinates would only report half the movement.
    private static var space: String { "ReorderableChoiceList" }

    private func drag(_ choice: BrowserChoice) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if dragged == nil { dragged = choice.id }
                translation = value.translation.height
            }
            .onEnded { _ in
                let order = displayOrder
                withAnimation(.easeOut(duration: 0.15)) {
                    dragged = nil
                    translation = 0
                    if order.map(\.id) != choices.map(\.id) { onReorder(order) }
                }
            }
    }

    private var startIndex: Int? { choices.firstIndex { $0.id == dragged } }

    /// The pointer's movement, kept inside the list.
    private var clampedTranslation: CGFloat {
        guard let start = startIndex else { return 0 }
        let up = -CGFloat(start) * rowHeight
        let down = CGFloat(choices.count - 1 - start) * rowHeight
        return min(max(translation, up), down)
    }

    /// `choices` with the dragged row moved to the slot under the pointer.
    private var displayOrder: [BrowserChoice] {
        guard let start = startIndex else { return choices }
        let target = start + Int((clampedTranslation / rowHeight).rounded())
        var order = choices
        order.insert(order.remove(at: start), at: target)
        return order
    }

    /// Keeps the dragged row under the pointer even though its slot has moved.
    private func draggedOffset(at index: Int) -> CGFloat {
        guard let start = startIndex else { return 0 }
        return clampedTranslation - CGFloat(index - start) * rowHeight
    }
}

/// A browser's icon; for a profile, with the profile's avatar (or a generic one) in the corner.
struct BrowserIcon: View {
    let browser: Browser
    var hasProfile = false
    var avatar: NSImage?
    var size: CGFloat = 32

    var body: some View {
        Image(nsImage: browser.icon)
            .resizable()
            .frame(width: size, height: size)
            .overlay(alignment: .bottomTrailing) {
                if hasProfile {
                    Group {
                        if let avatar {
                            Image(nsImage: avatar).resizable().scaledToFill()
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .foregroundStyle(.white, .gray)
                        }
                    }
                    .frame(width: size / 2, height: size / 2)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                    .offset(x: size / 8, y: size / 8)
                }
            }
    }
}

/// One picker entry: a browser, or one profile of it with the profile's avatar on the browser icon.
private struct BrowserChoiceRow: View {
    let choice: BrowserChoice
    @Binding var isVisible: Bool
    let isPrimary: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .help("Drag to reorder")
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(choice.title)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if isPrimary {
                Text("Primary")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(.tint.opacity(0.12), in: Capsule())
            }
            Toggle("", isOn: $isVisible)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .opacity(isVisible ? 1 : 0.55)
    }

    private var subtitle: String {
        guard let profile = choice.profile else { return choice.browser.id }
        return [choice.browser.name, profile.userName].compactMap { $0 }.joined(separator: " · ")
    }

    private var icon: some View {
        BrowserIcon(browser: choice.browser, hasProfile: choice.profile != nil, avatar: choice.avatar)
    }
}

// MARK: - Apps

struct AppsSettingsView: View {
    @EnvironmentObject private var model: SettingsModel
    @EnvironmentObject private var browsers: BrowserManager

    var body: some View {
        Form {
            Section {
                PaneHeader(.apps, message: "Open links in the desktop app instead of a browser tab. These are checked before your rules.")
            }

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
                        .frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 1) {
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
                    .opacity(appURL == nil ? 0.6 : 1)
                }
            } footer: {
                Text("Hold \(model.settings.pickerModifier.symbol) \(model.settings.pickerModifier.name) while clicking to get the picker instead; the app is offered there too.")
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
        case domains = "History"
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
                    RuleRow(rule: $rule).tag(rule.id)
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
                    Button("Pick from History") { pane = .domains }
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

/// A rule in the list: where it sends links (as an icon), its name, what it matches, and an on/off switch.
private struct RuleRow: View {
    @Binding var rule: Rule
    @EnvironmentObject private var browsers: BrowserManager

    var body: some View {
        HStack(spacing: 10) {
            destinationIcon
                .help(destinationTitle)
            VStack(alignment: .leading, spacing: 1) {
                Text(rule.name.isEmpty ? "Untitled rule" : rule.name)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Toggle("", isOn: $rule.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help(rule.isEnabled ? "Turn this rule off" : "Turn this rule on")
        }
        .padding(.vertical, 3)
        .opacity(rule.isEnabled ? 1 : 0.5)
    }

    @ViewBuilder
    private var destinationIcon: some View {
        switch rule.action {
        case .ask:
            IconTile(symbol: "list.bullet", tint: .gray, size: 24)
        case .open(let id, let profileID):
            if let browser = browsers.browser(withID: id) {
                let profile = profileID.flatMap { p in browsers.profiles[id]?.first { $0.id == p } }
                BrowserIcon(browser: browser, hasProfile: profileID != nil,
                            avatar: profile?.avatarPath.flatMap(NSImage.init(contentsOfFile:)), size: 24)
            } else {
                IconTile(symbol: "questionmark", tint: .orange, size: 24)
            }
        }
    }

    private var destinationTitle: String {
        switch rule.action {
        case .ask: "Shows the picker"
        case .open(let id, let profile): "Opens in \(browsers.title(for: BrowserTarget(browserID: id, profileID: profile)))"
        }
    }

    /// What the rule matches, or where it sends links when the name already says what it matches.
    private var subtitle: String {
        let name = rule.name.trimmingCharacters(in: .whitespaces).lowercased()
        let what = summary
        guard name == what.lowercased() || what.lowercased().hasPrefix(name + ",") else { return what }
        return destinationTitle
    }

    /// "github.com/hakubo", "Source app is Slack", "buffer.com, +1 more".
    private var summary: String {
        let filled = rule.conditions.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let first = filled.first else { return "No conditions yet" }
        // Domain + path rules, as Create Rule makes them, read as one address: "github.com/buffer".
        if filled.count == 2, rule.matchMode == .all, first.field == .host, first.op == .isDomain,
           filled[1].field == .path, filled[1].op == .isUnder {
            let path = filled[1].value.hasPrefix("/") ? filled[1].value : "/" + filled[1].value
            return first.value + path
        }
        let text: String = switch (first.field, first.op) {
        case (.address, .isUnder), (.host, .isDomain): first.value
        default: "\(first.field.label) \(first.op.label) \(first.value)"
        }
        return filled.count > 1 ? "\(text), +\(filled.count - 1) more" : text
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
                            // A 0.1.4 Link condition that couldn't be split keeps showing as Link.
                            ForEach(ConditionField.selectable + (condition.field == .address ? [.address] : []), id: \.self) {
                                Text($0.label).tag($0)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                        Picker("", selection: $condition.op) {
                            ForEach(condition.field.operators, id: \.self) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                        if condition.field == .modifiers {
                            KeyToggles(value: $condition.value)
                        } else {
                            TextField("", text: $condition.value, prompt: Text(condition.field.placeholder))
                                .labelsHidden()
                        }
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
                if let clash = pickerKeyClash {
                    Text("Holding \(clash.symbol) \(clash.name) shows the picker instead (Settings → General), so this rule never runs with it held. Pick another key here or there.")
                        .font(.caption).foregroundStyle(.orange)
                }
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

    /// The picker key, if this rule needs it held: the picker would always win.
    private var pickerKeyClash: ModifierKey? {
        guard model.settings.forcePickerWithOption else { return nil }
        let key = model.settings.pickerModifier
        let needsKey = rule.conditions.contains { $0.field == .modifiers && ModifierKey.parse($0.value).contains(key) }
        return needsKey ? key : nil
    }

    private func isListed(_ browserID: String, _ profileID: String?) -> Bool {
        let target = BrowserTarget(browserID: browserID, profileID: profileID)
        return browsers.menuChoices(model.settings).contains { $0.target == target }
    }
}

/// ⌃ ⌥ ⇧ ⌘ buttons that edit a Keys held condition's value ("⌥⌘").
private struct KeyToggles: View {
    @Binding var value: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ModifierKey.allCases, id: \.self) { key in
                Toggle(isOn: Binding(
                    get: { ModifierKey.parse(value).contains(key) },
                    set: { on in
                        var keys = ModifierKey.parse(value)
                        if on { keys.insert(key) } else { keys.remove(key) }
                        value = ModifierKey.symbols(keys)
                    })
                ) {
                    Text(key.symbol).font(.system(size: 13, weight: .medium)).frame(minWidth: 18)
                }
                .toggleStyle(.button)
                .help(key.name)
            }
            Spacer(minLength: 0)
        }
    }
}
