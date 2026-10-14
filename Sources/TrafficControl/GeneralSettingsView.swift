import SwiftUI
import TrafficControlCore

struct GeneralSettingsView: View {
    @EnvironmentObject private var model: SettingsModel
    @EnvironmentObject private var browsers: BrowserManager
    @EnvironmentObject private var defaultStatus: DefaultBrowserStatus
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginNeedsApproval = LoginItem.needsApproval

    var body: some View {
        Form {
            Section {
                PaneHeader(
                    title: "TrafficControl",
                    message: defaultStatus.isDefault
                        ? "Every link you click passes through here and goes to the right place."
                        : "TrafficControl only sees links once it is your default browser."
                ) {
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
