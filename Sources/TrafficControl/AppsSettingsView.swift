import SwiftUI
import TrafficControlCore

struct AppsSettingsView: View {
    @EnvironmentObject private var model: SettingsModel
    @EnvironmentObject private var browsers: BrowserManager
    @State private var newWorkspace = ""
    @State private var newTeamID = ""

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

            slackWorkspacesSection
        }
        .formStyle(.grouped)
    }

    /// Slack's app needs each workspace's team ID, which its web links don't include.
    private var slackWorkspacesSection: some View {
        Section {
            ForEach(model.settings.slackWorkspaces.sorted(by: { $0.key < $1.key }), id: \.key) { workspace, teamID in
                HStack {
                    Text(workspace + ".slack.com")
                    Spacer()
                    Text(teamID).foregroundStyle(.secondary).textSelection(.enabled)
                    Button {
                        model.settings.slackWorkspaces[workspace] = nil
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove \(workspace)")
                }
            }
            HStack {
                TextField("Workspace", text: $newWorkspace, prompt: Text("acme.slack.com"))
                    .labelsHidden()
                TextField("Workspace ID", text: $newTeamID, prompt: Text("T0123ABCD"))
                    .labelsHidden()
                    .onSubmit(addWorkspace)
                Button("Add", action: addWorkspace)
                    .disabled(parsedWorkspace == nil)
            }
        } header: {
            Text("Slack workspaces")
        } footer: {
            Text("The Slack app needs each workspace's ID, which links don't include. The first link from a workspace looks it up on slack.com and adds it here. To add one by hand, open the workspace in a browser: the ID is the T… in app.slack.com/client/T…/, and you can paste that whole address.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var parsedWorkspace: (workspace: String, teamID: String)? {
        guard let workspace = AppSettings.slackWorkspace(from: newWorkspace),
            let teamID = AppSettings.slackTeamID(from: newTeamID)
        else { return nil }
        return (workspace, teamID)
    }

    private func addWorkspace() {
        guard let (workspace, teamID) = parsedWorkspace else { return }
        model.settings.slackWorkspaces[workspace] = teamID
        newWorkspace = ""
        newTeamID = ""
    }

    private func mode(of id: String) -> Binding<AppLinkMode> {
        Binding(
            get: { model.settings.appLinkMode(for: id) },
            set: { model.settings.appLinkModes[id] = $0 })
    }
}
