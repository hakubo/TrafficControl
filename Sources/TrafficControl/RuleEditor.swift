import SwiftUI
import TrafficControlCore

struct RuleEditor: View {
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
                    VStack(alignment: .leading, spacing: 4) {
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
                        if let error = condition.regexError {
                            Text("This regex never matches: \(error).")
                                .font(.caption).foregroundStyle(.red)
                        }
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
                if let shadow = rule.shadowingRule(in: model.settings.rules),
                    let sample = rule.sampleURL.flatMap(LinkAddress.of)
                {
                    let name = shadow.rule.name.isEmpty ? "Untitled rule" : shadow.rule.name
                    Text("Rule \(shadow.index + 1) (“\(name)”) comes first and already catches links like \(sample).")
                        .font(.caption).foregroundStyle(.secondary)
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
        guard model.settings.forcePickerWithKey else { return nil }
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
                Toggle(
                    isOn: Binding(
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
