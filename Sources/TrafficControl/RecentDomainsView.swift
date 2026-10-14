import SwiftUI
import TrafficControlCore

/// The sidebar list of domains you've opened links on, each one a click away from becoming a rule.
struct RecentDomainsList: View {
    @Binding var selection: String?
    let onCreateRule: (DomainRecord, BrowserTarget?) -> Void
    @EnvironmentObject private var model: SettingsModel
    @EnvironmentObject private var browsers: BrowserManager
    @EnvironmentObject private var history: HistoryModel
    @State private var filter = ""

    var body: some View {
        VStack(spacing: 0) {
            TextField("Filter", text: $filter)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            List(selection: $selection) {
                ForEach(records) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(record.domain).lineLimit(1)
                            Text(subtitle(for: record))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if coveringRule(for: record.domain, in: model.settings.rules) != nil {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(.secondary)
                                .help("A rule already handles this domain")
                        } else {
                            Button { onCreateRule(record, record.preferredBrowser) } label: {
                                Image(systemName: "plus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Create a rule for \(record.domain)")
                        }
                    }
                    .tag(record.domain)
                }
            }
            Divider()
            HStack {
                Toggle("Remember", isOn: $model.settings.rememberDomains)
                    .toggleStyle(.checkbox)
                    .help("Keep a list of domains you open links on")
                Spacer()
                Button("Clear") {
                    history.clear()
                    selection = nil
                }
                .disabled(history.history.records.isEmpty)
            }
            .controlSize(.small)
            .padding(6)
        }
    }

    private var records: [DomainRecord] {
        let all = history.history.recent
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return needle.isEmpty ? all : all.filter { $0.domain.contains(needle) }
    }

    private func subtitle(for record: DomainRecord) -> String {
        let usual = record.preferred.map { browsers.title(for: $0) } ?? "–"
        return "\(record.visits)× · \(usual)"
    }
}

/// Details for one domain: where its links went, and a rule to make that permanent.
struct DomainDetailView: View {
    let record: DomainRecord
    let onCreateRule: (DomainRecord, BrowserTarget?) -> Void
    let onShowRule: (Rule) -> Void
    let onRemove: () -> Void
    @EnvironmentObject private var model: SettingsModel
    @EnvironmentObject private var browsers: BrowserManager
    @State private var target: BrowserTarget?

    init(
        record: DomainRecord,
        onCreateRule: @escaping (DomainRecord, BrowserTarget?) -> Void,
        onShowRule: @escaping (Rule) -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.record = record
        self.onCreateRule = onCreateRule
        self.onShowRule = onShowRule
        self.onRemove = onRemove
        _target = State(initialValue: record.preferredBrowser)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Opened", value: "\(record.visits) time\(record.visits == 1 ? "" : "s")")
                LabeledContent("Last opened") {
                    Text(record.lastOpened, format: .relative(presentation: .named))
                }
            } header: {
                Text(record.domain).font(.title2.weight(.semibold))
            }

            Section("Where its links went") {
                ForEach(record.destinations.sorted { $0.count > $1.count }, id: \.destination) { tally in
                    LabeledContent(browsers.title(for: tally.destination), value: "\(tally.count)×")
                }
            }

            Section("Rule") {
                if let rule = coveringRule(for: record.domain, in: model.settings.rules) {
                    HStack {
                        Text("Handled by “\(rule.name.isEmpty ? "Untitled rule" : rule.name)”")
                        Spacer()
                        Button("Show Rule") { onShowRule(rule) }
                    }
                } else {
                    Picker("Open \(record.domain) with", selection: $target) {
                        Text("Show the picker").tag(BrowserTarget?.none)
                        ForEach(browsers.menuChoices(model.settings)) { Text($0.menuTitle).tag(BrowserTarget?.some($0.target)) }
                    }
                    HStack {
                        Text("Also matches subdomains of \(record.domain).").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Create Rule") { onCreateRule(record, target) }
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }

            Section {
                Button("Remove from List", role: .destructive, action: onRemove)
            }
        }
        .formStyle(.grouped)
    }
}

/// The enabled rule that would catch a link to the domain's front page, if any.
func coveringRule(for domain: String, in rules: [Rule]) -> Rule? {
    guard let url = URL(string: "https://\(domain)/") else { return nil }
    return Router.firstMatchingRule(LinkContext(url: url), in: rules)
}
