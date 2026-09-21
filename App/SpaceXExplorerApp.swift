import SwiftUI
import SpaceXCore

@main
struct SpaceXExplorerApp: App {
    @AppStorage("dataMode") private var savedMode = DataMode.automatic.rawValue

    private var mode: DataMode {
        if ProcessInfo.processInfo.arguments.contains("--demo") { return .demo }
        return DataMode(rawValue: savedMode) ?? .automatic
    }

    var body: some Scene {
        WindowGroup {
            ExplorerRoot(mode: mode, selectedMode: $savedMode)
                .id(mode.rawValue)
                .tint(.teal)
        }
    }
}

private struct ExplorerRoot: View {
    let mode: DataMode
    @Binding var selectedMode: String
    @State private var repository: SpaceXRepository
    @State private var showsSettings = false

    init(mode: DataMode, selectedMode: Binding<String>) {
        self.mode = mode
        _selectedMode = selectedMode
        let directory = URL.cachesDirectory.appending(path: "SpaceXExplorer/snapshots")
        _repository = State(initialValue: SpaceXRepository(cache: DiskCache(directory: directory), mode: mode))
    }

    var body: some View {
        TabView {
            Tab("Launches", systemImage: "sparkles") {
                NavigationStack {
                    LaunchesView(repository: repository, mode: mode)
                        .toolbar { settingsButton }
                }
            }
            Tab("Rockets", systemImage: "airplane.up.forward") {
                NavigationStack {
                    RocketsView(repository: repository, mode: mode)
                        .toolbar { settingsButton }
                }
            }
        }
        .sheet(isPresented: $showsSettings) {
            NavigationStack {
                Form {
                    Section("Data source") {
                        Picker("Source", selection: $selectedMode) {
                            ForEach(DataMode.allCases, id: \.rawValue) { mode in
                                Text(mode.title).tag(mode.rawValue)
                            }
                        }
                        .accessibilityIdentifier("dataSourcePicker")
                        Text("Automatic tries SpaceX first, then saved results, then local samples if the service is unavailable. Live API only never substitutes samples.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("About this build") {
                        LabeledContent("Design", value: "Liquid Glass")
                        Text("An independent SpaceX explorer. Not affiliated with SpaceX.")
                        Text("Demo missions, dates, outcomes, and specifications are illustrative. The demo video is a historical launch example.")
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Settings")
                .toolbar { Button("Done") { showsSettings = false } }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Settings", systemImage: "gearshape") { showsSettings = true }
        }
    }
}
