import SwiftUI
import TrafficControlCore

struct UpdatesSettingsView: View {
    @EnvironmentObject private var updater: UpdaterModel

    var body: some View {
        Form {
            Section {
                PaneHeader(
                    .updates,
                    message: updater.lastCheck.map {
                        "TrafficControl \(appVersion). Last checked \($0.formatted(.relative(presentation: .named)))."
                    } ?? "TrafficControl \(appVersion)."
                ) {
                    Button("Check Now") { updater.checkForUpdates() }
                }
            }

            Section {
                Toggle(
                    isOn: Binding(
                        get: { updater.automaticallyChecks },
                        set: { updater.automaticallyChecks = $0 })
                ) {
                    Text("Check for updates automatically")
                    Text("Look for a new version once a day")
                }
                Toggle(
                    isOn: Binding(
                        get: { updater.automaticallyDownloads },
                        set: { updater.automaticallyDownloads = $0 })
                ) {
                    Text("Download and install automatically")
                    Text("Updates are applied the next time TrafficControl starts")
                }
                .disabled(!updater.automaticallyChecks)
            }
        }
        .formStyle(.grouped)
    }
}
