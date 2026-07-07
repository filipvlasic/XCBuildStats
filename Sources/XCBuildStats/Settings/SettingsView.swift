import SwiftUI
import AppKit

struct SettingsView: View {
    @Bindable var preferences: Preferences
    let model: DashboardViewModel

    @State private var launchAtLogin: Bool = LoginItem.isEnabled
    @State private var showClearConfirm: Bool = false

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            projectsTab
                .tabItem {
                    Label("Projects", systemImage: "folder")
                }
            dataTab
                .tabItem {
                    Label("Data", systemImage: "externaldrive")
                }
        }
        .frame(width: 440, height: 320)
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .disabled(!LoginItem.isSupported)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LoginItem.setEnabled(newValue)
                        launchAtLogin = LoginItem.isEnabled
                    }
                Picker("Menu bar shows", selection: $preferences.menuBarDisplay) {
                    ForEach(MenuBarDisplay.allCases) { display in
                        Text(display.rawValue).tag(display)
                    }
                }
                Toggle("Disable animations", isOn: $preferences.disableAnimations)
            } footer: {
                if !LoginItem.isSupported {
                    Text("Launch at login is available only in the packaged app (not via swift run).")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = LoginItem.isEnabled
        }
    }

    private var projectsTab: some View {
        Form {
            if model.availableProjects.isEmpty {
                Text("No projects recorded yet.")
                    .foregroundStyle(.secondary)
            } else {
                Section {
                    ForEach(model.availableProjects, id: \.self) { project in
                        Toggle(project, isOn: Binding(
                            get: { !preferences.isExcluded(project) },
                            set: { preferences.setExcluded(project, !$0) }
                        ))
                    }
                } footer: {
                    Text("Unchecked projects are excluded from all stats.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var appVersion: String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var dataTab: some View {
        Form {
            LabeledContent("Version", value: appVersion)
            LabeledContent("Database", value: "~/.xcbuildstats/db.sqlite")
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([model.databaseURL])
            }
            Button("Export as CSV…") {
                model.exportCSV()
            }
            Button("Clear database…", role: .destructive) {
                showClearConfirm = true
            }
            .confirmationDialog(
                "Delete all recorded builds and events?",
                isPresented: $showClearConfirm
            ) {
                Button("Delete everything", role: .destructive) {
                    model.clearDatabase()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone. New builds will be collected again from Xcode.")
            }
        }
        .formStyle(.grouped)
    }
}
