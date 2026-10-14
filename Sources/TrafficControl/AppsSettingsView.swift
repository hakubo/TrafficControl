import SwiftUI
import TrafficControlCore

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
                                Image(nsImage: ImageCache.appIcon(atPath: appURL.path)).resizable()
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
