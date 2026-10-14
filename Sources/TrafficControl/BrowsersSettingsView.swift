import SwiftUI
import TrafficControlCore

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
                    onReorder: { model.settings.choiceOrder = $0.map(\.target) }
                )
                .listRowInsets(EdgeInsets())
            } footer: {
                Text("Each profile of Chrome, Brave, Edge or Vivaldi is its own entry.")
                    .font(.caption).foregroundStyle(.secondary)
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
