import SwiftUI
import TrafficControlCore

struct GeneralSettingsView: View {
    @EnvironmentObject private var model: SettingsModel
    @EnvironmentObject private var browsers: BrowserManager
    @EnvironmentObject private var defaultStatus: DefaultBrowserStatus
    @EnvironmentObject private var history: HistoryModel
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginNeedsApproval = LoginItem.needsApproval

    private var linkCount: Int { history.history.records.values.reduce(0) { $0 + $1.visits } }

    var body: some View {
        Form {
            Section {
                StatusHero(isDefault: defaultStatus.isDefault, links: linkCount, sites: history.history.records.count) {
                    defaultStatus.makeDefault()
                }
                .listRowInsets(EdgeInsets())
            } footer: {
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
                .frame(maxWidth: .infinity)
            }

            Section {
                Picker(selection: $model.settings.defaultBehavior) {
                    ForEach(DefaultBehavior.allCases, id: \.self) { Text($0.label).tag($0) }
                } label: {
                    Text("Behavior")
                    Text("What happens to a link that no rule claims")
                }
                if model.settings.defaultBehavior == .primaryBrowser, model.settings.primaryBrowser == nil {
                    Text("No primary browser is set, so these links show the picker.")
                        .font(.caption).foregroundStyle(.orange)
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
                if model.settings.tabReuse != .off {
                    AutomationPermissionsView()
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
                Toggle(isOn: $model.settings.forcePickerWithKey) {
                    Text("Hold a key while clicking a link to always show the picker")
                    Text("Skips rules, desktop apps and open tabs so you can choose by hand")
                }
                if model.settings.forcePickerWithKey {
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
                Toggle(
                    isOn: Binding(
                        get: { launchAtLogin },
                        set: {
                            LoginItem.setEnabled($0)
                            launchAtLogin = LoginItem.isEnabled
                            loginNeedsApproval = LoginItem.needsApproval
                        })
                ) {
                    Text("Launch at login")
                    Text("Open TrafficControl automatically when you log in")
                }
                if loginNeedsApproval {
                    HStack {
                        Text("macOS needs your approval in Login Items.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items Settings") { LoginItem.openLoginItemsSettings() }
                    }
                }
                Toggle(isOn: $model.settings.showMenuBarIcon) {
                    Text("Show menu bar icon")
                    Text(
                        model.settings.showMenuBarIcon
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
            loginNeedsApproval = LoginItem.needsApproval
        }
    }
}

/// The top of the General pane, in the app icon's colors: night-sky navy, radar rings and the amber cab light.
/// Says whether links reach TrafficControl, and how many it has handled.
private struct StatusHero: View {
    let isDefault: Bool
    let links: Int
    let sites: Int
    let makeDefault: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(isDefault ? "Every link goes through TrafficControl" : "Links aren't reaching TrafficControl")
                    .font(.system(size: 15, weight: .semibold))
                if isDefault {
                    Label("Default browser", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.75))
                } else {
                    HStack(spacing: 10) {
                        Text("Another app is your default browser.")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.75))
                        Button("Make Default Browser", action: makeDefault)
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .controlSize(.small)
                    }
                }
            }
            Spacer(minLength: 12)
            if isDefault, links > 0 {
                HStack(spacing: 18) {
                    stat(links, "links opened")
                    stat(sites, sites == 1 ? "site" : "sites")
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { background }
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value, format: .number)
                .font(.system(size: 20, weight: .semibold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .fixedSize()
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.15, green: 0.22, blue: 0.42), Color(red: 0.06, green: 0.10, blue: 0.22)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            // Radar rings sweeping out from the top-right corner, as on the icon.
            GeometryReader { proxy in
                let center = CGPoint(x: proxy.size.width - 30, y: 10)
                ForEach(1..<7) { ring in
                    Circle()
                        .stroke(.white.opacity(0.06), lineWidth: 1)
                        .frame(width: CGFloat(ring) * 56, height: CGFloat(ring) * 56)
                        .position(center)
                }
            }
            RadialGradient(
                colors: [(isDefault ? Color.amber : .orange).opacity(0.45), .clear],
                center: .topTrailing, startRadius: 0, endRadius: 220)
        }
    }
}
