import SwiftUI
import TrafficControlCore

struct RulesSettingsView: View {
    private enum Pane: String, CaseIterable {
        case rules = "Rules"
        case history = "History"
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
            HSplitView {
                VStack(spacing: 0) {
                    Picker("", selection: $pane) {
                        ForEach(Pane.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(8)

                    switch pane {
                    case .rules: rulesList
                    case .history: HistoryList(selection: $domainSelection, onCreateRule: createRule(address:target:))
                    }
                }
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 420)

                Group {
                    switch pane {
                    case .rules: ruleDetail
                    case .history: domainDetail
                    }
                }
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack {
                TextField("Try a link, e.g. https://github.com/apple/swift", text: $testURL)
                    .textFieldStyle(.roundedBorder)
                Text(testResult).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
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
            .onDeleteCommand { removeSelected() }
            Divider()
            HStack(spacing: 2) {
                Button {
                    addRule()
                } label: {
                    Image(systemName: "plus").frame(width: 20, height: 20)
                }
                Button {
                    removeSelected()
                } label: {
                    Image(systemName: "minus").frame(width: 20, height: 20)
                }
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
                    Button("Pick from History") { pane = .history }
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
                }
            )
            .id(domain)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath").font(.largeTitle).foregroundStyle(.tertiary)
                Text(
                    history.history.records.isEmpty
                        ? "Domains of the links you open will show up here."
                        : "Pick a domain to see where its links went, or click ＋ to make it a rule."
                )
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
                BrowserIcon(
                    browser: browser, hasProfile: profileID != nil,
                    avatar: ImageCache.avatar(atPath: profile?.avatarPath), size: 24)
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
            filled[1].field == .path, filled[1].op == .isUnder
        {
            let path = filled[1].value.hasPrefix("/") ? filled[1].value : "/" + filled[1].value
            return first.value + path
        }
        let text: String =
            switch (first.field, first.op) {
            case (.address, .isUnder), (.host, .isDomain): first.value
            default: "\(first.field.label) \(first.op.label) \(first.value)"
            }
        return filled.count > 1 ? "\(text), +\(filled.count - 1) more" : text
    }
}
